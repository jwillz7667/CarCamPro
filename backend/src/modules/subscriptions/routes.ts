import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';

import { Errors } from '../../lib/errors.js';

import {
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
  verifyAppleJws,
} from './apple.js';
import { SubscriptionsService } from './service.js';

/**
 * Subscription routes.
 *
 *   POST /v1/subscriptions/verify                — client-initiated receipt verification
 *   POST /v1/subscriptions/webhook/app-store     — ASSN v2 webhook (public, Apple-signed)
 *   GET  /v1/subscriptions/current               — authenticated lookup
 *
 * The webhook route is unauthenticated (Apple calls it) but requires a valid
 * signed payload. We dedupe via the `notificationUUID` stored in Redis to
 * survive Apple's at-least-once delivery semantics.
 */
export const subscriptionsRoutes = async (app: FastifyInstance) => {
  const service = new SubscriptionsService({ prisma: app.prisma });
  const typed = app.withTypeProvider<ZodTypeProvider>();

  // ─── POST /verify ─────────────────────────────────────
  typed.route({
    method: 'POST',
    url: '/verify',
    preHandler: [app.authenticate],
    schema: {
      body: z.object({
        /// Signed JWS transaction from StoreKit 2's
        /// `Transaction.latest(for:)` or `JWSTransaction`.
        signedTransactionPayload: z.string().min(20),
        /// Optional — signed renewal info from `Product.SubscriptionInfo`.
        signedRenewalInfoPayload: z.string().min(20).optional(),
      }),
      response: {
        200: z.object({
          tier: z.enum(['FREE', 'PRO', 'PREMIUM']),
          status: z.enum(['ACTIVE', 'IN_GRACE_PERIOD', 'IN_BILLING_RETRY', 'EXPIRED', 'REVOKED', 'PAUSED']),
          currentPeriodEndsAt: z.string().datetime(),
          autoRenew: z.boolean(),
        }),
      },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');

      const tx = await verifyAppleJws<JWSTransactionDecodedPayload>(request.body.signedTransactionPayload);

      const renewal = request.body.signedRenewalInfoPayload
        ? await verifyAppleJws<JWSRenewalInfoDecodedPayload>(request.body.signedRenewalInfoPayload)
        : undefined;

      const sub = await service.apply({
        userId: request.auth.userId,
        tx,
        renewal,
        signedPayload: request.body.signedTransactionPayload,
      });

      return {
        tier: sub.tier,
        status: sub.status,
        currentPeriodEndsAt: sub.currentPeriodEndsAt.toISOString(),
        autoRenew: sub.autoRenew,
      };
    },
  });

  // ─── POST /webhook/app-store ──────────────────────────
  typed.route({
    method: 'POST',
    url: '/webhook/app-store',
    config: {
      rateLimit: { max: 600, timeWindow: '1 minute' }, // Apple can burst
    },
    schema: {
      body: z.object({ signedPayload: z.string() }),
    },
    handler: async (request, reply) => {
      const outer = await verifyAppleJws<ResponseBodyV2DecodedPayload>(
        request.body.signedPayload,
      );

      // Idempotency — Apple retries. Record the notificationUUID with a TTL;
      // any duplicate is a no-op 200.
      const idemKey = `assn:v2:${outer.notificationUUID}`;
      const firstSeen = await app.redis.set(idemKey, '1', 'EX', 60 * 60 * 24 * 30, 'NX');
      if (firstSeen !== 'OK') {
        return reply.send({ ok: true, duplicate: true });
      }

      if (!outer.data?.signedTransactionInfo) {
        return reply.send({ ok: true, skipped: 'no transaction info' });
      }

      const tx = await verifyAppleJws<JWSTransactionDecodedPayload>(
        outer.data.signedTransactionInfo,
      );
      const renewal = outer.data.signedRenewalInfo
        ? await verifyAppleJws<JWSRenewalInfoDecodedPayload>(outer.data.signedRenewalInfo)
        : undefined;

      // Which user does this belong to? Look up by the existing subscription;
      // a webhook for an unknown originalTransactionId implies a user who
      // hasn't yet hit the `/verify` endpoint to associate.
      const existing = await app.prisma.subscription.findUnique({
        where: { appleOriginalTransactionId: tx.originalTransactionId },
        select: { userId: true },
      });

      if (!existing) {
        app.log.warn(
          { originalTransactionId: tx.originalTransactionId, type: outer.notificationType },
          'ASSN received for unknown subscription — user has not called /verify yet',
        );
        return reply.send({ ok: true, deferred: true });
      }

      await service.apply({
        userId: existing.userId,
        tx,
        renewal,
        notificationType: outer.notificationType,
        notificationSubtype: outer.subtype,
        signedPayload: outer.data.signedTransactionInfo,
      });

      return reply.send({ ok: true });
    },
  });

  // ─── GET /current ─────────────────────────────────────
  typed.route({
    method: 'GET',
    url: '/current',
    preHandler: [app.authenticate],
    schema: {
      response: {
        200: z.object({
          tier: z.enum(['FREE', 'PRO', 'PREMIUM']),
          status: z.enum(['ACTIVE', 'IN_GRACE_PERIOD', 'IN_BILLING_RETRY', 'EXPIRED', 'REVOKED', 'PAUSED']).nullable(),
          productId: z.string().nullable(),
          currentPeriodEndsAt: z.string().datetime().nullable(),
          autoRenew: z.boolean().nullable(),
        }),
      },
    },
    handler: async (request) => {
      if (!request.auth) throw new Error('unreachable');
      const sub = await service.currentForUser(request.auth.userId);
      if (!sub) {
        return {
          tier: 'FREE' as const,
          status: null,
          productId: null,
          currentPeriodEndsAt: null,
          autoRenew: null,
        };
      }
      return {
        tier: sub.tier,
        status: sub.status,
        productId: sub.productId,
        currentPeriodEndsAt: sub.currentPeriodEndsAt.toISOString(),
        autoRenew: sub.autoRenew,
      };
    },
  });
};

// Silence unused-import warning from `Errors` during the initial scaffold.
void Errors;
