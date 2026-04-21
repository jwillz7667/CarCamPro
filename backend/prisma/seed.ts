/**
 * Database seed.
 *
 * Populates every table (users, sessions, devices, subscriptions,
 * subscription_transactions, clips, clip_thumbnails, incident_reports,
 * hazard_sightings, hazard_votes, daily_salts, audit_logs) with 20
 * fixture users plus supporting rows.
 *
 * Deterministic: the seeded RNG produces the same data on every run, so
 * the E2E harness and iOS contract tests can rely on stable IDs
 * (`seed-user-00` through `seed-user-19`). Re-running is idempotent — the
 * script deletes any prior `seed-` scoped rows before inserting.
 *
 * Usage:  pnpm db:seed
 */
import { createHash, createHmac } from 'node:crypto';

import { PrismaClient, Prisma } from '@prisma/client';
import type {
  HazardType,
  SubscriptionStatus,
  SubscriptionTier,
  UploadStatus,
} from '@prisma/client';

const prisma = new PrismaClient();

// ─── Deterministic helpers ────────────────────────────────

/** Mulberry32: tiny, deterministic, 2^32-period PRNG. Seeded from a string. */
const mulberry32 = (seed: string) => {
  let state = 0;
  for (let i = 0; i < seed.length; i += 1) {
    state = (state + seed.charCodeAt(i) * (i + 1)) >>> 0;
  }
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
};

const rng = mulberry32('carcam-pro-seed-v1');

const pick = <T>(arr: readonly T[]): T => {
  const i = Math.floor(rng() * arr.length);
  return arr[i] as T;
};

const pickInt = (min: number, max: number): number =>
  Math.floor(rng() * (max - min + 1)) + min;

const pickFloat = (min: number, max: number, decimals = 2): number => {
  const v = min + rng() * (max - min);
  const p = 10 ** decimals;
  return Math.round(v * p) / p;
};

/**
 * ULIDs that are sortable AND deterministic. The `ulid()` package uses
 * Math.random + timestamp; we want the same IDs every run, so we derive
 * the entropy half from a SHA-256 of a tag string and encode it in
 * Crockford base-32 manually.
 */
const deterministicUlid = (tag: string): string => {
  // 10-char timestamp prefix: fixed epoch (2026-01-01) so IDs sort naturally
  // against real ULIDs but don't drift between seed runs.
  const prefix = '01JP5R9FC0';
  const digest = createHash('sha256').update(tag).digest();
  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  let out = prefix;
  // 16 chars of entropy = 80 bits — pull 2 base-32 chars per byte.
  for (let i = 0; i < 10; i += 1) {
    const b = digest[i] ?? 0;
    out += alphabet[(b >> 3) & 0x1f];
    out += alphabet[((b & 0x07) << 2) | ((digest[i + 1] ?? 0) >> 6)];
  }
  return out.slice(0, 26);
};

/** SHA-256 hash returned as a Prisma-compatible `Uint8Array<ArrayBuffer>`. */
const sha256 = (s: string | Uint8Array): Uint8Array<ArrayBuffer> => {
  const digest = createHash('sha256')
    .update(typeof s === 'string' ? Buffer.from(s) : Buffer.from(s))
    .digest();
  return bufToBytes(digest);
};

const hmac = (key: Uint8Array, msg: string): Uint8Array<ArrayBuffer> => {
  const digest = createHmac('sha256', Buffer.from(key)).update(msg).digest();
  return bufToBytes(digest);
};

/** Copy a Node Buffer into a fresh Uint8Array whose backing store is a
 *  plain ArrayBuffer — required by Prisma 6 `Bytes` columns under strict
 *  Node 22 typings. */
const bufToBytes = (b: Buffer): Uint8Array<ArrayBuffer> => {
  const out = new Uint8Array(b.byteLength);
  out.set(b);
  return out;
};

// ─── Fixture data ─────────────────────────────────────────

const FIRST_NAMES = [
  'Alex', 'Sam', 'Jordan', 'Taylor', 'Morgan', 'Riley', 'Casey', 'Quinn',
  'Avery', 'Reese', 'Skyler', 'Harper', 'Emerson', 'Rowan', 'Sage', 'Hayden',
  'Finley', 'River', 'Phoenix', 'Kai',
] as const;

