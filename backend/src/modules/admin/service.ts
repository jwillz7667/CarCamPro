import type { PrismaClient, SubscriptionStatus } from '@prisma/client';
import type Redis from 'ioredis';

import { Errors } from '../../lib/errors.js';
import { storageQuotaFor } from '../subscriptions/service.js';

import type { AppleAssaClient } from './appleAssa.js';

/**
 * Admin use cases. Kept separate from routes so each operation has a single
 * well-documented function signature — trivial to unit-test, hard to abuse.
 */
export interface AdminDeps {
  prisma: PrismaClient;
  assa: AppleAssaClient;
}

export class AdminService {
  constructor(private readonly deps: AdminDeps) {}

  // ─── User management ─────────────────────────────────────

  /**
   * Search users by email fragment, display name, or exact ID. Results are
   * bounded (admin UIs must paginate). `deletedAt` is exposed so operators
   * can distinguish users awaiting the 30-day purge.
   */
  async searchUsers(params: {
    query: string;
    limit: number;
  }) {
    const q = params.query.trim();
    const where = q
      ? {
          OR: [
            { id: q },
            { applePrincipalId: q },
            { email: { contains: q, mode: 'insensitive' as const } },
            { displayName: { contains: q, mode: 'insensitive' as const } },
          ],
        }
      : {};
    return this.deps.prisma.user.findMany({
      where,
      take: Math.min(params.limit, 100),
      orderBy: { createdAt: 'desc' },
      include: {
        _count: { select: { clips: true, sessions: true, subscriptions: true } },
      },
    });
  }

  async getUserDetails(userId: string) {
    const user = await this.deps.prisma.user.findUnique({
      where: { id: userId },
      include: {
        subscriptions: { orderBy: { currentPeriodEndsAt: 'desc' } },
        devices: { orderBy: { lastSeenAt: 'desc' }, take: 10 },
        _count: { select: { clips: true, sessions: true, auditLogs: true } },
      },
    });
    if (!user) throw Errors.notFound('User');
    return user;
  }

  /**
   * Revoke every active session for the user. Returns how many were
   * affected. The revocation is written to both Postgres (so it survives
   * restarts) and the Redis cache read by the auth plugin's JWT check.
   */
  async revokeAllSessions(userId: string, reason: string, redis: Redis): Promise<number> {
    const sessions = await this.deps.prisma.session.findMany({
      where: { userId, revokedAt: null },
      select: { id: true },
    });
    if (sessions.length === 0) return 0;

    await this.deps.prisma.session.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date(), revokedReason: `admin:${reason.slice(0, 64)}` },
    });

    // Push revocation into Redis so in-flight JWTs are rejected immediately.
    // TTL is 1h — comfortably longer than the 15m access-token lifetime.
    await Promise.all(
      sessions.map((s) => redis.set(`session:revoked:${s.id}`, '1', 'EX', 60 * 60)),
    );

    return sessions.length;
  }

  /**
   * Override subscription state — used when Apple's ASSN v2 is delayed or
   * a customer-support interaction needs to force the downgrade.
   */
  async overrideSubscription(params: {
    subscriptionId: string;
    status: SubscriptionStatus;
    reason: string;
    actor: string;
  }) {
    const sub = await this.deps.prisma.subscription.findUnique({
      where: { id: params.subscriptionId },
      select: { id: true, userId: true, tier: true, status: true },
    });
    if (!sub) throw Errors.notFound('Subscription');

    // If revoking/expiring, reset the user's denormalized tier + quota.
    const isTerminal = params.status === 'REVOKED' || params.status === 'EXPIRED';
    const userUpdates = isTerminal
      ? { subscriptionTier: 'FREE' as const, storageQuotaBytes: storageQuotaFor('FREE') }
      : null;

    await this.deps.prisma.$transaction([
      this.deps.prisma.subscription.update({
        where: { id: sub.id },
        data: {
          status: params.status,
          ...(params.status === 'EXPIRED' ? { expiredAt: new Date() } : {}),
          ...(params.status === 'REVOKED' ? { cancelledAt: new Date() } : {}),
        },
      }),
      ...(userUpdates
        ? [
            this.deps.prisma.user.update({
              where: { id: sub.userId },
              data: userUpdates,
            }),
          ]
        : []),
      this.deps.prisma.auditLog.create({
        data: {
          userId: sub.userId,
          action: 'admin.subscription.override',
          resource: 'subscription',
          resourceId: sub.id,
          metaJson: {
            previousStatus: sub.status,
            newStatus: params.status,
            reason: params.reason,
            actor: params.actor,
          },
        },
      }),
    ]);

    return this.deps.prisma.subscription.findUniqueOrThrow({ where: { id: sub.id } });
  }

  // ─── Refunds ─────────────────────────────────────────────

  async refundLookup(originalTransactionId: string) {
    const [sub, history] = await Promise.all([
      this.deps.prisma.subscription.findUnique({
        where: { appleOriginalTransactionId: originalTransactionId },
        include: { user: { select: { id: true, email: true, displayName: true } } },
      }),
      this.deps.assa.getRefundHistory(originalTransactionId),
    ]);
    return { subscription: sub, refundHistory: history };
  }

  // ─── Audit + metrics ─────────────────────────────────────

  async tailAudit(params: {
    userId?: string;
    action?: string;
    limit: number;
  }) {
    return this.deps.prisma.auditLog.findMany({
      where: {
        ...(params.userId ? { userId: params.userId } : {}),
        ...(params.action ? { action: { contains: params.action } } : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: Math.min(params.limit, 200),
    });
  }

  async metrics() {
    const [users, activeSubs, clips, pendingIncidentReports, hazardsActive] = await Promise.all([
      this.deps.prisma.user.count({ where: { deletedAt: null } }),
      this.deps.prisma.subscription.count({
        where: { status: { in: ['ACTIVE', 'IN_GRACE_PERIOD'] } },
      }),
      this.deps.prisma.clip.count({ where: { deletedAt: null } }),
      this.deps.prisma.incidentReport.count({ where: { sizeBytes: 0 } }),
      this.deps.prisma.hazardSighting.count({
        where: { expiresAt: { gt: new Date() } },
      }),
    ]);
    return { users, activeSubs, clips, pendingIncidentReports, hazardsActive };
  }
}
