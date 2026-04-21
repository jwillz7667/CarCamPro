import * as jose from 'jose';

import { env } from '../../config/env.js';
import { Errors } from '../../lib/errors.js';

/**
 * Sign in with Apple — identity-token verification.
 *
 *   1. Fetch Apple's JWKS (cached by jose's remote JWKS helper).
 *   2. Verify the JWT signature + `iss` + `aud` + `exp`.
 *   3. Return the extracted claims.
 *
 * The `sub` claim is Apple's stable principal identifier — use that as the
 * FK into `User.applePrincipalId`. The email claim may be present on first
 * sign-in only (Apple strips it from subsequent tokens).
 */
const JWKS = jose.createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export interface AppleIdentityClaims {
  sub: string;
  email?: string | undefined;
  emailVerified?: boolean | undefined;
  isPrivateEmail?: boolean | undefined;
  iss: string;
  aud: string;
  iat: number;
  exp: number;
  nonce?: string | undefined;
}

export const verifyAppleIdentityToken = async (
  identityToken: string,
  expectedNonce?: string,
): Promise<AppleIdentityClaims> => {
  try {
    const { payload } = await jose.jwtVerify(identityToken, JWKS, {
      issuer: 'https://appleid.apple.com',
      audience: env.APPLE_APP_BUNDLE_ID,
      clockTolerance: 10,
    });

    const sub = typeof payload.sub === 'string' ? payload.sub : '';
    if (!sub) throw Errors.unauthorized('Apple token missing subject');

    if (expectedNonce && payload['nonce'] !== expectedNonce) {
      throw Errors.unauthorized('Apple token nonce mismatch');
    }

    return {
      sub,
      email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
      emailVerified: coerceBool(payload['email_verified']),
      isPrivateEmail: coerceBool(payload['is_private_email']),
      iss: String(payload.iss),
      aud: String(Array.isArray(payload.aud) ? payload.aud[0] : payload.aud),
      iat: Number(payload.iat),
      exp: Number(payload.exp),
      nonce: typeof payload['nonce'] === 'string' ? payload['nonce'] : undefined,
    };
  } catch (err: unknown) {
    if (err instanceof jose.errors.JOSEError) {
      throw Errors.unauthorized('Invalid Apple identity token');
    }
    throw err;
  }
};

const coerceBool = (v: unknown): boolean | undefined => {
  if (v === undefined) return undefined;
  if (typeof v === 'boolean') return v;
  if (typeof v === 'string') return v === 'true';
  return undefined;
};