const LAST_NAMES = [
  'Chen', 'Patel', 'Nguyen', 'Rodriguez', 'Kim', 'Martinez', 'Johnson',
  'Brown', 'Davis', 'Wilson', 'Anderson', 'Thomas', 'Moore', 'Lee',
  'Silva', 'Park', 'Kumar', 'Okafor', 'Novak', 'Khan',
] as const;

const LOCALES = ['en-US', 'en-GB', 'es-MX', 'fr-CA', 'de-DE', 'pt-BR', 'ja-JP'] as const;
const TIMEZONES = [
  'America/Los_Angeles', 'America/New_York', 'America/Chicago', 'America/Denver',
  'Europe/London', 'Europe/Berlin', 'Asia/Tokyo', 'Australia/Sydney',
] as const;

const IPHONE_MODELS = [
  { model: 'iPhone17,1', name: 'iPhone 16 Pro Max' },
  { model: 'iPhone17,2', name: 'iPhone 16 Pro' },
  { model: 'iPhone17,3', name: 'iPhone 16' },
  { model: 'iPhone16,1', name: 'iPhone 15 Pro Max' },
  { model: 'iPhone16,2', name: 'iPhone 15 Pro' },
] as const;

const OS_VERSIONS = ['26.0', '26.1', '26.2'] as const;
const APP_VERSIONS = ['1.0.0', '1.0.1', '1.1.0'] as const;

const PRODUCT_IDS = {
  FREE: null,
  PRO: 'com.carcampro.sub.pro.monthly',
  PREMIUM: 'com.carcampro.sub.premium.monthly',
} as const;

const STORAGE_QUOTA: Record<SubscriptionTier, bigint> = {
  FREE:    2n * 1024n ** 3n,
  PRO:    10n * 1024n ** 3n,
  PREMIUM: 100n * 1024n ** 4n,
};

// Seed region centered on SF Bay Area — realistic dense-metro sample.
const SEED_CENTER_LAT = 37.7749;
const SEED_CENTER_LNG = -122.4194;

/** Stable city-level jitter within ~25 km of the seed center. */
const jitterLocation = (): { lat: number; lng: number } => ({
  lat: SEED_CENTER_LAT + (rng() - 0.5) * 0.4,
  lng: SEED_CENTER_LNG + (rng() - 0.5) * 0.4,
});

const HAZARD_TYPES: readonly HazardType[] = [
  'EMERGENCY_VEHICLE',
  'POLICE_STOP',
  'ACCIDENT',
  'ROAD_HAZARD',
  'CONSTRUCTION',
  'WEATHER',
];

const RESOLUTIONS = ['720p', '1080p', '4K'] as const;
const CODECS = ['HEVC', 'H.264'] as const;

// ─── Plans per user: mix of tiers + edge cases ────────────
// Index-keyed so each user has a documented, deterministic shape.
interface Plan {
  tier: SubscriptionTier;
  subscriptionStatus: SubscriptionStatus | null;
  devices: number;
  sessions: number;
  clips: number;
  incidents: number;      // number of clips that will be flagged as incidents
  incidentReports: number; // PDFs rendered — only meaningful for PREMIUM
  hazardReports: number;   // hazard sightings authored
  softDeleted: boolean;
}

