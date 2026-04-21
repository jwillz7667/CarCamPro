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
 * PDF rendering itself happens in the worker process (see `src/worker.ts`)
 * so the API replica never blocks on PDFKit. This module:
 *   1. Creates (or idempotently looks up) the `IncidentReport` row.
 *   2. Enqueues a BullMQ job under a deterministic `jobId` (one per report)
 *      so duplicate POSTs coalesce.
 *   3. Serves the GET with a presigned download once the worker has
 *      populated `sizeBytes`.
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

      // Idempotency — one report per clip. If a row already exists, we still
      // re-enqueue the render job (the queue itself dedupes on `jobId`), so
      // a retry after a worker crash picks up where we left off.
      const existing = await app.prisma.incidentReport.findUnique({ where: { clipId: clip.id } });
      if (existing) {
        if (existing.sizeBytes === 0) {
          await app.queues.enqueueIncidentReport({
            reportId: existing.id,
            userId: existing.userId,
            clipId: existing.clipId,
            attempt: 1,
          });
        }
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

      await app.queues.enqueueIncidentReport({
        reportId,
        userId: clip.userId,
        clipId: clip.id,
        attempt: 1,
      });

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
