import { describe, expect, it } from 'vitest';

import {
  productIdToTier,
  statusFromNotification,
  storageQuotaFor,
} from '../src/modules/subscriptions/service.js';

describe('subscription helpers', () => {
  describe('productIdToTier', () => {
    it('maps premium SKUs to PREMIUM', () => {
      expect(productIdToTier('com.carcampro.sub.premium.monthly')).toBe('PREMIUM');
      expect(productIdToTier('premium.annual')).toBe('PREMIUM');
    });

    it('maps pro SKUs to PRO', () => {
      expect(productIdToTier('com.carcampro.sub.pro.monthly')).toBe('PRO');
    });

    it('falls back to FREE for unknown SKUs', () => {
      expect(productIdToTier('unknown.product')).toBe('FREE');
    });
  });

  describe('storageQuotaFor', () => {
    it('assigns exponentially increasing quotas', () => {
      const free = storageQuotaFor('FREE');
      const pro = storageQuotaFor('PRO');
      const premium = storageQuotaFor('PREMIUM');
      expect(pro).toBeGreaterThan(free);
      expect(premium).toBeGreaterThan(pro);
    });

    it('free tier is exactly 2 GiB', () => {
      expect(storageQuotaFor('FREE')).toBe(2n * 1024n ** 3n);
    });
  });

  describe('statusFromNotification', () => {
    it('SUBSCRIBED + DID_RENEW → ACTIVE', () => {
      expect(statusFromNotification('SUBSCRIBED', undefined, 'EXPIRED')).toBe('ACTIVE');
      expect(statusFromNotification('DID_RENEW', undefined, 'IN_BILLING_RETRY')).toBe('ACTIVE');
    });

    it('DID_FAIL_TO_RENEW with GRACE_PERIOD subtype → IN_GRACE_PERIOD', () => {
      expect(statusFromNotification('DID_FAIL_TO_RENEW', 'GRACE_PERIOD', 'ACTIVE')).toBe(
        'IN_GRACE_PERIOD',
      );
    });

    it('DID_FAIL_TO_RENEW without subtype → IN_BILLING_RETRY', () => {
      expect(statusFromNotification('DID_FAIL_TO_RENEW', undefined, 'ACTIVE')).toBe(
        'IN_BILLING_RETRY',
      );
    });

    it('EXPIRED and REVOKE map to terminal states', () => {
      expect(statusFromNotification('EXPIRED', undefined, 'ACTIVE')).toBe('EXPIRED');
      expect(statusFromNotification('REVOKE', undefined, 'ACTIVE')).toBe('REVOKED');
    });

    it('renewal-metadata-only notifications preserve the current status', () => {
      expect(
        statusFromNotification('DID_CHANGE_RENEWAL_STATUS', undefined, 'IN_GRACE_PERIOD'),
      ).toBe('IN_GRACE_PERIOD');
    });

    it('unknown notification types are non-destructive', () => {
      expect(statusFromNotification('MYSTERY_TYPE', undefined, 'ACTIVE')).toBe('ACTIVE');
    });
  });
});