const PLANS: Plan[] = [
  // 5 PREMIUM users — deep data, including one with a soft-deleted account
  { tier: 'PREMIUM', subscriptionStatus: 'ACTIVE',          devices: 3, sessions: 2, clips: 24, incidents: 4, incidentReports: 3, hazardReports: 5, softDeleted: false },
  { tier: 'PREMIUM', subscriptionStatus: 'ACTIVE',          devices: 2, sessions: 2, clips: 18, incidents: 3, incidentReports: 2, hazardReports: 4, softDeleted: false },
  { tier: 'PREMIUM', subscriptionStatus: 'IN_GRACE_PERIOD', devices: 1, sessions: 1, clips: 12, incidents: 2, incidentReports: 2, hazardReports: 2, softDeleted: false },
  { tier: 'PREMIUM', subscriptionStatus: 'ACTIVE',          devices: 2, sessions: 3, clips: 20, incidents: 5, incidentReports: 4, hazardReports: 3, softDeleted: false },
  { tier: 'PREMIUM', subscriptionStatus: 'REVOKED',         devices: 2, sessions: 1, clips: 10, incidents: 1, incidentReports: 1, hazardReports: 1, softDeleted: true  },

  // 8 PRO users — mainstream, varied churn states
  { tier: 'PRO',     subscriptionStatus: 'ACTIVE',          devices: 2, sessions: 2, clips: 15, incidents: 3, incidentReports: 0, hazardReports: 3, softDeleted: false },
  { tier: 'PRO',     subscriptionStatus: 'ACTIVE',          devices: 1, sessions: 1, clips: 12, incidents: 2, incidentReports: 0, hazardReports: 2, softDeleted: false },
  { tier: 'PRO',     subscriptionStatus: 'ACTIVE',          devices: 1, sessions: 2, clips: 10, incidents: 2, incidentReports: 0, hazardReports: 2, softDeleted: false },
  { tier: 'PRO',     subscriptionStatus: 'ACTIVE',          devices: 2, sessions: 1, clips: 14, incidents: 3, incidentReports: 0, hazardReports: 4, softDeleted: false },
  { tier: 'PRO',     subscriptionStatus: 'IN_BILLING_RETRY', devices: 1, sessions: 1, clips: 8, incidents: 1, incidentReports: 0, hazardReports: 1, softDeleted: false },
  { tier: 'PRO',     subscriptionStatus: 'IN_GRACE_PERIOD', devices: 1, sessions: 1, clips: 6, incidents: 1, incidentReports: 0, hazardReports: 1, softDeleted: false },
  { tier: 'PRO',     subscriptionStatus: 'EXPIRED',         devices: 1, sessions: 0, clips: 4, incidents: 0, incidentReports: 0, hazardReports: 2, softDeleted: false },
  { tier: 'PRO',     subscriptionStatus: 'PAUSED',          devices: 1, sessions: 1, clips: 5, incidents: 1, incidentReports: 0, hazardReports: 1, softDeleted: false },

  // 7 FREE users — shallow data, no clips allowed on server (Pro+ only)
  { tier: 'FREE',    subscriptionStatus: null, devices: 1, sessions: 1, clips: 0, incidents: 0, incidentReports: 0, hazardReports: 1, softDeleted: false },
  { tier: 'FREE',    subscriptionStatus: null, devices: 1, sessions: 1, clips: 0, incidents: 0, incidentReports: 0, hazardReports: 2, softDeleted: false },
  { tier: 'FREE',    subscriptionStatus: null, devices: 1, sessions: 1, clips: 0, incidents: 0, incidentReports: 0, hazardReports: 0, softDeleted: false },
  { tier: 'FREE',    subscriptionStatus: null, devices: 1, sessions: 0, clips: 0, incidents: 0, incidentReports: 0, hazardReports: 1, softDeleted: false },
  { tier: 'FREE',    subscriptionStatus: null, devices: 1, sessions: 1, clips: 0, incidents: 0, incidentReports: 0, hazardReports: 0, softDeleted: false },
  { tier: 'FREE',    subscriptionStatus: null, devices: 1, sessions: 1, clips: 0, incidents: 0, incidentReports: 0, hazardReports: 0, softDeleted: false },
  { tier: 'FREE',    subscriptionStatus: null, devices: 0, sessions: 0, clips: 0, incidents: 0, incidentReports: 0, hazardReports: 0, softDeleted: true  },
];

if (PLANS.length !== 20) {
  throw new Error(`Expected exactly 20 user plans, got ${PLANS.length}`);
}

// ─── Insertion helpers ────────────────────────────────────

const daysAgo = (days: number): Date => new Date(Date.now() - days * 24 * 60 * 60 * 1000);
const minutesAgo = (minutes: number): Date => new Date(Date.now() - minutes * 60 * 1000);

/**
 * Wipe everything previously produced by the seed. Targets the
 * `seed-user-NN` tag-derived IDs + the deterministic ULID space. Uses
 * a cascade off User deletion for most relations; hazards + daily salts
 * are not user-owned so they get explicit cleanup.
 */
