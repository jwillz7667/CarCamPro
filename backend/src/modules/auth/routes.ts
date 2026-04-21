import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { newId } from '../../lib/ids.js';
import { stripUndefined } from '../../lib/objects.js';

import { verifyAppleIdentityToken } from './apple.js';
import { AuthService } from './service.js';

/**
 * Auth routes.
 *
 *   POST /v1/auth/apple        — Sign in with Apple exchange
 *   POST /v1/auth/refresh      — Rotate refresh + access tokens
 *   POST /v1/auth/logout       — Revoke current session
 *   POST /v1/auth/logout-all   — Revoke every session for the user
 *   GET  /v1/auth/me           — Current user profile (quick sanity check)
 *
 * Stricter per-route rate limits are applied to the unauthenticated endpoints
 * to slow down credential-stuffing-style attacks against Apple's nonce flow.
 */
export const authRoutes = async (app: FastifyInstance) => {
  const service = new AuthService({ prisma: app.prisma, redis: app.redis });
  const typed = app.withTypeProvider<ZodTypeProvider>();

  // ─── POST /v1/auth/apple ──────────────────────────────────
  typed.route({
    method: 'POST',
    url: '/apple',
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
    schema: {
      body: z.object({
        identityToken: z.string().min(20),
        nonce: z.string().min(8).optional(),
        displayName: z.string().max(64).optional(),
        deviceId: z.string().min(26).max(26).optional(),
        deviceName: z.string().max(64).optional(),
        deviceModel: z.string().max(64).optional(),
        osVersion: z.string().max(32).optional(),
        appVersion: z.string().max(32).optional(),
      }),
      response: {
        200: z.object({
          accessToken: z.string(),
          refreshToken: z.string(),
          accessTokenExpiresIn: z.number().int(),
          refreshTokenExpiresAt: z.string().datetime(),
          user: z.object({
            id: z.string(),
            email: z.string().nullable(),
            displayName: z.string().nullable(),
            subscriptionTier: z.enum(['FREE', 'PRO', 'PREMIUM']),
          }),
        }),
      },
    },
    handler: async (request, reply) => {
      const body = request.body;
      const claims = await verifyAppleIdentityToken(body.identityToken, body.nonce);

      // Upsert user by Apple principal ID. Email is only present on first login,
      // so only update it if we received one AND we don't already have one.
      const user = await app.prisma.user.upsert({
        where: { applePrincipalId: claims.sub },
        create: {
          id: newId(),
          applePrincipalId: claims.sub,
          email: claims.email ?? null,
          emailVerifiedAt: claims.emailVerified ? new Date() : null,
          displayName: body.displayName ?? null,
        },
        update: stripUndefined({
          email: claims.email,
          emailVerifiedAt: claims.emailVerified ? new Date() : undefined,
          displayName: body.displayName,
          lastActiveAt: new Date(),
        }),
      });

      // Upsert device (optional — native clients always pass one).
      let deviceId: string | undefined;
      if (body.deviceId) {
        await app.prisma.device.upsert({
          where: { id: body.deviceId },
          create: {
            id: body.deviceId,
            userId: user.id,
            name: body.deviceName ?? 'iPhone',
            model: body.deviceModel ?? null,
            osVersion: body.osVersion ?? null,
            appVersion: body.appVersion ?? null,
          },
          update: stripUndefined({
            lastSeenAt: new Date(),
            name: body.deviceName,
            osVersion: body.osVersion,
            appVersion: body.appVersion,
          }),
        });
        deviceId = body.deviceId;
      }

      const created = await service.createSession({
        userId: user.id,
        deviceId,
        userAgent: request.headers['user-agent'] ?? undefined,
        ipAddress: request.ip,
        tier: user.subscriptionTier,
      });

      const accessToken = await app.signAccessToken(created.accessTokenClaims);

      await app.prisma.auditLog.create({
        data: {
          userId: user.id,
          action: 'auth.apple.login',
          ipAddress: request.ip,
          userAgent: request.headers['user-agent'] ?? null,
        },
      });

      return reply.send({
        accessToken,
        refreshToken: created.refreshToken,
        accessTokenExpiresIn: service.accessTtlSeconds(),
        refreshTokenExpiresAt: created.session.expiresAt.toISOString(),
        user: {
          id: user.id,
          email: user.email,
          displayName: user.displayName,
          subscriptionTier: user.subscriptionTier,
        },
      });
    },
  });

  // ─── POST /v1/auth/refresh ────────────────────────────────
  typed.route({
    method: 'POST',
    url: '/refresh',
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    schema: {
      body: z.object({ refreshToken: z.string().min(20) }),
      response: {
        200: z.object({
          accessToken: z.string(),
          refreshToken: z.string(),
          accessTokenExpiresIn: z.number().int(),
          refreshTokenExpiresAt: z.string().datetime(),
        }),
      },
    },
    handler: async (request, reply) => {
      const rotated = await service.refreshSession(request.body.refreshToken);
      const accessToken = await app.signAccessToken(rotated.accessTokenClaims);
      return reply.send({
        accessToken,
        refreshToken: rotated.refreshToken,
        accessTokenExpiresIn: service.accessTtlSeconds(),
        refreshTokenExpiresAt: rotated.session.expiresAt.toISOString(),
      });
    },
  });

  // ─── POST /v1/auth/logout ─────────────────────────────────
  typed.route({
    method: 'POST',
    url: '/logout',
    preHandler: [app.authenticate],
    schema: { response: { 204: z.void() } },
    handler: async (request, reply) => {
      if (!request.auth) throw new Error('unreachable');
      await service.revokeSession(request.auth.sessionId, 'user_logout');
      return reply.status(204).send();
    },
  });

  // ─── POST /v1/auth/logout-all ─────────────────────────────
  typed.route({
    method: 'POST',
    url: '/logout-all',
    preHandler: [app.authenticate],
    schema: { response: { 200: z.object({ revoked: z.number().int() }) } },
    handler: async (request, reply) => {
      if (!request.auth) throw new Error('unreachable');
      const n = await service.revokeAllSessionsForUser(request.auth.userId, 'user_logout_all');
      return reply.send({ revoked: n });
    },
  });

  // ─── GET /v1/auth/me ──────────────────────────────────────
  typed.route({
    method: 'GET',
    url: '/me',
    preHandler: [app.authenticate],
    schema: {
      response: {
        200: z.object({
          id: z.string(),
          email: z.string().nullable(),
          displayName: z.string().nullable(),
          subscriptionTier: z.enum(['FREE', 'PRO', 'PREMIUM']),
          storageQuotaBytes: z.string(),
        }),
      },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const user = await app.prisma.user.findUnique({
        where: { id: request.auth.userId },
        select: {
          id: true, email: true, displayName: true,
          subscriptionTier: true, storageQuotaBytes: true,
        },
      });
      if (!user) throw new Error('user disappeared after auth');
      return {
        ...user,
        storageQuotaBytes: user.storageQuotaBytes.toString(),
      };
    },
  });
};
