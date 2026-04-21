import * as jose from 'jose';

import { env } from '../../config/env.js';
import { Errors } from '../../lib/errors.js';

/**
 * Thin client for Apple's App Store Server API.
 *
 *   Apple docs: https://developer.apple.com/documentation/appstoreserverapi
 *
 * Auth is an ES256 JWT signed with the downloaded .p8 private key:
 *   • iss = issuer ID (App Store Connect team)
 *   • kid = key ID (header)
 *   • bid = bundle ID (payload)
 *   • exp ≤ iat + 20min (Apple rejects longer)
 *
 * The JWT is cached until 60s before expiry so we don't sign one per
 * request. Private-key import is eager: at first use, the .p8 PEM is parsed
 * and stored. If any ASSA credential is missing, every method throws `GONE`
 * so operators know admin-side subscription tooling is off.
 */

const ENV_HOST: Record<'Sandbox' | 'Production', string> = {
  Sandbox:    'https://api.storekit-sandbox.itunes.apple.com',
  Production: 'https://api.storekit.itunes.apple.com',
};

export interface RefundHistoryRecord {
  transactionId: string;
  revocationDate?: number;
  revocationReason?: number;
  refundReason?: string;
  productId: string;
  signedPayload: string;
}

export class AppleAssaClient {
  private cachedToken: { jwt: string; expiresAt: number } | null = null;
  private privateKey: CryptoKey | null = null;

  private requireEnv() {
    if (!env.APPLE_ASSA_KEY_ID || !env.APPLE_ASSA_ISSUER_ID || !env.APPLE_ASSA_PRIVATE_KEY) {
      throw Errors.gone('App Store Server API credentials not configured on this deployment');
    }
    return {
      keyId: env.APPLE_ASSA_KEY_ID,
      issuerId: env.APPLE_ASSA_ISSUER_ID,
      privateKey: env.APPLE_ASSA_PRIVATE_KEY,
    };
  }

  /**
   * Get refund history for a given `originalTransactionId`.
   *
   *   GET /inApps/v2/refund/lookup/{originalTransactionId}
   *
   * Returns the decoded refund records. We do NOT re-verify the signed JWS
   * here — Apple's HTTPS channel is the trust boundary; we already trust
   * our outbound TLS validation. The signed payload is stored verbatim
   * on `subscription_transactions` rows for dispute-time re-verification.
   */
  async getRefundHistory(originalTransactionId: string): Promise<RefundHistoryRecord[]> {
    const token = await this.ensureToken();
    const host = ENV_HOST[env.APPLE_ASSA_ENVIRONMENT];
    const url = `${host}/inApps/v2/refund/lookup/${encodeURIComponent(originalTransactionId)}`;

    const res = await fetch(url, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
    });

    if (res.status === 404) return [];
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw Errors.upstream(`Apple ASSA ${res.status}: ${body.slice(0, 256)}`);
    }

    const body = (await res.json()) as { signedTransactions?: string[] };
    const signedTransactions = body.signedTransactions ?? [];

    const records: RefundHistoryRecord[] = [];
    for (const signedPayload of signedTransactions) {
      try {
        const claims = jose.decodeJwt(signedPayload) as Record<string, unknown>;
        records.push({
          transactionId: String(claims.transactionId ?? ''),
          revocationDate: numOrUndef(claims.revocationDate),
          revocationReason: numOrUndef(claims.revocationReason),
          refundReason: strOrUndef(claims.refundReason),
          productId: String(claims.productId ?? ''),
          signedPayload,
        });
      } catch {
        // Skip malformed records rather than crashing the whole lookup.
      }
    }
    return records;
  }

  /**
   * Extend a subscription's renewal date (for manual dispute resolution,
   * consolation grants, etc).
   *
   *   PUT /inApps/v1/subscriptions/extend/{originalTransactionId}
   */
  async extendRenewalDate(params: {
    originalTransactionId: string;
    extendByDays: number;
    extendReasonCode: 1 | 2 | 3 | 4; // Apple's enumeration
    requestIdentifier: string;
  }): Promise<void> {
    const token = await this.ensureToken();
    const host = ENV_HOST[env.APPLE_ASSA_ENVIRONMENT];
    const url = `${host}/inApps/v1/subscriptions/extend/${encodeURIComponent(
      params.originalTransactionId,
    )}`;

    const res = await fetch(url, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        extendByDays: params.extendByDays,
        extendReasonCode: params.extendReasonCode,
        requestIdentifier: params.requestIdentifier,
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      throw Errors.upstream(`Apple ASSA extend ${res.status}: ${body.slice(0, 256)}`);
    }
  }

  // ─────────────────────────────────────────────────────────
  // Internals
  // ─────────────────────────────────────────────────────────

  private async ensureToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.cachedToken && this.cachedToken.expiresAt > now + 60) {
      return this.cachedToken.jwt;
    }
    const { keyId, issuerId, privateKey } = this.requireEnv();
    if (!this.privateKey) {
      this.privateKey = await jose.importPKCS8(privateKey, 'ES256');
    }

    const expiresAt = now + 60 * 15; // 15 min — under Apple's 20 min cap
    const jwt = await new jose.SignJWT({ bid: env.APPLE_APP_BUNDLE_ID })
      .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
      .setIssuer(issuerId)
      .setIssuedAt(now)
      .setExpirationTime(expiresAt)
      .setAudience('appstoreconnect-v1')
      .sign(this.privateKey);

    this.cachedToken = { jwt, expiresAt };
    return jwt;
  }
}

const numOrUndef = (v: unknown): number | undefined =>
  typeof v === 'number' && Number.isFinite(v) ? v : undefined;
const strOrUndef = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined);