const wipeSeedData = async (): Promise<void> => {
  console.log('• wiping any prior seed data');
  // Hazards (anonymous — no FK to User) need explicit cleanup. We tag them
  // with the deterministic ULID prefix `01JP5R9FC0` so we can target only
  // seed-authored rows and leave any manually-created hazards alone.
  await prisma.$executeRaw`DELETE FROM hazard_sightings WHERE id LIKE '01JP5R9FC0%'`;
  await prisma.dailySalt.deleteMany({ where: { dayKey: { in: seededDayKeys() } } });

  // Delete users — all user-owned rows cascade (clips, sessions, devices,
  // subscriptions, incident reports, hazard votes, audit logs with the user
  // get SetNull).
  const userIds = Array.from({ length: PLANS.length }, (_, i) =>
    deterministicUlid(`seed-user-${i.toString().padStart(2, '0')}`),
  );
  await prisma.auditLog.deleteMany({
    where: { userId: { in: userIds } },
  });
  await prisma.user.deleteMany({ where: { id: { in: userIds } } });
};

const seededDayKeys = (): string[] => {
  // Produce the last 3 day keys — covers hazards with today/yesterday/2d ago
  // reporter-hashes.
  const keys: string[] = [];
  for (let offset = 0; offset < 3; offset += 1) {
    keys.push(daysAgo(offset).toISOString().slice(0, 10));
  }
  return keys;
};

// ─── Entrypoint ───────────────────────────────────────────

const main = async () => {
  console.log('═══ CarCam Pro seed ═══');
  await wipeSeedData();

  const saltsByDay = await ensureDailySalts();

  const createdUsers: Array<{
    userId: string;
    tier: SubscriptionTier;
    devices: string[];
    plan: Plan;
  }> = [];

  for (let i = 0; i < PLANS.length; i += 1) {
    const plan = PLANS[i]!;
    const tag = `seed-user-${i.toString().padStart(2, '0')}`;
    const userId = deterministicUlid(tag);
    const first = FIRST_NAMES[i % FIRST_NAMES.length]!;
    const last = LAST_NAMES[i % LAST_NAMES.length]!;
    const email = `seed.${first.toLowerCase()}.${last.toLowerCase()}${i}@example.com`;

    console.log(
      `• user ${i.toString().padStart(2, '0')} (${plan.tier}, ${plan.subscriptionStatus ?? '—'}): ${first} ${last}`,
    );

    await prisma.user.create({
      data: {
        id: userId,
        applePrincipalId: `seed.apple.principal.${userId}`,
        email,
        emailVerifiedAt: plan.tier !== 'FREE' ? daysAgo(pickInt(30, 365)) : daysAgo(pickInt(1, 30)),
        displayName: `${first} ${last}`,
        avatarUrl: `https://cdn.example.com/avatars/${first.toLowerCase()}.png`,
        locale: pick(LOCALES),
        timezone: pick(TIMEZONES),
        subscriptionTier: plan.tier,
        storageQuotaBytes: STORAGE_QUOTA[plan.tier],
        createdAt: daysAgo(pickInt(30, 720)),
        lastActiveAt: plan.softDeleted ? daysAgo(pickInt(31, 60)) : minutesAgo(pickInt(5, 2000)),
        ...(plan.softDeleted ? { deletedAt: daysAgo(pickInt(31, 40)) } : {}),
      },
    });

    const deviceIds = await seedDevices({ userId, plan, tag });
    await seedSessions({ userId, plan, tag, deviceIds });
    const subscription = await seedSubscription({ userId, plan, tag });
    const clipIds = await seedClips({ userId, plan, tag, deviceIds });
    await seedIncidentReports({ userId, plan, tag, clipIds });
    await seedHazardReports({ plan, tag, saltsByDay, userId });
    await seedAuditLogs({ userId, plan, subscription });

    createdUsers.push({ userId, tier: plan.tier, devices: deviceIds, plan });
  }

  // Hazard votes — for every sighting, roll a 30% chance each user upvotes.
  // Skips voters who are soft-deleted or FREE (votes require auth; FREE is
  // fine to allow — just keep the dataset varied). Dedup via the
  // (sightingId, userId) unique index.
  await seedHazardVotes(createdUsers);

  await summarize();
};

// ─── Table-specific seeders ───────────────────────────────

