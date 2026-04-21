import type { FastifyInstance, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import * as jose from 'jose';

import { env } from '../config/env.js';
import { Errors } from '../lib/errors.js';

export interface AccessTokenClaims {
  sub: string;            // userId
  sid: string;            // sessionId
  tier: 'FREE' | 'PRO' | 'PREMIUM';
  iat: number;
  exp: number;
  iss: string;
  aud: string | string[];
}

export interface AuthContext {
  userId: string;
  sessionId: string;
  tier: AccessTokenClaims['tier'];
}

/**
 * Authentication plugin.
 *
 *   - `app.authenticate`  : required bearer-token auth. Call `request.requireAuth()`
 *                           inside handlers, or register with `preHandler: [app.authenticate]`.
 *   - `app.requireTier`   : factory that produces a pre-handler requiring a tier floor
 *                           (PRO or PREMIUM). Lower tiers get a 402.
 *   - `app.signAccessToken`: signs a JWT access token for the session.
 */
export default fp(async (app: FastifyInstance) => {
  const secret = new TextEncoder().encode(env.JWT_ACCESS_SECRET);

  app.decorate('signAccessToken', async (claims: Omit<AccessTokenClaims, 'iat' | 'exp' | 'iss' | 'aud'>) => {
    return new jose.SignJWT({ ...claims })
      .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
      .setSubject(claims.sub)
      .setIssuer(env.JWT_ISSUER)
      .setAudience(env.JWT_AUDIENCE)
      .setIssuedAt()
      .setExpirationTime(env.JWT_ACCESS_TTL)
      .sign(secret);
  });

  app.decorate('authenticate', async (request: FastifyRequest) => {
    const header = request.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) throw Errors.unauthorized();
    const token = header.slice(7).trim();

    try {
      const { payload } = await jose.jwtVerify(token, secret, {
        issuer: env.JWT_ISSUER,
        audience: env.JWT_AUDIENCE,
        clockTolerance: 5,
      });

      const claims = payload as unknown as AccessTokenClaims;
      if (!claims.sub || !claims.sid) throw Errors.unauthorized();

      // Revocation check — sessions revoked recently are cached in Redis so
      // we don't hit Postgres on every request.
      const revoked = await request.server.redis.get(`session:revoked:${claims.sid}`);
      if (revoked) throw Errors.unauthorized('Session revoked');

      request.auth = { userId: claims.sub, sessionId: claims.sid, tier: claims.tier };
    } catch (err: unknown) {
      if (err instanceof jose.errors.JOSEError) throw Errors.unauthorized();
      throw err;
    }
  });

  app.decorate('requireTier', (min: AccessTokenClaims['tier']) => {
    return async (request: FastifyRequest) => {
      if (!request.auth) throw Errors.unauthorized();
      const order: Record<AccessTokenClaims['tier'], number> = {
        FREE: 0,
        PRO: 1,
        PREMIUM: 2,
      };
      if (order[request.auth.tier] < order[min]) {
        throw Errors.paymentRequired(`This feature requires the ${min} tier.`);
      }
    };
  });
}, {
  name: 'auth',
  dependencies: ['redis'],
});

declare module 'fastify' {
  interface FastifyInstance {
    authenticate: (request: FastifyRequest) => Promise<void>;
    requireTier: (min: AccessTokenClaims['tier']) => (request: FastifyRequest) => Promise<void>;
    signAccessToken: (
      claims: Omit<AccessTokenClaims, 'iat' | 'exp' | 'iss' | 'aud'>,
    ) => Promise<string>;
  }

  interface FastifyRequest {
    auth?: AuthContext;
  }
}
