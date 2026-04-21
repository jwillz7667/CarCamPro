import { timingSafeEqual } from 'node:crypto';
import type { FastifyRequest } from 'fastify';

import { env } from '../../config/env.js';
import { isIpInAllowlist } from '../../lib/cidr.js';
import { sha256, type Bytes } from '../../lib/crypto.js';
import { Errors } from '../../lib/errors.js';

/**
 * Admin authentication.
 *
 * Two independent gates:
 *   1. API key — `x-admin-api-key: <secret>`. Constant-time-compared against
 *      SHA-256 digests so a length mismatch isn't leaked via timing. Missing
 *      env key => the whole admin surface is 403'd (never 404 — we don't
 *      hide behavior in a security boundary that might be misinterpreted by
 *      internal tools that expect a concrete response).
 *   2. Optional IP allowlist — `ADMIN_IP_ALLOWLIST`. Comma-separated
 *      CIDR ranges. Empty => no IP gate (fine for internal networks).
 *
 * Admin access never overlaps with user-bearer auth: an admin request
 * carries only `x-admin-api-key`, never a user bearer token. Audit log rows
 * are tagged with `action: admin.<verb>` to keep the trail distinct.
 */

const prehashedAdminKey: Bytes | null = env.ADMIN_API_KEY
  ? sha256(env.ADMIN_API_KEY)
  : null;

export const adminAuth = async (request: FastifyRequest): Promise<void> => {
  if (!prehashedAdminKey) {
    throw Errors.forbidden('Admin surface is disabled (ADMIN_API_KEY not configured)');
  }

  const presented = request.headers['x-admin-api-key'];
  if (typeof presented !== 'string' || presented.length === 0) {
    throw Errors.unauthorized('Missing x-admin-api-key header');
  }
  const presentedHash = sha256(presented);
  if (!timingSafeEqual(prehashedAdminKey, presentedHash)) {
    throw Errors.unauthorized('Invalid admin API key');
  }

  if (env.ADMIN_IP_ALLOWLIST.length > 0 && !isIpInAllowlist(request.ip, env.ADMIN_IP_ALLOWLIST)) {
    throw Errors.forbidden(`IP ${request.ip} not in admin allowlist`);
  }
};