const ensureDailySalts = async (): Promise<Map<string, Uint8Array<ArrayBuffer>>> => {
  const m = new Map<string, Uint8Array<ArrayBuffer>>();
  for (let offset = 0; offset < 3; offset += 1) {
    const dayKey = daysAgo(offset).toISOString().slice(0, 10);
    const salt = sha256(`seed-daily-salt-${dayKey}`);
    await prisma.dailySalt.upsert({
      where: { dayKey },
      create: { dayKey, salt },
      update: { salt },
    });
    m.set(dayKey, salt);
  }
  return m;
};

const seedDevices = async (params: {
  userId: string;
  plan: Plan;
  tag: string;
}): Promise<string[]> => {
  const ids: string[] = [];
  for (let d = 0; d < params.plan.devices; d += 1) {
    const deviceTag = `${params.tag}-device-${d}`;
    const id = deterministicUlid(deviceTag);
    const hw = pick(IPHONE_MODELS);
    await prisma.device.create({
      data: {
        id,
        userId: params.userId,
        apnsToken: Buffer.from(sha256(deviceTag)).toString('hex'),
        name: d === 0 ? `${hw.name}` : `${hw.name} (dashcam)`,
        model: hw.model,
        osVersion: pick(OS_VERSIONS),
        appVersion: pick(APP_VERSIONS),
        appBuild: String(pickInt(100, 999)),
        firstSeenAt: daysAgo(pickInt(20, 400)),
        lastSeenAt: minutesAgo(pickInt(3, 2000)),
      },
    });
    ids.push(id);
  }
  return ids;
};

const seedSessions = async (params: {
  userId: string;
  plan: Plan;
  tag: string;
  deviceIds: string[];
}): Promise<void> => {
  for (let s = 0; s < params.plan.sessions; s += 1) {
    const sessionTag = `${params.tag}-session-${s}`;
    const token = `${sessionTag}-refresh-token`;
    const refreshTokenHash = sha256(token);
    await prisma.session.create({
      data: {
        id: deterministicUlid(sessionTag),
        userId: params.userId,
        deviceId: params.deviceIds[s % Math.max(1, params.deviceIds.length)],
        refreshTokenHash,
        userAgent: 'CarCam Pro/1.0 (iOS 26.0)',
        ipAddress: `203.0.113.${pickInt(1, 254)}`,
        createdAt: daysAgo(pickInt(1, 29)),
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        lastUsedAt: minutesAgo(pickInt(5, 1440)),
      },
    });
  }
};

const seedSubscription = async (params: {
  userId: string;
  plan: Plan;
  tag: string;
}) => {
  const { plan, tag, userId } = params;
  if (plan.tier === 'FREE' || plan.subscriptionStatus === null) return null;

  const productId = PRODUCT_IDS[plan.tier];
  if (!productId) return null;

  const id = deterministicUlid(`${tag}-subscription`);
  const originalTx = `2000000${pickInt(100_000_000, 999_999_999)}`;
  const latestTx = String(Number(originalTx) + pickInt(1, 10));
  const startedAt = daysAgo(pickInt(30, 365));
  const isTerminal = plan.subscriptionStatus === 'EXPIRED' || plan.subscriptionStatus === 'REVOKED';
  const periodEnd = isTerminal
    ? daysAgo(pickInt(1, 10))
    : new Date(Date.now() + pickInt(3, 30) * 24 * 60 * 60 * 1000);

  const subscription = await prisma.subscription.create({
    data: {
      id,
      userId,
      appleOriginalTransactionId: originalTx,
      appleLatestTransactionId: latestTx,
      productId,
      tier: plan.tier,
      status: plan.subscriptionStatus,
      environment: 'Sandbox',
      autoRenew: plan.subscriptionStatus === 'ACTIVE',
      startedAt,
      currentPeriodEndsAt: periodEnd,
      ...(plan.subscriptionStatus === 'REVOKED' ? { cancelledAt: daysAgo(pickInt(1, 15)) } : {}),
      ...(plan.subscriptionStatus === 'EXPIRED' ? { expiredAt: daysAgo(pickInt(1, 10)) } : {}),
      ...(plan.subscriptionStatus === 'IN_GRACE_PERIOD'
        ? { gracePeriodEndsAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) }
        : {}),
    },
  });

  // Transaction log: one entry per renewal, oldest → newest.
  const entries = pickInt(1, 4);
  for (let t = 0; t < entries; t += 1) {
    const txId = String(Number(originalTx) + t);
    const purchase = new Date(startedAt.getTime() + t * 30 * 24 * 60 * 60 * 1000);
    await prisma.subscriptionTransaction.create({
      data: {
        id: deterministicUlid(`${tag}-tx-${t}`),
        subscriptionId: subscription.id,
        appleTransactionId: txId,
        appleNotificationType: t === 0 ? 'SUBSCRIBED' : 'DID_RENEW',
        appleSubtype: null,
        productId,
        purchaseDate: purchase,
        originalPurchaseDate: startedAt,
        signedPayload: `seed.signed.jws.${txId}`,
      },
    });
  }

  return subscription;
};

