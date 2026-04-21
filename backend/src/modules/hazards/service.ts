import { Prisma } from '@prisma/client';
import type { PrismaClient, HazardSighting, HazardType } from '@prisma/client';

import { hmacSha256, randomBuffer } from '../../lib/crypto.js';
import { newId } from '../../lib/ids.js';

import { encodeGeohash } from './geohash.js';

/**
 * Hazard layer — opt-in, anonymous, crowdsourced sightings of emergency
 * vehicles, accidents, hazards, etc.
 *
 * Anonymization rules:
 *   - `HazardSighting` rows never reference `userId`.
 *   - Instead, we write `reporterHash = HMAC(dailySalt, userId)`. The daily
 *     salt rotates every 24 h, so yesterday's reporter-hash cannot be
 *     correlated with today's. Rate limits within a day are still possible.
 *   - `HazardVote` rows DO carry `userId` (for dedup) but never join back
 *     to sightings' `reporterHash` — that's enforced at the code layer
 *     since there's no SQL-level way to express "these two tables must
 *     not be joined".
 */

/**
 * Default sighting lifetime. Shorter than most real-world incidents, but
 * long enough to propagate to nearby drivers before decaying. Confirmed /
 * heavily-upvoted sightings get extended in `refreshDecay`.
 */
const DEFAULT_TTL_MS = 2 * 60 * 60 * 1000; // 2h

export interface HazardsDeps {
  prisma: PrismaClient;
}

export class HazardsService {
  constructor(private readonly deps: HazardsDeps) {}

  /**
   * Create a sighting. Lat/lng come in from the client (post-consent) and
   * are quantized to a geohash before writing; the underlying PostGIS
   * `geography(Point, 4326)` column is written via a raw SQL statement
   * because Prisma doesn't model PostGIS types natively.
   */
  async report(params: {
    userId: string;
    type: HazardType;
    lat: number;
    lng: number;
    severity: number;
    confidence: number;
  }): Promise<HazardSighting> {
    const dayKey = this.todayKey();
    const salt = await this.getOrCreateDailySalt(dayKey);
    const reporterHash = hmacSha256(salt, params.userId);
    const geohash = encodeGeohash(params.lat, params.lng, 9);
    const id = newId();
    const expiresAt = new Date(Date.now() + DEFAULT_TTL_MS);

    // Prisma 6 maps Prisma fields to camelCase Postgres columns by default
    // (no `@map` directives in the schema for this model). The camelCase
    // identifiers below are intentionally double-quoted so Postgres preserves
    // case instead of down-casing them to lowercase and failing to resolve.
    await this.deps.prisma.$executeRaw`
      INSERT INTO hazard_sightings
        (id, type, geohash, "reporterHash", severity, confidence, location,
         upvotes, downvotes, "expiresAt", "createdAt")
      VALUES
        (${id}, ${params.type}::hazard_type, ${geohash}, ${reporterHash},
         ${params.severity}, ${params.confidence},
         ST_SetSRID(ST_MakePoint(${params.lng}, ${params.lat}), 4326)::geography,
         1, 0, ${expiresAt}, NOW())
    `;

    const created = await this.deps.prisma.hazardSighting.findUniqueOrThrow({ where: { id } });
    return created;
  }

  /**
   * Radial query — sightings within `radiusMeters` of the given point that
   * haven't yet expired. Ordered by distance, capped at `limit`.
   */
  async nearby(params: {
    lat: number;
    lng: number;
    radiusMeters: number;
    limit: number;
    type?: HazardType | undefined;
  }) {
    // Prisma.sql composes fragments safely — each `${}` becomes a bound
    // parameter, no string concatenation, no SQL injection surface even if
    // `params.type` were user-controlled (it is, via Zod-enum-validated query).
    const typeFilter = params.type
      ? Prisma.sql`AND type = ${params.type}::hazard_type`
      : Prisma.empty;

    const rows = await this.deps.prisma.$queryRaw<
      {
        id: string;
        type: HazardType;
        geohash: string;
        severity: number;
        confidence: number;
        upvotes: number;
        downvotes: number;
        expiresAt: Date;
        createdAt: Date;
        distance_meters: number;
        lat: number;
        lng: number;
      }[]
    >(Prisma.sql`
      SELECT
        id, type, geohash, severity, confidence, upvotes, downvotes,
        "expiresAt", "createdAt",
        ST_Distance(location, ST_SetSRID(ST_MakePoint(${params.lng}, ${params.lat}), 4326)::geography) AS distance_meters,
        ST_Y(location::geometry) AS lat,
        ST_X(location::geometry) AS lng
      FROM hazard_sightings
      WHERE "expiresAt" > NOW()
        ${typeFilter}
        AND ST_DWithin(
          location,
          ST_SetSRID(ST_MakePoint(${params.lng}, ${params.lat}), 4326)::geography,
          ${params.radiusMeters}
        )
      ORDER BY distance_meters ASC
      LIMIT ${params.limit}
    `);

    return rows.map((r) => ({
      id: r.id,
      type: r.type,
      severity: r.severity,
      confidence: r.confidence,
      upvotes: r.upvotes,
      downvotes: r.downvotes,
      expiresAt: r.expiresAt,
      createdAt: r.createdAt,
      distanceMeters: r.distance_meters,
      latitude: r.lat,
      longitude: r.lng,
    }));
  }

  /**
   * Vote. Upserts `(sightingId, userId)` so a user can change their mind;
   * we recompute the denormalized counters with a single raw SQL statement
   * so votes + counters stay consistent under concurrency.
   */
  async vote(params: { userId: string; sightingId: string; direction: 1 | -1 }) {
    await this.deps.prisma.$transaction(async (tx) => {
      const existing = await tx.hazardVote.findUnique({
        where: { sightingId_userId: { sightingId: params.sightingId, userId: params.userId } },
      });

      if (existing?.direction === params.direction) return;

      await tx.hazardVote.upsert({
        where: { sightingId_userId: { sightingId: params.sightingId, userId: params.userId } },
        create: {
          id: newId(),
          userId: params.userId,
          sightingId: params.sightingId,
          direction: params.direction,
        },
        update: { direction: params.direction },
      });

      await tx.$executeRaw`
        UPDATE hazard_sightings SET
          upvotes = (
            SELECT COUNT(*) FROM hazard_votes
            WHERE "sightingId" = ${params.sightingId} AND direction = 1
          ),
          downvotes = (
            SELECT COUNT(*) FROM hazard_votes
            WHERE "sightingId" = ${params.sightingId} AND direction = -1
          ),
          "expiresAt" = GREATEST(
            "expiresAt",
            NOW() + INTERVAL '1 hour' * (
              SELECT COUNT(*) FROM hazard_votes
              WHERE "sightingId" = ${params.sightingId} AND direction = 1
            )
          )
        WHERE id = ${params.sightingId}
      `;
    });
  }

  // MARK: - Internal

  private async getOrCreateDailySalt(dayKey: string): Promise<Uint8Array> {
    const existing = await this.deps.prisma.dailySalt.findUnique({ where: { dayKey } });
    if (existing) return existing.salt;
    const salt = randomBuffer(32);
    try {
      await this.deps.prisma.dailySalt.create({ data: { dayKey, salt } });
      return salt;
    } catch {
      // Another replica raced us — re-read.
      const winner = await this.deps.prisma.dailySalt.findUnique({ where: { dayKey } });
      if (!winner) throw new Error('Failed to race for daily salt');
      return winner.salt;
    }
  }

  private todayKey(): string {
    return new Date().toISOString().slice(0, 10);
  }
}
