import { describe, expect, it } from 'vitest';

import { constantTimeEqual, sha256, hmacSha256, randomBuffer, randomToken } from '../src/lib/crypto.js';

const hex = (bytes: Uint8Array): string => Buffer.from(bytes).toString('hex');

describe('crypto helpers', () => {
  it('sha256 produces the NIST test vector', () => {
    // "abc" → "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    expect(hex(sha256('abc'))).toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  it('hmacSha256 is deterministic with equal keys', () => {
    const key = new TextEncoder().encode('shared-secret');
    expect(hex(hmacSha256(key, 'hello'))).toBe(hex(hmacSha256(key, 'hello')));
  });

  it('constantTimeEqual returns false for different-length buffers without throwing', () => {
    expect(constantTimeEqual(new TextEncoder().encode('abc'), new TextEncoder().encode('abcd'))).toBe(false);
  });

  it('constantTimeEqual returns true for equal buffers', () => {
    expect(constantTimeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 3]))).toBe(true);
  });

  it('randomBuffer returns the requested length', () => {
    expect(randomBuffer(16).length).toBe(16);
    expect(randomBuffer(32).length).toBe(32);
  });

  it('randomToken returns base64url with expected byte length', () => {
    const t = randomToken(32);
    // base64url encoding of 32 bytes = 43 chars (no padding).
    expect(t.length).toBe(43);
    expect(/^[A-Za-z0-9_-]+$/.test(t)).toBe(true);
  });
});
