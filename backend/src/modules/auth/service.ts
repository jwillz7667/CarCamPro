import type { PrismaClient, Session, SubscriptionTier } from '@prisma/client';
import type Redis from 'ioredis';

import { env } from '../../config/env.js';
import { constantTimeEqual, randomToken, sha256 } from '../../lib/crypto.js';
import { Errors } from '../../lib/errors.js';
import { newId } from '../../lib/ids.js';

/**
 * Auth service — orchestrates session + refresh token lifecycle.
 *
 * Refresh-token design:
 *   - Opaque 32-byte token, base64url-encoded.
 *   - Only the SHA-256 HASH is stored server-side (column `refresh_token_hash`).
 *   - On refresh, the client's plaintext hash must match AND the session
 *     must not be revoked. Old token hash is stashed in `previousTokenHash`
 *     so a replay attack (old token used twice) kills the whole session.
 *
 * Access tokens are short-lived JWTs (see `plugins/auth.ts`). Revocation is
 * propagated via Redis: when a session is revoked, we set
 *   `session:revoked:<sessionId>` = "1" with TTL = remaining access-token life
 * so the stateless JWT check still sees the revocation.
 */

const REFRESH_TTL_DAYS = 30;
const REVOKED_CACHE_TTL_SECONDS = 15 * 60; // covers typical 15m access-token TTL

export interface CreatedSession {
  session: Session;
  accessTokenClaims: {
    sub: string;
    sid: string;
    tier: SubscriptionTier;
  };
  refreshToken: string; // plaintext, return to client once
}

export interface AuthDeps {
  prisma: PrismaClient;
  redis: Redis;
}

export class AuthService {
  constructor(private readonly deps: AuthDeps) {}

  /**
   * Create a fresh session + refresh token for the given user. Returns the
   * plaintext refresh token — the caller must hand this back to the client
   * immediately; it is not retrievable afterwards.
   */
  async createSession(params: {
    userId: string;
    deviceId?: string;
    userAgent?: string;
    ipAddress?: string;
    tier: SubscriptionTier;
  }): Promise<CreatedSession> {
    const refreshToken = randomToken(32);
    const refreshTokenHash = sha256(refreshToken);
    const sessionId = newId();
    const expiresAt = new Date(Date.now() + REFRESH_TTL_DAYS * 24 * 60 * 60 * 1000);

    const session = await this.deps.prisma.session.create({
      data: {
        id: sessionId,
        userId: params.userId,
        deviceId: params.deviceId ?? null,
        refreshTokenHash,
        userAgent: params.userAgent ?? null,
        ipAddress: params.ipAddress ?? null,
        expiresAt,
      },
    });

    return {
      session,
      accessTokenClaims: {
        sub: params.userId,
        sid: sessionId,
        tier: params.tier,
      },
      refreshToken,
    };
  }

  /**
   * Rotate an existing session. Returns a new refresh token and updates the
   * DB row in-place. Detects token-reuse attacks by checking the
   * `previousTokenHash` column — if the client presents an old hash, the
   * session is revoked.
   */
  async refreshSession(refreshToken: string): Promise<CreatedSession> {
    const presentedHash = sha256(refreshToken);

    const session = await this.deps.prisma.session.findFirst({
      where: {
        OR: [{ refreshTokenHash: presentedHash }, { previousTokenHash: presentedHash }],
      },
      include: { user: true },
    });

    if (!session) throw Errors.unauthorized('Invalid refresh token');
    if (session.revokedAt) throw Errors.unauthorized('Session revoked');
    if (session.expiresAt <= new Date()) throw Errors.unauthorized('Session expired');

    // Token-reuse attack: presented hash matches the previous (already-rotated)
    // token. Revoke the whole session and surface an error.
    if (session.previousTokenHash && constantTimeEqual(session.previousTokenHash, presentedHash)) {
      await this.revokeSession(session.id, 'refresh_token_reuse_detected');
      throw Errors.unauthorized('Session revoked — token reuse detected');
    }

    if (!constantTimeEqual(session.refreshTokenHash, presentedHash)) {
      throw Errors.unauthorized('Invalid refresh token');
    }

    const newPlain = randomToken(32);
    const newHash = sha256(newPlain);

    const updated = await this.deps.prisma.session.update({
      where: { id: session.id },
      data: {
        previousTokenHash: session.refreshTokenHash,
        refreshTokenHash: newHash,
        lastUsedAt: new Date(),
      },
    });

    return {
      session: updated,
      accessTokenClaims: {
        sub: session.userId,
        sid: session.id,
        tier: session.user.subscriptionTier,
      },
      refreshToken: newPlain,
    };
  }

  async revokeSession(sessionId: string, reason: string): Promise<void> {
    const now = new Date();
    await this.deps.prisma.session.update({
      where: { id: sessionId },
      data: { revokedAt: now, revokedReason: reason },
    });
    await this.deps.redis.set(
      `session:revoked:${sessionId}`,
      '1',
      'EX',
      REVOKED_CACHE_TTL_SECONDS,
    );
  }

  async revokeAllSessionsForUser(userId: string, reason: string): Promise<number> {
    const now = new Date();
    const sessions = await this.deps.prisma.session.findMany({
      where: { userId, revokedAt: null },
      select: { id: true },
    });
    if (sessions.length === 0) return 0;

    await this.deps.prisma.session.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: now, revokedReason: reason },
    });

    const pipeline = this.deps.redis.pipeline();
    for (const s of sessions) {
      pipeline.set(`session:revoked:${s.id}`, '1', 'EX', REVOKED_CACHE_TTL_SECONDS);
    }
    await pipeline.exec();

    return sessions.length;
  }

  /**
   * Compute the concrete expiry hint exposed on the login response, so the
   * client can refresh preemptively.
   */
  refreshExpiresAt(): Date {
    return new Date(Date.now() + REFRESH_TTL_DAYS * 24 * 60 * 60 * 1000);
  }

  accessTtlSeconds(): number {
    // Parse env.JWT_ACCESS_TTL like "15m" → 900. Keep it simple; jose handles
    // the actual JWT exp claim.
    const ttl = env.JWT_ACCESS_TTL;
    const match = /^(\d+)([smhd])$/.exec(ttl);
    if (!match) return 900;
    const n = Number(match[1]);
    const unit = match[2];
    switch (unit) {
      case 's': return n;
      case 'm': return n * 60;
      case 'h': return n * 60 * 60;
      case 'd': return n * 60 * 60 * 24;
      default:  return 900;
    }
  }
}
