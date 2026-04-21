import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { env } from '../../config/env.js';
import { newId } from '../../lib/ids.js';

import { ClipsService } from './service.js';

/**
 * Clip routes — all require authentication.
 *
 *   POST /v1/clips/init             — reserve slot + presigned upload URL
 *   POST /v1/clips/:id/complete     — finalize after client-side PUT
 *   GET  /v1/clips                  — paged list
 *   GET  /v1/clips/:id              — single clip metadata
 *   GET  /v1/clips/:id/download     — presigned download URL
 *   DELETE /v1/clips/:id            — soft-delete (protected clips require unlock)
 */
export const clipsRoutes = async (app: FastifyInstance) => {
  const service = new ClipsService({
    prisma: app.prisma,
    storage: app.storage,
    presignTtlSeconds: env.S3_PRESIGN_TTL,
  });
  const typed = app.withTypeProvider<ZodTypeProvider>();

  const clipDto = z.object({
    id: z.string(),
    sizeBytes: z.string(),
    durationSeconds: z.number(),
    resolution: z.string(),
    frameRate: z.number().int(),
    codec: z.string(),
    startedAt: z.string().datetime(),
    endedAt: z.string().datetime(),
    isProtected: z.boolean(),
    hasIncident: z.boolean(),
    incidentSeverity: z.string().nullable(),
    peakGForce: z.number().nullable(),
    uploadStatus: z.enum(['PENDING', 'UPLOADING', 'UPLOADED', 'FAILED', 'PURGED']),
    uploadedAt: z.string().datetime().nullable(),
    createdAt: z.string().datetime(),
  });

  const serializeClip = (c: Awaited<ReturnType<typeof service.getClip>>) => ({
    id: c.id,
    sizeBytes: c.sizeBytes.toString(),
    durationSeconds: c.durationSeconds,
    resolution: c.resolution,
    frameRate: c.frameRate,
    codec: c.codec,
    startedAt: c.startedAt.toISOString(),
    endedAt: c.endedAt.toISOString(),
    isProtected: c.isProtected,
    hasIncident: c.hasIncident,
    incidentSeverity: c.incidentSeverity,
    peakGForce: c.peakGForce,
    uploadStatus: c.uploadStatus,
    uploadedAt: c.uploadedAt?.toISOString() ?? null,
    createdAt: c.createdAt.toISOString(),
  });

  // ─── POST /init ──────────────────────────────────────────
  typed.route({
    method: 'POST',
    url: '/init',
    preHandler: [app.authenticate, app.requireTier('PRO')],
    schema: {
      body: z.object({
        deviceId: z.string().min(26).max(26),
        sizeBytes: z.coerce.bigint().positive(),
        contentType: z.string().default('video/mp4'),
        sha256Base64: z.string().regex(/^[A-Za-z0-9+/=]+$/),
      }),
      response: {
        200: z.object({
          clipId: z.string(),
          uploadUrl: z.string().url(),
          storageKey: z.string(),
          expiresInSeconds: z.number().int(),
        }),
      },
    },
    handler: async (request, reply) => {
      if (!request.auth) throw new Error('unreachable');
      const clipId = newId();
      const result = await service.initUpload({
        clipId,
        userId: request.auth.userId,
        deviceId: request.body.deviceId,
        sizeBytes: request.body.sizeBytes,
        contentType: request.body.contentType,
        sha256Base64: request.body.sha256Base64,
      });
      return reply.send({ clipId, ...result });
    },
  });

  // ─── POST /:id/complete ─────────────────────────────────
  typed.route({
    method: 'POST',
    url: '/:id/complete',
    preHandler: [app.authenticate, app.requireTier('PRO')],
    schema: {
      params: z.object({ id: z.string().min(26).max(26) }),
      body: z.object({
        durationSeconds: z.number().positive(),
        resolution: z.string(),
        frameRate: z.number().int().positive(),
        codec: z.string(),
        startedAt: z.coerce.date(),
        endedAt: z.coerce.date(),
        isProtected: z.boolean().default(false),
        protectionReason: z.string().optional(),
        hasIncident: z.boolean().default(false),
        incidentSeverity: z.enum(['minor', 'moderate', 'severe']).optional(),
        peakGForce: z.number().nonnegative().optional(),
        incidentTimestamp: z.coerce.date().optional(),
        startLatitude: z.number().gte(-90).lte(90).optional(),
        startLongitude: z.number().gte(-180).lte(180).optional(),
        endLatitude: z.number().gte(-90).lte(90).optional(),
        endLongitude: z.number().gte(-180).lte(180).optional(),
        averageSpeedMPH: z.number().nonnegative().optional(),
      }),
      response: { 200: clipDto },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const clip = await service.completeUpload({
        clipId: request.params.id,
        userId: request.auth.userId,
        ...request.body,
      });
      return serializeClip(clip);
    },
  });

  // ─── GET list ───────────────────────────────────────────
  typed.route({
    method: 'GET',
    url: '/',
    preHandler: [app.authenticate],
    schema: {
      querystring: z.object({
        cursor: z.string().min(26).max(26).optional(),
        limit: z.coerce.number().int().min(1).max(100).default(30),
        protectedOnly: z.coerce.boolean().default(false),
      }),
      response: {
        200: z.object({
          clips: z.array(clipDto),
          nextCursor: z.string().nullable(),
        }),
      },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const { cursor, limit, protectedOnly } = request.query;
      const rows = await service.listClips({
        userId: request.auth.userId,
        protectedOnly,
        cursor,
        limit,
      });
      const hasMore = rows.length > limit;
      const items = hasMore ? rows.slice(0, limit) : rows;
      const nextCursor = hasMore ? items[items.length - 1]!.id : null;
      return { clips: items.map(serializeClip), nextCursor };
    },
  });

  // ─── GET single ─────────────────────────────────────────
  typed.route({
    method: 'GET',
    url: '/:id',
    preHandler: [app.authenticate],
    schema: {
      params: z.object({ id: z.string().min(26).max(26) }),
      response: { 200: clipDto },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const clip = await service.getClip({
        userId: request.auth.userId,
        clipId: request.params.id,
      });
      return serializeClip(clip);
    },
  });

  // ─── GET download URL ───────────────────────────────────
  typed.route({
    method: 'GET',
    url: '/:id/download',
    preHandler: [app.authenticate],
    schema: {
      params: z.object({ id: z.string().min(26).max(26) }),
      response: {
        200: z.object({
          url: z.string().url(),
          expiresInSeconds: z.number().int(),
        }),
      },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const url = await service.presignDownload({
        userId: request.auth.userId,
        clipId: request.params.id,
      });
      return { url, expiresInSeconds: env.S3_PRESIGN_TTL };
    },
  });

  // ─── DELETE soft-delete ─────────────────────────────────
  typed.route({
    method: 'DELETE',
    url: '/:id',
    preHandler: [app.authenticate],
    schema: {
      params: z.object({ id: z.string().min(26).max(26) }),
      response: { 204: z.void() },
    },
    handler: async (request, reply) => {
      if (!request.auth) throw new Error('unreachable');
      await service.softDelete({
        userId: request.auth.userId,
        clipId: request.params.id,
      });
      return reply.status(204).send();
    },
  });
};
