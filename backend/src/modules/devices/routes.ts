import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { Errors } from '../../lib/errors.js';
import { newId } from '../../lib/ids.js';
import { stripUndefined } from '../../lib/objects.js';

/**
 * Device routes — register / update / deregister push tokens.
 *
 *   POST /v1/devices/register    — create or upsert a device
 *   PATCH /v1/devices/:id        — update push token + metadata
 *   DELETE /v1/devices/:id       — soft-delete
 *   GET /v1/devices              — list current user's devices
 */
export const devicesRoutes = async (app: FastifyInstance) => {
  const typed = app.withTypeProvider<ZodTypeProvider>();

  const deviceDto = z.object({
    id: z.string(),
    name: z.string(),
    model: z.string().nullable(),
    osVersion: z.string().nullable(),
    appVersion: z.string().nullable(),
    appBuild: z.string().nullable(),
    lastSeenAt: z.string().datetime(),
  });

  typed.route({
    method: 'POST',
    url: '/register',
    preHandler: [app.authenticate],
    schema: {
      body: z.object({
        id: z.string().min(26).max(26).optional(),
        name: z.string().min(1).max(64),
        model: z.string().max(64).optional(),
        osVersion: z.string().max(32).optional(),
        appVersion: z.string().max(32).optional(),
        appBuild: z.string().max(32).optional(),
        apnsToken: z.string().max(256).optional(),
      }),
      response: { 200: deviceDto },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const id = request.body.id ?? newId();
      const device = await app.prisma.device.upsert({
        where: { id },
        create: {
          id,
          userId: request.auth.userId,
          name: request.body.name,
          model: request.body.model ?? null,
          osVersion: request.body.osVersion ?? null,
          appVersion: request.body.appVersion ?? null,
          appBuild: request.body.appBuild ?? null,
          apnsToken: request.body.apnsToken ?? null,
        },
        update: stripUndefined({
          name: request.body.name,
          model: request.body.model,
          osVersion: request.body.osVersion,
          appVersion: request.body.appVersion,
          appBuild: request.body.appBuild,
          apnsToken: request.body.apnsToken,
          lastSeenAt: new Date(),
        }),
      });
      return {
        id: device.id,
        name: device.name,
        model: device.model,
        osVersion: device.osVersion,
        appVersion: device.appVersion,
        appBuild: device.appBuild,
        lastSeenAt: device.lastSeenAt.toISOString(),
      };
    },
  });

  typed.route({
    method: 'PATCH',
    url: '/:id',
    preHandler: [app.authenticate],
    schema: {
      params: z.object({ id: z.string().min(26).max(26) }),
      body: z.object({
        name: z.string().min(1).max(64).optional(),
        apnsToken: z.string().max(256).optional(),
        appVersion: z.string().max(32).optional(),
        appBuild: z.string().max(32).optional(),
        osVersion: z.string().max(32).optional(),
      }),
      response: { 200: deviceDto },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const existing = await app.prisma.device.findUnique({ where: { id: request.params.id } });
      if (!existing) throw Errors.notFound('Device');
      if (existing.userId !== request.auth.userId) throw Errors.forbidden();
      const device = await app.prisma.device.update({
        where: { id: request.params.id },
        data: stripUndefined({ ...request.body, lastSeenAt: new Date() }),
      });
      return {
        id: device.id,
        name: device.name,
        model: device.model,
        osVersion: device.osVersion,
        appVersion: device.appVersion,
        appBuild: device.appBuild,
        lastSeenAt: device.lastSeenAt.toISOString(),
      };
    },
  });

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
      const existing = await app.prisma.device.findUnique({ where: { id: request.params.id } });
      if (!existing) throw Errors.notFound('Device');
      if (existing.userId !== request.auth.userId) throw Errors.forbidden();
      await app.prisma.device.update({
        where: { id: request.params.id },
        data: { deletedAt: new Date(), apnsToken: null },
      });
      return reply.status(204).send();
    },
  });

  typed.route({
    method: 'GET',
    url: '/',
    preHandler: [app.authenticate],
    schema: { response: { 200: z.object({ devices: z.array(deviceDto) }) } },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const devices = await app.prisma.device.findMany({
        where: { userId: request.auth.userId, deletedAt: null },
        orderBy: { lastSeenAt: 'desc' },
      });
      return {
        devices: devices.map((d) => ({
          id: d.id,
          name: d.name,
          model: d.model,
          osVersion: d.osVersion,
          appVersion: d.appVersion,
          appBuild: d.appBuild,
          lastSeenAt: d.lastSeenAt.toISOString(),
        })),
      };
    },
  });
};
