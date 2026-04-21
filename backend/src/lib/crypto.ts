import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * Shared crypto primitives. Centralized so every call site uses the same
 * hash function (important for rotating refresh-token hashes) and so we can
 * swap SHA-256 for something else (Argon2, etc.) in a single edit.
 *
 * Returns `Uint8Array<ArrayBuffer>` rather than `Buffer` so the bytes flow
 * into Prisma `Bytes` columns without the Node-22 generic-parameter mismatch
 * that would otherwise surface under `strict` + `exactOptionalPropertyTypes`.
 */

export type Bytes = Uint8Array<ArrayBuffer>;

/** Copy a Buffer into a fresh Uint8Array-backed ArrayBuffer. */
const toBytes = (b: Buffer): Bytes => {
  const out = new Uint8Array(b.byteLength);
  out.set(b);
  return out;
};

export const sha256 = (input: string | Uint8Array): Bytes => {
  const hash = createHash('sha256');
  hash.update(typeof input === 'string' ? Buffer.from(input, 'utf8') : Buffer.from(input));
  return toBytes(hash.digest());
};

export const hmacSha256 = (key: Uint8Array, message: string | Uint8Array): Bytes => {
  const h = createHmac('sha256', Buffer.from(key));
  h.update(typeof message === 'string' ? Buffer.from(message, 'utf8') : Buffer.from(message));
  return toBytes(h.digest());
};

/**
 * Constant-time comparison. `timingSafeEqual` throws on length mismatch,
 * which is itself a timing side-channel — so we short-circuit first.
 */
export const constantTimeEqual = (a: Uint8Array, b: Uint8Array): boolean => {
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
};

/** Cryptographically random opaque token, base64url-encoded (no padding). */
export const randomToken = (bytes = 32): string => randomBytes(bytes).toString('base64url');

/** Random bytes as a Uint8Array-backed ArrayBuffer. */
export const randomBuffer = (bytes: number): Bytes => toBytes(randomBytes(bytes));
