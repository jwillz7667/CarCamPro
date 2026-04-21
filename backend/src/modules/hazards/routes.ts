import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { HazardsService } from './service.js';

/**
 * Hazard routes.
 *
 *   POST /v1/hazards            — report a sighting (opt-in)
 *   GET  /v1/hazards/nearby     — radial query
 *   POST /v1/hazards/:id/vote   — upvote / downvote
 *
 * POST / vote are authenticated; GET nearby is open to authenticated users
 * but the results never reveal the reporter. Client-side opt-in is enforced
 * by the app (the Settings toggle must be on before `POST /hazards` fires).
 */
export const hazardsRoutes = async (app: FastifyInstance) => {
  const service = new HazardsService({ prisma: app.prisma });
  const typed = app.withTypeProvider<ZodTypeProvider>();

  const hazardTypeEnum = z.enum([
    'EMERGENCY_VEHICLE',
    'POLICE_STOP',
    'ACCIDENT',
    'ROAD_HAZARD',
    'CONSTRUCTION',
    'WEATHER',
  ]);

  typed.route({
    method: 'POST',
    url: '/',
    preHandler: [app.authenticate],
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    schema: {
      body: z.object({
        type: hazardTypeEnum,
        latitude: z.number().gte(-90).lte(90),
        longitude: z.number().gte(-180).lte(180),
        severity: z.number().int().min(1).max(3).default(2),
        confidence: z.number().min(0).max(1),
      }),
      response: {
        201: z.object({
          id: z.string(),
          expiresAt: z.string().datetime(),
        }),
      },
    },
    handler: async (request, reply) => {
      if (!request.auth) throw new Error('unreachable');
      const s = await service.report({
        userId: request.auth.userId,
        type: request.body.type,
        lat: request.body.latitude,
        lng: request.body.longitude,
        severity: request.body.severity,
        confidence: request.body.confidence,
      });
      return reply.status(201).send({
        id: s.id,
        expiresAt: s.expiresAt.toISOString(),
      });
    },
  });

  typed.route({
    method: 'GET',
    url: '/nearby',
    preHandler: [app.authenticate],
    schema: {
      querystring: z.object({
        latitude: z.coerce.number().gte(-90).lte(90),
        longitude: z.coerce.number().gte(-180).lte(180),
        radiusMeters: z.coerce.number().min(50).max(20_000).default(2_000),
        limit: z.coerce.number().int().min(1).max(200).default(50),
        type: hazardTypeEnum.optional(),
      }),
      response: {
        200: z.object({
          sightings: z.array(
            z.object({
              id: z.string(),
              type: hazardTypeEnum,
              severity: z.number().int(),
              confidence: z.number(),
              upvotes: z.number().int(),
              downvotes: z.number().int(),
              expiresAt: z.string().datetime(),
              createdAt: z.string().datetime(),
              distanceMeters: z.number(),
              latitude: z.number(),
              longitude: z.number(),
            }),
          ),
        }),
      },
    },
    handler: async (request) => {
      const rows = await service.nearby({
        lat: request.query.latitude,
        lng: request.query.longitude,
        radiusMeters: request.query.radiusMeters,
        limit: request.query.limit,
        type: request.query.type,
      });
      return {
        sightings: rows.map((r) => ({
          ...r,
          expiresAt: r.expiresAt.toISOString(),
          createdAt: r.createdAt.toISOString(),
        })),
      };
    },
  });

  typed.route({
    method: 'POST',
    url: '/:id/vote',
    preHandler: [app.authenticate],
    schema: {
      params: z.object({ id: z.string().min(26).max(26) }),
      body: z.object({ direction: z.union([z.literal(1), z.literal(-1)]) }),
      response: { 204: z.void() },
    },
    handler: async (request, reply) => {
      if (!request.auth) throw new Error('unreachable');
      await service.vote({
        userId: request.auth.userId,
        sightingId: request.params.id,
        direction: request.body.direction,
      });
      return reply.status(204).send();
    },
  });
};
