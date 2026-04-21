import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * Shared crypto primitives. Centralized so every call site uses the same
 * hash function (important for rotating refresh-token hashes) and so we can
 * swap SHA-256 for something else (Argon2, etc.) in a single edit.
 */

export const sha256 = (input: string | Buffer): Buffer => {
  const hash = createHash('sha256');
  hash.update(typeof input === 'string' ? Buffer.from(input, 'utf8') : input);
  return hash.digest();
};

export const hmacSha256 = (key: Buffer, message: string | Buffer): Buffer => {
  const h = createHmac('sha256', key);
  h.update(typeof message === 'string' ? Buffer.from(message, 'utf8') : message);
  return h.digest();
};

/**
 * Constant-time comparison. Pad shorter input so lengths match; `timingSafeEqual`
 * throws when lengths differ, which is itself a timing side-channel.
 */
export const constantTimeEqual = (a: Buffer, b: Buffer): boolean => {
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
};

/** Cryptographically random opaque token, base64url-encoded (no padding). */
export const randomToken = (bytes = 32): string => randomBytes(bytes).toString('base64url');

/** Random bytes. */
export const randomBuffer = (bytes: number): Buffer => randomBytes(bytes);
