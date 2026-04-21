import { describe, expect, it } from 'vitest';

import { encodeGeohash } from '../src/modules/hazards/geohash.js';

/**
 * Reference geohashes from <https://en.wikipedia.org/wiki/Geohash>.
 * Validating against the published constants catches axis-swap regressions.
 */
describe('encodeGeohash', () => {
  it('matches the reference encoding for (57.64911, 10.40744)', () => {
    expect(encodeGeohash(57.64911, 10.40744, 11)).toBe('u4pruydqqvj');
  });

  it('truncates to the requested precision', () => {
    const full = encodeGeohash(37.7749, -122.4194, 11);
    const short = encodeGeohash(37.7749, -122.4194, 6);
    expect(full.startsWith(short)).toBe(true);
  });

  it('rejects invalid precision', () => {
    expect(() => encodeGeohash(0, 0, 0)).toThrow();
    expect(() => encodeGeohash(0, 0, 13)).toThrow();
  });
});
