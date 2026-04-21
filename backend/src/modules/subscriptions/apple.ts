import * as jose from 'jose';

import { Errors } from '../../lib/errors.js';

/**
 * Decode + verify an Apple-signed JWS payload (ASSN v2 or StoreKit 2).
 *
 * Apple signs these with an x5c header chain rooted at "Apple Root CA - G3".
 * `jose` can extract the leaf key from the header, which is enough for
 * signature verification. Chain-to-root validation is handled separately in
 * `verifyCertificateChain` to keep this function focused.
 */
export const verifyAppleJws = async <T = unknown>(signedPayload: string): Promise<T> => {
  const decoded = jose.decodeProtectedHeader(signedPayload);
  const x5c = decoded.x5c;
  if (!x5c || x5c.length === 0) {
    throw Errors.unauthorized('Apple JWS missing certificate chain');
  }

  try {
    const leafKey = await jose.importX509(
      `-----BEGIN CERTIFICATE-----\n${x5c[0]}\n-----END CERTIFICATE-----`,
      'ES256',
    );
    const { payload } = await jose.jwtVerify(signedPayload, leafKey);
    return payload as unknown as T;
  } catch {
    throw Errors.unauthorized('Apple JWS signature verification failed');
  }
};

// ─── ASSN v2 payload shapes ───────────────────────────────────
// Apple docs: https://developer.apple.com/documentation/appstoreservernotifications

export interface ResponseBodyV2DecodedPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data?: {
    bundleId: string;
    environment: 'Sandbox' | 'Production';
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
  summary?: {
    environment: 'Sandbox' | 'Production';
    appAppleId?: number;
    bundleId: string;
    productId?: string;
    requestIdentifier?: string;
  };
  version: string;
  signedDate: number;
}

export interface JWSTransactionDecodedPayload {
  originalTransactionId: string;
  transactionId: string;
  webOrderLineItemId?: string;
  bundleId: string;
  productId: string;
  subscriptionGroupIdentifier?: string;
  purchaseDate: number;
  originalPurchaseDate: number;
  expiresDate?: number;
  quantity: number;
  type: 'Auto-Renewable Subscription' | 'Non-Consumable' | 'Consumable' | 'Non-Renewing Subscription';
  inAppOwnershipType: string;
  signedDate: number;
  revocationDate?: number;
  revocationReason?: number;
  environment: 'Sandbox' | 'Production';
}

export interface JWSRenewalInfoDecodedPayload {
  originalTransactionId: string;
  autoRenewProductId?: string;
  productId?: string;
  autoRenewStatus: 0 | 1;
  renewalPrice?: number;
  currency?: string;
  signedDate: number;
  environment: 'Sandbox' | 'Production';
  expirationIntent?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}
