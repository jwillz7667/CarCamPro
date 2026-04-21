import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { env } from '../../config/env.js';
import { Errors } from '../../lib/errors.js';
import { newId } from '../../lib/ids.js';

/**
 * Incident report routes — Premium feature.
 *
 *   POST /v1/incidents/:clipId/report   — enqueue PDF generation
 *   GET  /v1/incidents/:clipId/report   — fetch status + presigned download
 *
 * PDF rendering itself happens in a worker process so the API replica never
 * blocks. This module exposes the creation + retrieval endpoints; the
 * `IncidentReport` row has a `pdfStorageKey` that gets populated once the
 * worker is done. For this initial cut we mark the report as "queued" and
 * return without actually invoking the worker — that wire-up happens in
 * `workers/incident-report.ts` (separate deploy unit) in a follow-up.
 */
export const incidentsRoutes = async (app: FastifyInstance) => {
  const typed = app.withTypeProvider<ZodTypeProvider>();

  typed.route({
    method: 'POST',
    url: '/:clipId/report',
    preHandler: [app.authenticate, app.requireTier('PREMIUM')],
    schema: {
      params: z.object({ clipId: z.string().min(26).max(26) }),
      response: {
        202: z.object({
          reportId: z.string(),
          status: z.literal('QUEUED'),
        }),
      },
    },
    handler: async (request, reply) => {
      if (!request.auth) throw new Error('unreachable');

      const clip = await app.prisma.clip.findUnique({ where: { id: request.params.clipId } });
      if (!clip) throw Errors.notFound('Clip');
      if (clip.userId !== request.auth.userId) throw Errors.forbidden();
      if (clip.uploadStatus !== 'UPLOADED') {
        throw Errors.conflict('Clip must be uploaded before generating a report');
      }

      // Idempotency — one report per clip. Return the existing ID if present.
      const existing = await app.prisma.incidentReport.findUnique({ where: { clipId: clip.id } });
      if (existing) {
        return reply.status(202).send({ reportId: existing.id, status: 'QUEUED' });
      }

      const reportId = newId();
      const storageKey = `users/${clip.userId}/reports/${reportId}.pdf`;

      await app.prisma.incidentReport.create({
        data: {
          id: reportId,
          userId: clip.userId,
          clipId: clip.id,
          pdfStorageKey: storageKey,
          sizeBytes: 0,
          payloadJson: buildPayload(clip),
        },
      });

      // Publish to the worker queue. A future PR adds a real queue (BullMQ /
      // Cloudflare Queues); for now, rely on a periodic scan for reports with
      // sizeBytes == 0.
      app.log.info({ reportId, clipId: clip.id }, 'incident report queued');

      return reply.status(202).send({ reportId, status: 'QUEUED' });
    },
  });

  typed.route({
    method: 'GET',
    url: '/:clipId/report',
    preHandler: [app.authenticate, app.requireTier('PREMIUM')],
    schema: {
      params: z.object({ clipId: z.string().min(26).max(26) }),
      response: {
        200: z.object({
          reportId: z.string(),
          status: z.enum(['QUEUED', 'READY']),
          downloadUrl: z.string().url().nullable(),
          expiresInSeconds: z.number().int().nullable(),
        }),
      },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');

      const report = await app.prisma.incidentReport.findUnique({
        where: { clipId: request.params.clipId },
      });
      if (!report) throw Errors.notFound('Report');
      if (report.userId !== request.auth.userId) throw Errors.forbidden();

      if (report.sizeBytes === 0) {
        return {
          reportId: report.id,
          status: 'QUEUED' as const,
          downloadUrl: null,
          expiresInSeconds: null,
        };
      }

      const url = await app.storage.presignDownload({
        bucket: app.storage.buckets.reports,
        key: report.pdfStorageKey,
      });
      return {
        reportId: report.id,
        status: 'READY' as const,
        downloadUrl: url,
        expiresInSeconds: env.S3_PRESIGN_TTL,
      };
    },
  });
};

/**
 * Snapshot the data the PDF renderer will consume. Stored on the row so
 * re-rendering with a new template produces the same content.
 */
const buildPayload = (clip: {
  id: string;
  startedAt: Date;
  endedAt: Date;
  durationSeconds: number;
  peakGForce: number | null;
  incidentSeverity: string | null;
  startLatitude: unknown;
  startLongitude: unknown;
  endLatitude: unknown;
  endLongitude: unknown;
  averageSpeedMPH: number | null;
  resolution: string;
  codec: string;
}) => ({
  clip: {
    id: clip.id,
    startedAt: clip.startedAt.toISOString(),
    endedAt: clip.endedAt.toISOString(),
    durationSeconds: clip.durationSeconds,
    resolution: clip.resolution,
    codec: clip.codec,
  },
  telemetry: {
    peakGForce: clip.peakGForce,
    severity: clip.incidentSeverity,
    startLatitude: clip.startLatitude,
    startLongitude: clip.startLongitude,
    endLatitude: clip.endLatitude,
    endLongitude: clip.endLongitude,
    averageSpeedMPH: clip.averageSpeedMPH,
  },
});
