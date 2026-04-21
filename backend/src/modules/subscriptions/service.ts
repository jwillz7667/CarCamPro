import type { PrismaClient, SubscriptionStatus, SubscriptionTier } from '@prisma/client';

import { newId } from '../../lib/ids.js';

import type { JWSRenewalInfoDecodedPayload, JWSTransactionDecodedPayload } from './apple.js';

/**
 * Map an App Store product id → our internal subscription tier.
 *
 * App Store product IDs for this app follow the convention
 *   `com.carcampro.sub.{tier}.{period}`   e.g. `com.carcampro.sub.pro.monthly`
 *
 * We match on the exact tier segment (surrounded by dots) rather than
 * `includes` — otherwise `foo.product.bar` would false-positive on "pro".
 * Unknown / legacy SKUs fall through to FREE, which the caller treats as a
 * "not entitled" state.
 */
export const productIdToTier = (productId: string): SubscriptionTier => {
  const segments = productId.toLowerCase().split('.');
  if (segments.includes('premium')) return 'PREMIUM';
  if (segments.includes('pro')) return 'PRO';
  return 'FREE';
};

export const storageQuotaFor = (tier: SubscriptionTier): bigint => {
  switch (tier) {
    case 'FREE':   return 2n * 1024n * 1024n * 1024n;
    case 'PRO':    return 10n * 1024n * 1024n * 1024n;
    case 'PREMIUM': return 100n * 1024n * 1024n * 1024n * 1024n;
  }
};

/**
 * Translate an Apple `notificationType` + `subtype` into our internal
 * subscription status. Not exhaustive — unexpected types log and leave the
 * status unchanged.
 *
 * Apple docs: https://developer.apple.com/documentation/appstoreservernotifications/notificationtype
 */
export const statusFromNotification = (
  type: string,
  subtype: string | undefined,
  current: SubscriptionStatus,
): SubscriptionStatus => {
  switch (type) {
    case 'SUBSCRIBED':
    case 'DID_RENEW':
      return 'ACTIVE';

    case 'DID_FAIL_TO_RENEW':
      return subtype === 'GRACE_PERIOD' ? 'IN_GRACE_PERIOD' : 'IN_BILLING_RETRY';

    case 'EXPIRED':
      return 'EXPIRED';

    case 'REVOKE':
      return 'REVOKED';

    case 'DID_CHANGE_RENEWAL_STATUS':
    case 'DID_CHANGE_RENEWAL_PREF':
    case 'PRICE_INCREASE':
    case 'OFFER_REDEEMED':
      return current; // no state change, just renewal-info update

    default:
      return current;
  }
};

export interface SubscriptionsDeps {
  prisma: PrismaClient;
}

export class SubscriptionsService {
  constructor(private readonly deps: SubscriptionsDeps) {}

  /**
   * Apply a transaction + renewal-info pair (from either a verified receipt
   * or an ASSN v2 notification) to our DB. Upserts the subscription row and
   * appends a transaction log entry.
   */
  async apply(params: {
    userId: string;
    tx: JWSTransactionDecodedPayload;
    renewal?: JWSRenewalInfoDecodedPayload | undefined;
    notificationType?: string | undefined;
    notificationSubtype?: string | undefined;
    signedPayload: string;
  }) {
    const tier = productIdToTier(params.tx.productId);
    const environment = params.tx.environment;
    const purchaseDate = new Date(params.tx.purchaseDate);
    const originalPurchaseDate = new Date(params.tx.originalPurchaseDate);

    // Find or create the subscription (keyed by the immutable
    // originalTransactionId).
    const existing = await this.deps.prisma.subscription.findUnique({
      where: { appleOriginalTransactionId: params.tx.originalTransactionId },
    });

    const nextStatus = statusFromNotification(
      params.notificationType ?? 'SUBSCRIBED',
      params.notificationSubtype,
      existing?.status ?? 'ACTIVE',
    );

    const expiresAt = params.tx.expiresDate
      ? new Date(params.tx.expiresDate)
      : existing?.currentPeriodEndsAt ?? new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    const cancelledAt =
      params.tx.revocationDate !== undefined ? new Date(params.tx.revocationDate) : null;

    const subscription = await this.deps.prisma.subscription.upsert({
      where: { appleOriginalTransactionId: params.tx.originalTransactionId },
      create: {
        id: newId(),
        userId: params.userId,
        appleOriginalTransactionId: params.tx.originalTransactionId,
        appleLatestTransactionId: params.tx.transactionId,
        productId: params.tx.productId,
        tier,
        status: nextStatus,
        environment,
        autoRenew: params.renewal?.autoRenewStatus === 1,
        startedAt: originalPurchaseDate,
        currentPeriodEndsAt: expiresAt,
        cancelledAt,
        gracePeriodEndsAt: params.renewal?.gracePeriodExpiresDate
          ? new Date(params.renewal.gracePeriodExpiresDate)
          : null,
      },
      update: {
        appleLatestTransactionId: params.tx.transactionId,
        productId: params.tx.productId,
        tier,
        status: nextStatus,
        environment,
        autoRenew: params.renewal?.autoRenewStatus === 1,
        currentPeriodEndsAt: expiresAt,
        cancelledAt,
        gracePeriodEndsAt: params.renewal?.gracePeriodExpiresDate
          ? new Date(params.renewal.gracePeriodExpiresDate)
          : null,
        expiredAt: nextStatus === 'EXPIRED' ? new Date() : null,
      },
    });

    // Append transaction log.
    await this.deps.prisma.subscriptionTransaction.upsert({
      where: { appleTransactionId: params.tx.transactionId },
      create: {
        id: newId(),
        subscriptionId: subscription.id,
        appleTransactionId: params.tx.transactionId,
        appleNotificationType: params.notificationType ?? null,
        appleSubtype: params.notificationSubtype ?? null,
        productId: params.tx.productId,
        purchaseDate,
        originalPurchaseDate,
        signedPayload: params.signedPayload,
      },
      update: {},
    });

    // Sync the User row's denormalized tier + quota so the hot path
    // (token issuance, quota checks) doesn't need to re-resolve the sub.
    const activeTier = nextStatus === 'ACTIVE' || nextStatus === 'IN_GRACE_PERIOD'
      ? tier
      : 'FREE';

    await this.deps.prisma.user.update({
      where: { id: params.userId },
      data: {
        subscriptionTier: activeTier,
        storageQuotaBytes: storageQuotaFor(activeTier),
      },
    });

    return subscription;
  }

  async currentForUser(userId: string) {
    return this.deps.prisma.subscription.findFirst({
      where: {
        userId,
        status: { in: ['ACTIVE', 'IN_GRACE_PERIOD', 'IN_BILLING_RETRY'] },
      },
      orderBy: { currentPeriodEndsAt: 'desc' },
    });
  }
}