const seedClips = async (params: {
  userId: string;
  plan: Plan;
  tag: string;
  deviceIds: string[];
}): Promise<string[]> => {
  const { plan, tag, userId, deviceIds } = params;
  if (plan.clips === 0 || deviceIds.length === 0) return [];

  const ids: string[] = [];
  for (let c = 0; c < plan.clips; c += 1) {
    const clipTag = `${tag}-clip-${c}`;
    const clipId = deterministicUlid(clipTag);
    const deviceId = deviceIds[c % deviceIds.length]!;
    const startedAt = daysAgo(pickInt(0, 60));
    const duration = pickInt(30, 180); // 30 s – 3 min
    const endedAt = new Date(startedAt.getTime() + duration * 1000);
    const isIncident = c < plan.incidents;
    const isProtected = isIncident || (rng() < 0.1);
    const resolution = pick(RESOLUTIONS);
    const codec = pick(CODECS);
    const loc = jitterLocation();
    const locEnd = jitterLocation();
    const status: UploadStatus =
      rng() < 0.92 ? 'UPLOADED' : (rng() < 0.5 ? 'PENDING' : 'FAILED');

    const sizeBytes = BigInt(
      Math.round(
        duration *
          (resolution === '4K' ? 2_500_000 : resolution === '1080p' ? 900_000 : 400_000),
      ),
    );

    await prisma.clip.create({
      data: {
        id: clipId,
        userId,
        deviceId,
        storageKey: `users/${userId}/clips/${clipId}.mp4`,
        sizeBytes,
        durationSeconds: duration + pickFloat(0, 0.99),
        resolution,
        frameRate: resolution === '4K' ? 30 : (rng() < 0.5 ? 30 : 60),
        codec,
        startedAt,
        endedAt,
        isProtected,
        protectionReason: isIncident ? 'incident' : (isProtected ? 'manual' : null),
        hasIncident: isIncident,
        incidentSeverity: isIncident ? pick(['minor', 'moderate', 'severe']) : null,
        peakGForce: isIncident ? pickFloat(1.5, 6.5) : null,
        incidentTimestamp: isIncident
          ? new Date(startedAt.getTime() + pickInt(5, duration - 5) * 1000)
          : null,
        startLatitude: new Prisma.Decimal(loc.lat),
        startLongitude: new Prisma.Decimal(loc.lng),
        endLatitude: new Prisma.Decimal(locEnd.lat),
        endLongitude: new Prisma.Decimal(locEnd.lng),
        averageSpeedMPH: pickFloat(10, 75, 1),
        uploadStatus: status,
        uploadedAt: status === 'UPLOADED' ? new Date(endedAt.getTime() + 60_000) : null,
        ...(status === 'FAILED' ? { uploadError: 'presigned URL expired' } : {}),
        createdAt: startedAt,
      },
    });

    if (status === 'UPLOADED') {
      await prisma.clipThumbnail.create({
        data: {
          id: deterministicUlid(`${clipTag}-thumb`),
          clipId,
          storageKey: `users/${userId}/thumbs/${clipId}.jpg`,
          sizeBytes: pickInt(15_000, 120_000),
          widthPx: resolution === '4K' ? 1280 : 640,
          heightPx: resolution === '4K' ? 720 : 360,
        },
      });
    }

    ids.push(clipId);
  }
  return ids;
};

