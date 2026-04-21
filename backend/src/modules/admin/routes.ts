import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { Errors } from '../../lib/errors.js';
import { snapshotQueues } from '../../queues/index.js';

import { adminAuth } from './auth.js';
import { AppleAssaClient } from './appleAssa.js';
import { AdminService } from './service.js';

/**
 * Admin routes — API-key gated, never user-bearer.
 *
 *   GET    /v1/admin/metrics
 *   GET    /v1/admin/queues
 *   GET    /v1/admin/users?q=...&limit=...
 *   GET    /v1/admin/users/:id
 *   POST   /v1/admin/users/:id/revoke-sessions
 *   POST   /v1/admin/users/:id/purge             — trigger immediate hard-purge
 *   POST   /v1/admin/subscriptions/:id/override  — status override
 *   GET    /v1/admin/subscriptions/by-original-tx/:originalTransactionId/refunds
 *   GET    /v1/admin/audit?userId=&action=&limit=
 *
 * Every endpoint runs through `adminAuth` which constant-time compares the
 * `x-admin-api-key` header. Every mutation writes an AuditLog row so a
 * later support investigation can reconstruct who did what, when.
 */
export const adminRoutes = async (app: FastifyInstance) => {
  const typed = app.withTypeProvider<ZodTypeProvider>();

  const assa = new AppleAssaClient();
  const service = new AdminService({ prisma: app.prisma, assa });

  const actor = (request: { headers: { [k: string]: string | string[] | undefined } }) =>
    (request.headers['x-admin-actor'] as string | undefined)?.slice(0, 64) ?? 'unknown';

  // Tier-3 rate limit — admin surface is a sensitive blast radius.
  const adminRouteConfig = { rateLimit: { max: 60, timeWindow: '1 minute' } };

  // ─── Metrics / queues ────────────────────────────────────
  typed.route({
    method: 'GET',
    url: '/metrics',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      response: {
        200: z.object({
          users: z.number().int(),
          activeSubs: z.number().int(),
          clips: z.number().int(),
          pendingIncidentReports: z.number().int(),
          hazardsActive: z.number().int(),
        }),
      },
    },
    handler: async () => service.metrics(),
  });

  typed.route({
    method: 'GET',
    url: '/queues',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      response: {
        200: z.object({
          queues: z.array(
            z.object({
              name: z.string(),
              waiting: z.number().int(),
              active: z.number().int(),
              delayed: z.number().int(),
              failed: z.number().int(),
              completed: z.number().int(),
            }),
          ),
        }),
      },
    },
    handler: async () => ({ queues: await snapshotQueues(app.queues) }),
  });

  // ─── Users ───────────────────────────────────────────────

  const userSummaryDto = z.object({
    id: z.string(),
    email: z.string().nullable(),
    displayName: z.string().nullable(),
    subscriptionTier: z.enum(['FREE', 'PRO', 'PREMIUM']),
    createdAt: z.string().datetime(),
    deletedAt: z.string().datetime().nullable(),
    clipCount: z.number().int(),
    sessionCount: z.number().int(),
    subscriptionCount: z.number().int(),
  });

  typed.route({
    method: 'GET',
    url: '/users',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      querystring: z.object({
        q: z.string().max(320).default(''),
        limit: z.coerce.number().int().min(1).max(100).default(25),
      }),
      response: {
        200: z.object({ users: z.array(userSummaryDto) }),
      },
    },
    handler: async (request) => {
      const rows = await service.searchUsers({ query: request.query.q, limit: request.query.limit });
      return {
        users: rows.map((u) => ({
          id: u.id,
          email: u.email,
          displayName: u.displayName,
          subscriptionTier: u.subscriptionTier,
          createdAt: u.createdAt.toISOString(),
          deletedAt: u.deletedAt?.toISOString() ?? null,
          clipCount: u._count.clips,
          sessionCount: u._count.sessions,
          subscriptionCount: u._count.subscriptions,
        })),
      };
    },
  });

  typed.route({
    method: 'GET',
    url: '/users/:id',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      params: z.object({ id: z.string().length(26) }),
      response: {
        200: z.object({
          id: z.string(),
          email: z.string().nullable(),
          displayName: z.string().nullable(),
          subscriptionTier: z.enum(['FREE', 'PRO', 'PREMIUM']),
          storageQuotaBytes: z.string(),
          createdAt: z.string().datetime(),
          deletedAt: z.string().datetime().nullable(),
          lastActiveAt: z.string().datetime().nullable(),
          subscriptions: z.array(z.object({
            id: z.string(),
            productId: z.string(),
            status: z.string(),
            tier: z.string(),
            currentPeriodEndsAt: z.string().datetime(),
            autoRenew: z.boolean(),
            appleOriginalTransactionId: z.string(),
          })),
          devices: z.array(z.object({
            id: z.string(),
            name: z.string(),
            model: z.string().nullable(),
            osVersion: z.string().nullable(),
            appVersion: z.string().nullable(),
            lastSeenAt: z.string().datetime(),
          })),
          counts: z.object({
            clips: z.number().int(),
            sessions: z.number().int(),
            auditLogs: z.number().int(),
          }),
        }),
      },
    },
    handler: async (request) => {
      const u = await service.getUserDetails(request.params.id);
      return {
        id: u.id,
        email: u.email,
        displayName: u.displayName,
        subscriptionTier: u.subscriptionTier,
        storageQuotaBytes: u.storageQuotaBytes.toString(),
        createdAt: u.createdAt.toISOString(),
        deletedAt: u.deletedAt?.toISOString() ?? null,
        lastActiveAt: u.lastActiveAt?.toISOString() ?? null,
        subscriptions: u.subscriptions.map((s) => ({
          id: s.id,
          productId: s.productId,
          status: s.status,
          tier: s.tier,
          currentPeriodEndsAt: s.currentPeriodEndsAt.toISOString(),
          autoRenew: s.autoRenew,
          appleOriginalTransactionId: s.appleOriginalTransactionId,
        })),
        devices: u.devices.map((d) => ({
          id: d.id,
          name: d.name,
          model: d.model,
          osVersion: d.osVersion,
          appVersion: d.appVersion,
          lastSeenAt: d.lastSeenAt.toISOString(),
        })),
        counts: {
          clips: u._count.clips,
          sessions: u._count.sessions,
          auditLogs: u._count.auditLogs,
        },
      };
    },
  });

  typed.route({
    method: 'POST',
    url: '/users/:id/revoke-sessions',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      params: z.object({ id: z.string().length(26) }),
      body: z.object({ reason: z.string().min(1).max(256) }),
      response: { 200: z.object({ revoked: z.number().int() }) },
    },
    handler: async (request) => {
      const revoked = await service.revokeAllSessions(
        request.params.id,
        `${request.body.reason} · by ${actor(request)}`,
        app.redis,
      );
      await app.prisma.auditLog.create({
        data: {
          userId: request.params.id,
          action: 'admin.sessions.revoke_all',
          ipAddress: request.ip,
          metaJson: { reason: request.body.reason, actor: actor(request), revoked },
        },
      });
      return { revoked };
    },
  });

  typed.route({
    method: 'POST',
    url: '/users/:id/purge',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      params: z.object({ id: z.string().length(26) }),
      body: z.object({
        /// Operator confirms they've spoken to the user / reviewed the
        /// cooldown waiver. Logged verbatim for the audit trail.
        acknowledgement: z.string().min(20).max(512),
      }),
      response: { 202: z.object({ enqueuedJobId: z.string() }) },
    },
    handler: async (request, reply) => {
      const user = await app.prisma.user.findUnique({
        where: { id: request.params.id },
        select: { id: true, deletedAt: true },
      });
      if (!user) throw Errors.notFound('User');
      if (!user.deletedAt) {
        throw Errors.conflict('User must be soft-deleted before hard purge can be scheduled');
      }

      const jobId = await app.queues.enqueueHardPurge({ userId: user.id, batchSize: 1 });
      await app.prisma.auditLog.create({
        data: {
          userId: user.id,
          action: 'admin.purge.requested',
          ipAddress: request.ip,
          metaJson: {
            actor: actor(request),
            acknowledgement: request.body.acknowledgement,
            jobId,
          },
        },
      });
      return reply.status(202).send({ enqueuedJobId: jobId });
    },
  });

  // ─── Subscriptions ───────────────────────────────────────

  typed.route({
    method: 'POST',
    url: '/subscriptions/:id/override',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      params: z.object({ id: z.string().length(26) }),
      body: z.object({
        status: z.enum([
          'ACTIVE',
          'IN_GRACE_PERIOD',
          'IN_BILLING_RETRY',
          'EXPIRED',
          'REVOKED',
          'PAUSED',
        ]),
        reason: z.string().min(1).max(512),
      }),
      response: {
        200: z.object({
          id: z.string(),
          status: z.string(),
          tier: z.string(),
        }),
      },
    },
    handler: async (request) => {
      const sub = await service.overrideSubscription({
        subscriptionId: request.params.id,
        status: request.body.status,
        reason: request.body.reason,
        actor: actor(request),
      });
      return { id: sub.id, status: sub.status, tier: sub.tier };
    },
  });

  typed.route({
    method: 'GET',
    url: '/subscriptions/by-original-tx/:originalTransactionId/refunds',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      params: z.object({ originalTransactionId: z.string().min(1).max(64) }),
      response: {
        200: z.object({
          subscription: z
            .object({
              id: z.string(),
              userId: z.string(),
              productId: z.string(),
              status: z.string(),
              currentPeriodEndsAt: z.string().datetime(),
              user: z.object({
                id: z.string(),
                email: z.string().nullable(),
                displayName: z.string().nullable(),
              }),
            })
            .nullable(),
          refundHistory: z.array(
            z.object({
              transactionId: z.string(),
              revocationDate: z.number().int().optional(),
              revocationReason: z.number().int().optional(),
              refundReason: z.string().optional(),
              productId: z.string(),
            }),
          ),
        }),
      },
    },
    handler: async (request) => {
      const { subscription, refundHistory } = await service.refundLookup(
        request.params.originalTransactionId,
      );
      return {
        subscription: subscription
          ? {
              id: subscription.id,
              userId: subscription.userId,
              productId: subscription.productId,
              status: subscription.status,
              currentPeriodEndsAt: subscription.currentPeriodEndsAt.toISOString(),
              user: {
                id: subscription.user.id,
                email: subscription.user.email,
                displayName: subscription.user.displayName,
              },
            }
          : null,
        // Strip signed JWS from the response — keep it server-side only.
        refundHistory: refundHistory.map((r) => ({
          transactionId: r.transactionId,
          revocationDate: r.revocationDate,
          revocationReason: r.revocationReason,
          refundReason: r.refundReason,
          productId: r.productId,
        })),
      };
    },
  });

  // ─── Audit tail ──────────────────────────────────────────

  typed.route({
    method: 'GET',
    url: '/audit',
    preHandler: [adminAuth],
    config: adminRouteConfig,
    schema: {
      querystring: z.object({
        userId: z.string().length(26).optional(),
        action: z.string().max(64).optional(),
        limit: z.coerce.number().int().min(1).max(200).default(50),
      }),
      response: {
        200: z.object({
          logs: z.array(z.object({
            id: z.string(),
            userId: z.string().nullable(),
            action: z.string(),
            resource: z.string().nullable(),
            resourceId: z.string().nullable(),
            ipAddress: z.string().nullable(),
            userAgent: z.string().nullable(),
            createdAt: z.string().datetime(),
          })),
        }),
      },
    },
    handler: async (request) => {
      const logs = await service.tailAudit({
        userId: request.query.userId,
        action: request.query.action,
        limit: request.query.limit,
      });
      return {
        logs: logs.map((l) => ({
          id: l.id.toString(),
          userId: l.userId,
          action: l.action,
          resource: l.resource,
          resourceId: l.resourceId,
          ipAddress: l.ipAddress,
          userAgent: l.userAgent,
          createdAt: l.createdAt.toISOString(),
        })),
      };
    },
  });
};
