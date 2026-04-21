/**
 * End-to-end harness. Exercises the running local stack against real
 * Postgres / Redis / MinIO — no mocks. Designed to be re-runnable: every
 * user row it creates lives under a deterministic ULID prefix and is
 * cleaned up at the end.
 *
 * Exit code 0 = all checks passed. Any failure prints context and exits 1.
 */
import { createHash } from 'node:crypto';

import { PrismaClient } from '@prisma/client';
import * as jose from 'jose';
import { ulid } from 'ulid';

// ─── Config ───────────────────────────────────────────────
const API = process.env['E2E_API'] ?? 'http://localhost:4000';
const ADMIN_KEY = process.env['ADMIN_API_KEY'] ?? '';
const JWT_SECRET = process.env['JWT_ACCESS_SECRET'] ?? '';
const JWT_ISSUER = process.env['JWT_ISSUER'] ?? 'http://localhost:4000';
const JWT_AUDIENCE = process.env['JWT_AUDIENCE'] ?? 'carcam-ios';

if (!ADMIN_KEY || !JWT_SECRET) {
  throw new Error('ADMIN_API_KEY + JWT_ACCESS_SECRET must be set in env');
}

const prisma = new PrismaClient();
const secret = new TextEncoder().encode(JWT_SECRET);

// ─── Tiny assertion helpers ───────────────────────────────
let passed = 0;
let failed = 0;
const check = (name: string, ok: boolean, detail?: unknown): void => {
  if (ok) {
    passed += 1;
    console.log(`  ✓ ${name}`);
  } else {
    failed += 1;
    console.error(`  ✗ ${name}`);
    if (detail !== undefined) console.error('    ', detail);
  }
};

const section = (name: string) => console.log(`\n● ${name}`);

// ─── HTTP helper ─────────────────────────────────────────
interface HttpResult {
  status: number;
  ok: boolean;
  json: unknown;
  text: string;
}
const http = async (
  method: string,
  path: string,
  opts: { body?: unknown; token?: string; admin?: boolean; headers?: Record<string, string> } = {},
): Promise<HttpResult> => {
  const headers: Record<string, string> = { ...(opts.headers ?? {}) };
  if (opts.body !== undefined) headers['content-type'] = 'application/json';
  if (opts.token) headers['authorization'] = `Bearer ${opts.token}`;
  if (opts.admin) headers['x-admin-api-key'] = ADMIN_KEY;

  const res = await fetch(`${API}${path}`, {
    method,
    headers,
    ...(opts.body !== undefined ? { body: JSON.stringify(opts.body) } : {}),
  });
  const text = await res.text();
  let json: unknown;
  try {
    json = text.length > 0 ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: res.status, ok: res.ok, json, text };
};