const seedIncidentReports = async (params: {
  userId: string;
  plan: Plan;
  tag: string;
  clipIds: string[];
}): Promise<void> => {
  const { plan, tag, userId, clipIds } = params;
  if (plan.tier !== 'PREMIUM' || plan.incidentReports === 0) return;

  // Only generate reports for clips that are incidents AND uploaded. Pick the
  // first N of those (PLANS defines a deterministic order so `plan.incidents`
  // is always <= `plan.clips`).
  const incidentClips = await prisma.clip.findMany({
    where: { id: { in: clipIds }, hasIncident: true, uploadStatus: 'UPLOADED' },
    orderBy: { startedAt: 'desc' },
    take: plan.incidentReports,
    select: {
      id: true, startedAt: true, endedAt: true, durationSeconds: true,
      resolution: true, codec: true, peakGForce: true, incidentSeverity: true,
      startLatitude: true, startLongitude: true, endLatitude: true, endLongitude: true,
      averageSpeedMPH: true,
    },
  });

  for (let i = 0; i < incidentClips.length; i += 1) {
    const clip = incidentClips[i]!;
    const reportId = deterministicUlid(`${tag}-report-${i}`);
    await prisma.incidentReport.create({
      data: {
        id: reportId,
        userId,
        clipId: clip.id,
        pdfStorageKey: `users/${userId}/reports/${reportId}.pdf`,
        // Non-zero size signals the worker has rendered it — so iOS contract
        // tests that hit /incidents/:id/report see a ready report.
        sizeBytes: pickInt(32_000, 250_000),
        payloadJson: {
          clip: {
            id: clip.id,
            startedAt: clip.startedAt.toISOString(),
            endedAt: clip.endedAt.toISOString(),
            durationSeconds: clip.durationSeconds,
            resolution: clip.resolution,
            codec: clip.codec,
          },
          telemetry: {
            peakGForce: clip.peakGForce,
            severity: clip.incidentSeverity,
            startLatitude: clip.startLatitude ? Number(clip.startLatitude) : null,
            startLongitude: clip.startLongitude ? Number(clip.startLongitude) : null,
            endLatitude: clip.endLatitude ? Number(clip.endLatitude) : null,
            endLongitude: clip.endLongitude ? Number(clip.endLongitude) : null,
            averageSpeedMPH: clip.averageSpeedMPH,
          },
        },
        generatedAt: new Date(clip.endedAt.getTime() + 5 * 60 * 1000),
      },
    });
  }
};

const seedHazardReports = async (params: {
  plan: Plan;
  tag: string;
  saltsByDay: Map<string, Uint8Array<ArrayBuffer>>;
  userId: string;
}): Promise<void> => {
  const { plan, tag, saltsByDay, userId } = params;
  if (plan.hazardReports === 0) return;

  for (let h = 0; h < plan.hazardReports; h += 1) {
    const hazardTag = `${tag}-hazard-${h}`;
    const id = deterministicUlid(hazardTag);
    const ageMin = pickInt(5, 180);
    const createdAt = minutesAgo(ageMin);
    const dayKey = createdAt.toISOString().slice(0, 10);
    const salt = saltsByDay.get(dayKey) ?? saltsByDay.get(
      new Date().toISOString().slice(0, 10),
    )!;
    const reporterHash = hmac(salt, userId);
    const { lat, lng } = jitterLocation();
    const type = pick(HAZARD_TYPES);
    const severity = pickInt(1, 3);
    const confidence = pickFloat(0.55, 0.98, 3);
    const expiresAt = new Date(createdAt.getTime() + 2 * 60 * 60 * 1000);

    // Raw insert (Prisma doesn't model geography). Quoted camelCase columns
    // match Prisma's default mapping.
    await prisma.$executeRaw`
      INSERT INTO hazard_sightings
        (id, type, geohash, "reporterHash", severity, confidence, location,
         upvotes, downvotes, "expiresAt", "createdAt")
      VALUES
        (${id}, ${type}::hazard_type, ${encodeGeohash(lat, lng)}, ${reporterHash},
         ${severity}, ${confidence},
         ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography,
         ${pickInt(0, 12)}, ${pickInt(0, 3)}, ${expiresAt}, ${createdAt})
    `;
  }
};

