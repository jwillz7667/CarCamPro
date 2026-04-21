import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { stripUndefined } from '../../lib/objects.js';

/**
 * User profile routes.
 *
 *   GET    /v1/users/me        — profile snapshot
 *   PATCH  /v1/users/me        — update mutable fields
 *   DELETE /v1/users/me        — soft-delete account (GDPR)
 */
export const usersRoutes = async (app: FastifyInstance) => {
  const typed = app.withTypeProvider<ZodTypeProvider>();

  const userDto = z.object({
    id: z.string(),
    email: z.string().nullable(),
    displayName: z.string().nullable(),
    avatarUrl: z.string().nullable(),
    locale: z.string().nullable(),
    timezone: z.string().nullable(),
    subscriptionTier: z.enum(['FREE', 'PRO', 'PREMIUM']),
    storageQuotaBytes: z.string(),
    createdAt: z.string().datetime(),
  });

  typed.route({
    method: 'GET',
    url: '/me',
    preHandler: [app.authenticate],
    schema: { response: { 200: userDto } },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const user = await app.prisma.user.findUniqueOrThrow({
        where: { id: request.auth.userId },
      });
      return {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        locale: user.locale,
        timezone: user.timezone,
        subscriptionTier: user.subscriptionTier,
        storageQuotaBytes: user.storageQuotaBytes.toString(),
        createdAt: user.createdAt.toISOString(),
      };
    },
  });

  typed.route({
    method: 'PATCH',
    url: '/me',
    preHandler: [app.authenticate],
    schema: {
      body: z.object({
        displayName: z.string().min(1).max(64).optional(),
        locale: z.string().max(16).optional(),
        timezone: z.string().max(64).optional(),
        avatarUrl: z.string().url().max(512).optional(),
      }),
      response: { 200: userDto },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const user = await app.prisma.user.update({
        where: { id: request.auth.userId },
        data: stripUndefined(request.body),
      });
      return {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        locale: user.locale,
        timezone: user.timezone,
        subscriptionTier: user.subscriptionTier,
        storageQuotaBytes: user.storageQuotaBytes.toString(),
        createdAt: user.createdAt.toISOString(),
      };
    },
  });

  typed.route({
    method: 'DELETE',
    url: '/me',
    preHandler: [app.authenticate],
    schema: {
      response: { 202: z.object({ scheduledFor: z.string().datetime() }) },
    },
    handler: async (request, reply) => {
      if (!request.auth) throw new Error('unreachable');

      // Soft-delete the user + revoke all sessions. A nightly job will hard-
      // purge rows + S3 objects after the 30-day cooling-off window so users
      // can change their mind (and we satisfy GDPR Article 17 without
      // creating irreversible data loss footguns).
      const scheduledFor = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await app.prisma.$transaction([
        app.prisma.user.update({
          where: { id: request.auth.userId },
          data: { deletedAt: new Date() },
        }),
        app.prisma.session.updateMany({
          where: { userId: request.auth.userId, revokedAt: null },
          data: { revokedAt: new Date(), revokedReason: 'account_deletion' },
        }),
        app.prisma.auditLog.create({
          data: {
            userId: request.auth.userId,
            action: 'user.delete_requested',
            ipAddress: request.ip,
            userAgent: request.headers['user-agent'] ?? null,
          },
        }),
      ]);

      return reply.status(202).send({ scheduledFor: scheduledFor.toISOString() });
    },
  });
};
