/**
 * Geohash encoder. Used for cheap radial prefix-match queries over the
 * hazard layer. A 9-character geohash has ~4.77 m precision.
 *
 * The algorithm is the standard Morton-interleave from Niemeyer (2008).
 * We never decode back to lat/lng server-side — PostGIS does the real
 * geography queries; the geohash is purely an index for bucket selection.
 */

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

export const encodeGeohash = (lat: number, lng: number, precision = 9): string => {
  if (precision < 1 || precision > 12) {
    throw new Error(`Geohash precision ${precision} out of range (1-12)`);
  }

  let latRange: [number, number] = [-90, 90];
  let lngRange: [number, number] = [-180, 180];
  let isEven = true;
  let bit = 0;
  let ch = 0;
  let result = '';

  while (result.length < precision) {
    if (isEven) {
      const mid = (lngRange[0] + lngRange[1]) / 2;
      if (lng >= mid) {
        ch = (ch << 1) | 1;
        lngRange = [mid, lngRange[1]];
      } else {
        ch <<= 1;
        lngRange = [lngRange[0], mid];
      }
    } else {
      const mid = (latRange[0] + latRange[1]) / 2;
      if (lat >= mid) {
        ch = (ch << 1) | 1;
        latRange = [mid, latRange[1]];
      } else {
        ch <<= 1;
        latRange = [latRange[0], mid];
      }
    }
    isEven = !isEven;

    if (bit < 4) {
      bit += 1;
    } else {
      result += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return result;
};