/** Niemeyer geohash — same 9-char precision as the runtime encoder. */
const encodeGeohash = (lat: number, lng: number, precision = 9): string => {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  let minLat = -90; let maxLat = 90;
  let minLng = -180; let maxLng = 180;
  let bits = 0; let bit = 0; let evenBit = true;
  let out = '';
  while (out.length < precision) {
    if (evenBit) {
      const midLng = (minLng + maxLng) / 2;
      if (lng >= midLng) { bits = (bits << 1) + 1; minLng = midLng; }
      else { bits <<= 1; maxLng = midLng; }
    } else {
      const midLat = (minLat + maxLat) / 2;
      if (lat >= midLat) { bits = (bits << 1) + 1; minLat = midLat; }
      else { bits <<= 1; maxLat = midLat; }
    }
    evenBit = !evenBit;
    bit += 1;
    if (bit === 5) {
      out += base32[bits]!;
      bits = 0; bit = 0;
    }
  }
  return out;
};

const seedHazardVotes = async (
  users: Array<{ userId: string; plan: Plan }>,
): Promise<void> => {
  console.log('• seeding hazard votes');
  const allSightings = await prisma.hazardSighting.findMany({
    where: { id: { startsWith: '01JP5R9FC0' } },
    select: { id: true },
  });

  for (const s of allSightings) {
    for (const u of users) {
      if (u.plan.softDeleted) continue;
      if (rng() < 0.30) {
        const direction: 1 | -1 = rng() < 0.85 ? 1 : -1;
        try {
          await prisma.hazardVote.create({
            data: {
              id: deterministicUlid(`vote-${s.id}-${u.userId}`),
              sightingId: s.id,
              userId: u.userId,
              direction,
            },
          });
        } catch {
          // Unique (sightingId, userId) — already voted, skip.
        }
      }
    }
  }

  // Recompute denormalized upvote/downvote counters so admin dashboards
  // match reality.
  await prisma.$executeRaw`
    UPDATE hazard_sightings SET
      upvotes = COALESCE((SELECT COUNT(*) FROM hazard_votes WHERE "sightingId" = hazard_sightings.id AND direction = 1), 0),
      downvotes = COALESCE((SELECT COUNT(*) FROM hazard_votes WHERE "sightingId" = hazard_sightings.id AND direction = -1), 0)
    WHERE id LIKE '01JP5R9FC0%'
  `;
};

const seedAuditLogs = async (params: {
  userId: string;
  plan: Plan;
  subscription: { id: string; tier: SubscriptionTier } | null;
}) => {
  const { userId, plan, subscription } = params;
  // Every active user gets a login + settings-change trail; terminal users
  // get a revoke or purge-request log for admin-dashboard realism.
  const loginCount = plan.sessions + pickInt(0, 3);
  for (let i = 0; i < loginCount; i += 1) {
    await prisma.auditLog.create({
      data: {
        userId,
        action: 'auth.apple.login',
        ipAddress: `203.0.113.${pickInt(1, 254)}`,
        userAgent: 'CarCam Pro/1.0 (iOS 26.0)',
        createdAt: daysAgo(pickInt(0, 45)),
      },
    });
  }

  if (subscription) {
    await prisma.auditLog.create({
      data: {
        userId,
        action: 'subscription.verified',
        resource: 'subscription',
        resourceId: subscription.id,
        metaJson: { tier: subscription.tier },
        createdAt: daysAgo(pickInt(0, 30)),
      },
    });
  }

  if (plan.softDeleted) {
    await prisma.auditLog.create({
      data: {
        userId,
        action: 'user.delete_requested',
        ipAddress: '203.0.113.42',
        userAgent: 'CarCam Pro/1.0 (iOS 26.0)',
        createdAt: daysAgo(pickInt(31, 40)),
      },
    });
  }
};

// ─── Summary ────────────────────────────────────────────

const summarize = async (): Promise<void> => {
  console.log('\n═══ Seed summary ═══');
  const tables = [
    'users', 'sessions', 'devices', 'subscriptions',
    'subscription_transactions', 'clips', 'clip_thumbnails',
    'incident_reports', 'hazard_sightings', 'hazard_votes',
    'daily_salts', 'audit_logs',
  ] as const;
  for (const t of tables) {
    const rows = await prisma.$queryRawUnsafe<{ n: bigint }[]>(`SELECT COUNT(*)::bigint AS n FROM ${t}`);
    const n = Number(rows[0]?.n ?? 0);
    console.log(`  ${t.padEnd(28)} ${n}`);
  }
};

// ─── Run ────────────────────────────────────────────────

main()
  .catch((err) => {
    console.error('✗ seed failed:', err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