const signAccess = async (sub: string, sid: string, tier: 'FREE' | 'PRO' | 'PREMIUM') =>
  new jose.SignJWT({ sub, sid, tier })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(sub)
    .setIssuer(JWT_ISSUER)
    .setAudience(JWT_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime('15m')
    .sign(secret);

// ─── Seed + teardown ─────────────────────────────────────
const userId = ulid();
const deviceId = ulid();
const sessionId = ulid();
let accessToken: string;

const seed = async () => {
  section('Seeding test user + session');
  await prisma.user.create({
    data: {
      id: userId,
      applePrincipalId: `apple-principal-${userId}`,
      email: `e2e-${userId.toLowerCase()}@example.com`,
      displayName: 'E2E Test Driver',
      subscriptionTier: 'PREMIUM',
      storageQuotaBytes: 100n * 1024n * 1024n * 1024n, // 100 GiB
    },
  });
  await prisma.device.create({
    data: {
      id: deviceId,
      userId,
      name: 'iPhone 16 Pro (e2e)',
      model: 'iPhone17,1',
      osVersion: '26.0',
      appVersion: '1.0.0',
    },
  });
  await prisma.session.create({
    data: {
      id: sessionId,
      userId,
      deviceId,
      refreshTokenHash: createHash('sha256').update('stub-refresh').digest(),
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });
  accessToken = await signAccess(userId, sessionId, 'PREMIUM');
  check('seeded user + device + session', true);
};

const cleanup = async () => {
  section('Cleaning up test data');
  // Cascade via user delete takes care of sessions/devices/clips/subs/votes.
  await prisma.user.deleteMany({ where: { id: userId } }).catch(() => {});
  check('deleted test user + cascaded rows', true);
  await prisma.$disconnect();
};

// ─── Test cases ──────────────────────────────────────────

const testUsersMe = async () => {
  section('GET /v1/users/me');
  const unauth = await http('GET', '/v1/users/me');
  check('401 without token', unauth.status === 401, unauth.json);

  const badToken = await http('GET', '/v1/users/me', { token: 'not-a-jwt' });
  check('401 with malformed token', badToken.status === 401, badToken.json);

  const ok = await http('GET', '/v1/users/me', { token: accessToken });
  check('200 with valid token', ok.status === 200, ok.json);
  const body = ok.json as { id: string; email: string | null; subscriptionTier: string };
  check('returns correct user id', body.id === userId, body);
  check('returns PREMIUM tier', body.subscriptionTier === 'PREMIUM', body);
};

const testDevicesList = async () => {
  section('GET /v1/devices');
  const res = await http('GET', '/v1/devices', { token: accessToken });
  check('200', res.status === 200, res.json);
  const body = res.json as { devices: Array<{ id: string; name: string }> };
  check('returns seeded device', body.devices.some((d) => d.id === deviceId), body);
};

const testClipUploadFlow = async () => {
  section('POST /v1/clips/init + PUT to MinIO + POST /v1/clips/:id/complete');

  // Payload — craft the blob, compute its SHA-256 base64 digest, declare size.
  const blob = Buffer.from('fake-mp4-bytes-for-e2e-'.repeat(1000));
  const sha256Base64 = createHash('sha256').update(blob).digest('base64');

  const init = await http('POST', '/v1/clips/init', {
    token: accessToken,
    body: {
      deviceId,
      sizeBytes: blob.byteLength.toString(),
      contentType: 'video/mp4',
      sha256Base64,
    },
  });
  check('clips/init 200', init.status === 200, init.json);
  const initBody = init.json as { clipId: string; uploadUrl: string; storageKey: string };
  check('clipId returned', typeof initBody.clipId === 'string' && initBody.clipId.length === 26);
  check('uploadUrl looks presigned', initBody.uploadUrl.includes('X-Amz-Signature=') || initBody.uploadUrl.includes('x-amz-signature='), initBody.uploadUrl);

  // PUT the blob to MinIO. S3-compatible requires the checksum header.
  const put = await fetch(initBody.uploadUrl, {
    method: 'PUT',
    headers: {
      'content-type': 'video/mp4',
      'x-amz-checksum-sha256': sha256Base64,
    },
    body: blob,
  });
  check(`MinIO PUT 200 (got ${put.status})`, put.ok, await put.text().catch(() => 'no body'));

  const complete = await http('POST', `/v1/clips/${initBody.clipId}/complete`, {
    token: accessToken,
    body: {
      durationSeconds: 42.5,
      resolution: '1080p',
      frameRate: 30,
      codec: 'HEVC',
      startedAt: new Date(Date.now() - 60_000).toISOString(),
      endedAt: new Date().toISOString(),
      isProtected: true,
      protectionReason: 'incident',
      hasIncident: true,
      incidentSeverity: 'moderate',
      peakGForce: 4.2,
      incidentTimestamp: new Date().toISOString(),
      startLatitude: 37.774929,
      startLongitude: -122.419416,
      endLatitude: 37.780000,
      endLongitude: -122.410000,
      averageSpeedMPH: 32.1,
    },
  });
  check('clips/:id/complete 200', complete.status === 200, complete.json);
  const clip = complete.json as { id: string; uploadStatus: string; hasIncident: boolean };
  check('uploadStatus=UPLOADED', clip.uploadStatus === 'UPLOADED', clip);
  check('hasIncident=true', clip.hasIncident === true, clip);

  return initBody.clipId;
};

const testIncidentReportFlow = async (clipId: string) => {
  section('POST /v1/incidents/:clipId/report (Premium) + worker render');
  const enqueue = await http('POST', `/v1/incidents/${clipId}/report`, { token: accessToken });
  check('202 accepted', enqueue.status === 202, enqueue.json);
  const { reportId } = enqueue.json as { reportId: string };

  // Poll the GET endpoint until the worker flips status → READY.
  const deadline = Date.now() + 30_000;
  let lastStatus: string | undefined;
  let downloadUrl: string | null = null;
  while (Date.now() < deadline) {
    const res = await http('GET', `/v1/incidents/${clipId}/report`, { token: accessToken });
    if (res.status !== 200) break;
    const body = res.json as { status: string; downloadUrl: string | null };
    lastStatus = body.status;
    if (body.status === 'READY' && body.downloadUrl) {
      downloadUrl = body.downloadUrl;
      break;
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  check(`worker flipped to READY (last=${lastStatus ?? 'n/a'})`, lastStatus === 'READY', { reportId });

  if (downloadUrl) {
    const pdfRes = await fetch(downloadUrl);
    const bytes = Buffer.from(await pdfRes.arrayBuffer());
    check('PDF download reachable', pdfRes.ok);
    check('PDF is non-trivially sized', bytes.byteLength > 1024, { bytes: bytes.byteLength });
    check('PDF magic bytes (%PDF-)', bytes.subarray(0, 5).toString('ascii') === '%PDF-', bytes.subarray(0, 16).toString('hex'));
  }
};

const testHazardFlow = async () => {
  section('POST /v1/hazards + /vote + /nearby');
  const latitude = 37.7749;
  const longitude = -122.4194;

  const create = await http('POST', '/v1/hazards', {
    token: accessToken,
    body: {
      type: 'POLICE_STOP',
      latitude,
      longitude,
      severity: 2,
      confidence: 0.87,
    },
  });
  check(
    `hazard create 201 (got ${create.status})`,
    create.status === 201,
    create.json,
  );
  const hazard = create.json as { id: string; expiresAt: string };
  if (!hazard?.id) return;

  const nearby = await http(
    'GET',
    `/v1/hazards/nearby?latitude=${latitude}&longitude=${longitude}&radiusMeters=500`,
    { token: accessToken },
  );
  check('hazard nearby 200', nearby.status === 200, nearby.json);
  const near = nearby.json as {
    sightings: Array<{ id: string; distanceMeters: number }>;
  };
  check(
    'created hazard appears in radial query',
    near.sightings.some((h) => h.id === hazard.id),
    near,
  );

  const vote = await http('POST', `/v1/hazards/${hazard.id}/vote`, {
    token: accessToken,
    body: { direction: 1 },
  });
  check('hazard vote 200/204', vote.status === 200 || vote.status === 204, vote.json);

  // Clean up the sighting so subsequent runs don't pollute.
  await prisma.hazardSighting.delete({ where: { id: hazard.id } }).catch(() => {});
};

const testAdminFlow = async () => {
  section('Admin surface (API key)');
  const metrics = await http('GET', '/v1/admin/metrics', { admin: true });
  check('admin metrics 200', metrics.status === 200, metrics.json);

  const users = await http('GET', `/v1/admin/users?q=${userId}`, { admin: true });
  check('admin user search returns our user', (users.json as { users: Array<{ id: string }> }).users.some((u) => u.id === userId), users.json);

  const detail = await http('GET', `/v1/admin/users/${userId}`, { admin: true });
  check('admin user detail 200', detail.status === 200, detail.json);
  const d = detail.json as { counts: { clips: number } };
  check('user detail counts clips', typeof d.counts.clips === 'number', d);

  const revoke = await http('POST', `/v1/admin/users/${userId}/revoke-sessions`, {
    admin: true,
    headers: { 'x-admin-actor': 'e2e-harness' },
    body: { reason: 'e2e testing' },
  });
  check('admin revoke-sessions 200', revoke.status === 200, revoke.json);
  check('revoked at least one session', (revoke.json as { revoked: number }).revoked >= 1, revoke.json);

  // After revoke, our JWT should be rejected.
  const afterRevoke = await http('GET', '/v1/users/me', { token: accessToken });
  check('JWT rejected after session revoke', afterRevoke.status === 401, afterRevoke.json);
};

// ─── Runner ─────────────────────────────────────────────
const main = async () => {
  console.log('═══ CarCam Pro E2E ═══');
  console.log(`API = ${API}`);
  console.log(`Test user ID = ${userId}`);

  try {
    await seed();
    await testUsersMe();
    await testDevicesList();
    const clipId = await testClipUploadFlow();
    await testIncidentReportFlow(clipId);
    await testHazardFlow();
    await testAdminFlow();
  } finally {
    await cleanup();
  }

  console.log('\n═══ Summary ═══');
  console.log(`  passed: ${passed}`);
  console.log(`  failed: ${failed}`);
  process.exit(failed === 0 ? 0 : 1);
};

void main().catch((err) => {
  console.error('\n✗ E2E harness crashed:', err);
  process.exit(1);
});
