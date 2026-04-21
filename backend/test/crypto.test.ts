import { describe, expect, it } from 'vitest';

import { constantTimeEqual, sha256, hmacSha256, randomBuffer, randomToken } from '../src/lib/crypto.js';

describe('crypto helpers', () => {
  it('sha256 produces the NIST test vector', () => {
    // "abc" → "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    const digest = sha256('abc').toString('hex');
    expect(digest).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  it('hmacSha256 is deterministic with equal keys', () => {
    const key = Buffer.from('shared-secret');
    const a = hmacSha256(key, 'hello').toString('hex');
    const b = hmacSha256(key, 'hello').toString('hex');
    expect(a).toBe(b);
  });

  it('constantTimeEqual returns false for different-length buffers without throwing', () => {
    expect(constantTimeEqual(Buffer.from('abc'), Buffer.from('abcd'))).toBe(false);
  });

  it('constantTimeEqual returns true for equal buffers', () => {
    expect(constantTimeEqual(Buffer.from([1, 2, 3]), Buffer.from([1, 2, 3]))).toBe(true);
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
