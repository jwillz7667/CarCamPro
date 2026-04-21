/**
 * Seed a single PREMIUM test user + device + session, then mint a
 * long-lived access token the iOS client (or curl) can use to exercise
 * every feature-gated endpoint.
 *
 * Intentionally idempotent — re-running updates the existing row in place
 * so the credentials stay stable across invocations. Prints the creds + a
 * ready-to-paste curl command.
 *
 * LOCAL / DEV ONLY. The long TTL and wide access are dangerous in prod;
 * NODE_ENV must be `development` or `test`.
 */
import { createHash, randomBytes } from 'node:crypto';

import { PrismaClient } from '@prisma/client';
import * as jose from 'jose';

const TEST_USER_ID = '01JTESTUSER000000000000001';       // ULID, 26 chars
const TEST_DEVICE_ID = '01JTESTDEVICE0000000000001';
const TEST_SESSION_ID = '01JTESTSESSION000000000001';
const TEST_SUBSCRIPTION_ID = '01JTESTSUBSCRIPTION000001';
const TEST_APPLE_ORIG_TX = 'test-orig-tx-0000000000000001';

const EMAIL = 'test@carcam.pro';
const DISPLAY_NAME = 'Test Driver';

const NODE_ENV = process.env['NODE_ENV'] ?? 'development';
if (NODE_ENV === 'production') {
  throw new Error('seed-test-user refuses to run in production');
}

const JWT_SECRET = process.env['JWT_ACCESS_SECRET'];
const JWT_ISSUER = process.env['JWT_ISSUER'] ?? 'http://localhost:4000';
const JWT_AUDIENCE = process.env['JWT_AUDIENCE'] ?? 'carcam-ios';
if (!JWT_SECRET) {
  throw new Error('JWT_ACCESS_SECRET missing — run with --env-file=.env');
}

const prisma = new PrismaClient();

const main = async (): Promise<void> => {
  // ── User ────────────────────────────────────────────────
  // PREMIUM tier + Premium-tier storage quota unlocks: 4K, unlimited
  // storage, background recording, incident reports with 60s buffer,
  // cloud backup, and every admin-gated API route.
  await prisma.user.upsert({
    where: { id: TEST_USER_ID },
    create: {
      id: TEST_USER_ID,
      applePrincipalId: `apple-test-${TEST_USER_ID}`,
      email: EMAIL,
      emailVerifiedAt: new Date(),
      displayName: DISPLAY_NAME,
      locale: 'en-US',
      timezone: 'America/Chicago',
      subscriptionTier: 'PREMIUM',
      storageQuotaBytes: BigInt(1024) * BigInt(1024) * BigInt(1024) * BigInt(1024), // 1 TiB
      lastActiveAt: new Date(),
    },
    update: {
      subscriptionTier: 'PREMIUM',
      storageQuotaBytes: BigInt(1024) * BigInt(1024) * BigInt(1024) * BigInt(1024),
      lastActiveAt: new Date(),
      deletedAt: null,
    },
  });

  // ── Device ──────────────────────────────────────────────
  await prisma.device.upsert({
    where: { id: TEST_DEVICE_ID },
    create: {
      id: TEST_DEVICE_ID,
      userId: TEST_USER_ID,
      name: 'Test iPhone 16 Pro',
      model: 'iPhone17,1',
      osVersion: '26.0',
      appVersion: '1.0.0',
      appBuild: '1',
    },
    update: {
      userId: TEST_USER_ID,
      lastSeenAt: new Date(),
      deletedAt: null,
    },
  });

  // ── Subscription (PREMIUM, active, auto-renew on) ──────
  const in30Days = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await prisma.subscription.upsert({
    where: { appleOriginalTransactionId: TEST_APPLE_ORIG_TX },
    create: {
      id: TEST_SUBSCRIPTION_ID,
      userId: TEST_USER_ID,
      appleOriginalTransactionId: TEST_APPLE_ORIG_TX,
      appleLatestTransactionId: TEST_APPLE_ORIG_TX,
      productId: 'pro.carcam.premium.monthly',
      tier: 'PREMIUM',
      status: 'ACTIVE',
      environment: 'Sandbox',
      autoRenew: true,
      startedAt: new Date(),
      currentPeriodEndsAt: in30Days,
    },
    update: {
      userId: TEST_USER_ID,
      status: 'ACTIVE',
      tier: 'PREMIUM',
      autoRenew: true,
      currentPeriodEndsAt: in30Days,
      cancelledAt: null,
      expiredAt: null,
    },
  });

  // ── Session + refresh token ────────────────────────────
  // The refresh token is a 32-byte base64url string; we store its SHA-256
  // in the Session row and hand back the plaintext for the iOS client.
  const refreshTokenPlain = randomBytes(32).toString('base64url');
  const refreshTokenHash = createHash('sha256').update(refreshTokenPlain).digest();
  const in30DaysSession = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  await prisma.session.upsert({
    where: { id: TEST_SESSION_ID },
    create: {
      id: TEST_SESSION_ID,
      userId: TEST_USER_ID,
      deviceId: TEST_DEVICE_ID,
      refreshTokenHash,
      userAgent: 'CarCamPro-Seed-Test/1.0',
      expiresAt: in30DaysSession,
    },
    update: {
      refreshTokenHash,
      userId: TEST_USER_ID,
      deviceId: TEST_DEVICE_ID,
      expiresAt: in30DaysSession,
      revokedAt: null,
      revokedReason: null,
      lastUsedAt: new Date(),
    },
  });

  // ── Access token (365-day TTL, for manual/QA use) ──────
  const secret = new TextEncoder().encode(JWT_SECRET);
  const accessToken = await new jose.SignJWT({
    sub: TEST_USER_ID,
    sid: TEST_SESSION_ID,
    tier: 'PREMIUM',
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(TEST_USER_ID)
    .setIssuer(JWT_ISSUER)
    .setAudience(JWT_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime('365d')
    .sign(secret);

  // ── Print creds ────────────────────────────────────────
  const banner = '═'.repeat(72);
  console.log(`\n${banner}`);
  console.log('  CarCam Pro — test user provisioned (PREMIUM, all-access)');
  console.log(banner);
  console.log(`  User ID            : ${TEST_USER_ID}`);
  console.log(`  Email              : ${EMAIL}`);
  console.log(`  Display name       : ${DISPLAY_NAME}`);
  console.log(`  Tier               : PREMIUM (4K + unlimited storage + all APIs)`);
  console.log(`  Device ID          : ${TEST_DEVICE_ID}`);
  console.log(`  Session ID         : ${TEST_SESSION_ID}`);
  console.log(`  Subscription       : ACTIVE until ${in30Days.toISOString()}`);
  console.log(`  Storage quota      : 1 TiB`);
  console.log(banner);
  console.log('  Access token (JWT, 365d TTL):');
  console.log(`\n  ${accessToken}\n`);
  console.log(banner);
  console.log('  Refresh token (opaque, 30d TTL):');
  console.log(`\n  ${refreshTokenPlain}\n`);
  console.log(banner);
  console.log('  curl probe:');
  console.log(`    curl -s http://localhost:4000/v1/me \\`);
  console.log(`         -H 'Authorization: Bearer ${accessToken.slice(0, 40)}...'`);
  console.log(`${banner}\n`);
};

main()
  .then(() => prisma.$disconnect())
  .catch(async (err) => {
    console.error(err);
    await prisma.$disconnect();
    process.exit(1);
  });
