<div align="center">

# CarCam Pro — Backend API

**Node 22 · TypeScript (strict) · Fastify 5 · Prisma 6 · Postgres 16 + PostGIS · Redis 7 · S3-compatible object storage**

A thin, auditable, zero-ceremony API that supports what the iOS client can't do alone: Sign in with Apple identity brokering, StoreKit 2 server-side verification, cloud clip storage with presigned uploads, Premium PDF incident reports, and an opt-in anonymous hazard layer.

</div>

---

## ▎ Why a backend at all?

The iOS client does ~95% of everything on-device. The backend only owns the four things the client **fundamentally can't**:

| Capability | Why it has to be server-side |
|:--|:--|
| **StoreKit 2 fraud prevention** | Apple's ASSN v2 webhook requires a public HTTPS endpoint with JWS verification. |
| **Cross-device clip access** | Clip files exceed CloudKit's per-object limits and need deterministic quota enforcement. |
| **Crowdsourced hazard layer** | A shared geo-index over multiple users. Pure client impossible. |
| **PDF incident reports** | Premium feature. Worker-rendered from a canonical template. |

Everything else — trip metadata sync, settings roaming — belongs in CloudKit.

---

## ▎ Architecture

```
  ┌──────────────────────────┐        ┌──────────────────────────┐
  │       Fastify API        │        │    Worker (BullMQ)       │
  │  (src/server.ts)         │        │    (src/worker.ts)       │
  │                          │──────▶│                          │
  │  auth · clips · subs     │ enqueue│  incident-report → PDF   │
  │  hazards · incidents     │        │  hard-purge → GDPR       │
  │  admin · /docs · /openapi│        │  hazard-expiry → sweep   │
  │                          │        │  + BullMQ cron scheduler │
  │  helmet · cors · rate    │        │                          │
  │  limit · Zod validation  │        │  pdfkit · S3 streams     │
  └─┬─────────────┬──────────┘        └─┬─────────────┬──────────┘
    │             │                     │             │
    │     ┌───────┴───────┐      ┌──────┴──────┐      │
    ├────▶│   Postgres    │◀─────┤   Workers   │      │
    │     │  + PostGIS    │      │   (Prisma)  │      │
    │     └───────────────┘      └─────────────┘      │
    │                                                 │
    │     ┌───────────────┐      ┌─────────────┐      │
    ├────▶│     Redis     │◀─────┤  BullMQ     │      │
    │     │  revocations  │      │  queues +   │      │
    │     │  rate limit   │      │  schedules  │      │
    │     │  idempotency  │      └─────────────┘      │
    │     └───────────────┘                           │
    │                                                 │
    │     ┌───────────────┐                           │
    └────▶│   S3 / R2     │◀──────────────────────────┘
          │  clips ·      │
          │  thumbs ·     │
          │  reports      │
          └───────────────┘
```

### Authentication

Sign in with Apple is the only identity provider. The iOS client sends Apple's signed identity token; the server verifies the JWT signature against Apple's public JWKS, derives the stable `sub` claim, and upserts a `User` row keyed by `applePrincipalId`.

**Session + refresh** — we mint two tokens:
- A **15-minute JWT access token** (stateless, HS256, verified on every request via a Fastify `preHandler`).
- A **30-day opaque refresh token** (32 random bytes, base64url). Only its SHA-256 **hash** is stored server-side (`sessions.refresh_token_hash`). Rotation updates the hash in place and stashes the old one in `previous_token_hash`. Presenting an old hash after rotation triggers **reuse detection**: the entire session is revoked.

Revocation is stateless-friendly — revoked session IDs are cached in Redis with TTL = access-token lifetime, so every JWT check also checks the revocation cache.

### StoreKit 2

Two entry points:
- **Client-initiated verification** (`POST /v1/subscriptions/verify`) — the iOS app hands us the `signedTransactionPayload` + `signedRenewalInfoPayload` from `Transaction.latest(for:)`. We verify the JWS with Apple's cert chain, upsert the `Subscription`, append to the immutable `subscription_transactions` log, and sync the user's denormalized `tier` + `storageQuotaBytes`.
- **App Store Server Notifications v2** (`POST /v1/subscriptions/webhook/app-store`) — Apple pushes state changes (renewal, grace period, refund, revocation) as nested signed JWS. We deduplicate by `notificationUUID` via Redis (Apple's delivery is at-least-once).

### Clip storage

Uploads are **direct-to-S3** via presigned PUT URLs with mandatory `x-amz-checksum-sha256`. The server never sees clip bytes. Flow:
1. `POST /v1/clips/init` — reserve a `Clip` row (status `PENDING`), enforce the per-tier quota, return a presigned URL.
2. Client PUTs the file to the URL.
3. `POST /v1/clips/:id/complete` — server `HEAD`s the object, verifies bytes match declared size, flips to `UPLOADED`.

### Hazards (opt-in)

Anonymized by construction:
- `HazardSighting` rows **never** carry `userId`. Instead, `reporter_hash = HMAC(dailySalt, userId)`. The salt rotates every 24 hours (stored in `daily_salts`), so yesterday's reporter-hash cannot be correlated with today's.
- `HazardVote` rows carry `userId` for dedup, but there's no SQL-level join back to the sighting's reporter hash.
- Sightings decay after 2 hours by default; every upvote extends expiry by 1 hour.
- Radial queries use PostGIS `ST_DWithin`; a 9-char geohash column stays for cheap prefix-bucket queries.

### Database

| Table | Purpose |
|:--|:--|
| `users` | Identity + denormalized tier / quota |
| `sessions` | Refresh-token hashes, rotation state, revocation |
| `devices` | Per-phone state + APNs push tokens |
| `subscriptions` | Current StoreKit state |
| `subscription_transactions` | Immutable transaction log |
| `clips` | Clip metadata + upload state |
| `clip_thumbnails` | 1:1 with `clips` |
| `incident_reports` | PDF render state (Premium) |
| `hazard_sightings` | Anonymized opt-in crowdsource |
| `hazard_votes` | Vote dedup (per user × sighting) |
| `daily_salts` | Rotating HMAC keys |
| `audit_logs` | Security-relevant events |

See [`prisma/schema.prisma`](./prisma/schema.prisma) for the canonical definition. ULID primary keys across the board.

---

## ▎ Getting started

### Prerequisites

- **Node 22** (use `nvm` / `fnm`)
- **pnpm 9** (`corepack enable && corepack prepare pnpm@9.14.4 --activate`)
- **Docker + Docker Compose**

### Bootstrap

```bash
cd backend
pnpm install
cp .env.example .env              # fill in real values for non-local deploys
pnpm docker:up                    # Postgres + Redis + MinIO + bucket init
pnpm prisma:migrate               # apply migrations
pnpm dev                          # Fastify on :4000
pnpm dev:worker                   # BullMQ workers (separate terminal)
```

Health check:

```bash
curl http://localhost:4000/health/ready
```

### Tests

```bash
pnpm test                   # run
pnpm test:coverage          # with v8 coverage
```

### Lint + typecheck

```bash
pnpm lint
pnpm typecheck
pnpm ci                     # all of the above
```

### Production build

```bash
pnpm build                                # TS → dist/
node dist/server.js                       # API process
node dist/worker.js                       # Worker process
# or:
docker build -f docker/Dockerfile        -t carcam-api    .
docker build -f docker/Dockerfile.worker -t carcam-worker .
```

### OpenAPI

```bash
curl http://localhost:4000/openapi.json   # machine-readable spec
open http://localhost:4000/docs           # Swagger UI (dev only by default)
pnpm openapi:emit --out openapi.json      # emit for CI / iOS codegen
```

---

## ▎ Deploying to Railway

1. Create a Railway project, add **Postgres** and **Redis** plugins.
2. Add a new service from this repo, root `/backend`. Railway auto-detects the Dockerfile.
3. Set environment variables from `.env.example` — at minimum:
   - `DATABASE_URL` (Railway injects)
   - `REDIS_URL` (Railway injects)
   - `JWT_ACCESS_SECRET` (`openssl rand -base64 64`)
   - `JWT_ISSUER`, `JWT_AUDIENCE`
   - `APPLE_APP_BUNDLE_ID=Res.CarCam-Pro`
   - `APPLE_ASSA_*` (from App Store Connect)
   - `S3_*` (Cloudflare R2 or Backblaze B2)
4. Deploy. Migrations auto-run on container start via `CMD` — or run `railway run pnpm prisma:deploy` manually first.

Post-deploy:
- Configure the App Store Server Notifications URL in App Store Connect:
  `https://api.carcampro.app/v1/subscriptions/webhook/app-store`
- Set `NODE_ENV=production` and `TRUST_PROXY=true`.

---

## ▎ API reference (concise)

```
  POST   /v1/auth/apple                   → exchange Apple identityToken for tokens
  POST   /v1/auth/refresh                 → rotate refresh + access
  POST   /v1/auth/logout                  → revoke current session
  POST   /v1/auth/logout-all              → revoke every session
  GET    /v1/auth/me                      → profile (from JWT)

  GET    /v1/users/me
  PATCH  /v1/users/me
  DELETE /v1/users/me                     → GDPR soft-delete (30d cooldown)

  POST   /v1/devices/register
  PATCH  /v1/devices/:id
  DELETE /v1/devices/:id
  GET    /v1/devices

  POST   /v1/clips/init                   → PRO+  presigned upload URL
  POST   /v1/clips/:id/complete           → PRO+  finalize metadata
  GET    /v1/clips                        → cursor-paged list
  GET    /v1/clips/:id
  GET    /v1/clips/:id/download           → presigned download URL
  DELETE /v1/clips/:id                    → soft delete

  POST   /v1/subscriptions/verify         → client-initiated StoreKit verification
  POST   /v1/subscriptions/webhook/app-store  (Apple, public, JWS-verified)
  GET    /v1/subscriptions/current

  POST   /v1/incidents/:clipId/report     → PREMIUM, enqueue PDF
  GET    /v1/incidents/:clipId/report     → status + presigned download

  POST   /v1/hazards
  GET    /v1/hazards/nearby
  POST   /v1/hazards/:id/vote

  # ── Admin (x-admin-api-key) ───────────────────────────────
  GET    /v1/admin/metrics
  GET    /v1/admin/queues
  GET    /v1/admin/users?q=&limit=
  GET    /v1/admin/users/:id
  POST   /v1/admin/users/:id/revoke-sessions
  POST   /v1/admin/users/:id/purge
  POST   /v1/admin/subscriptions/:id/override
  GET    /v1/admin/subscriptions/by-original-tx/:originalTransactionId/refunds
  GET    /v1/admin/audit?userId=&action=&limit=

  GET    /health                          → liveness
  GET    /health/ready                    → DB + Redis probe
  GET    /openapi.json                    → OpenAPI 3.1 spec
  GET    /docs                            → Swagger UI (dev)
```

---

## ▎ Background workers

The worker process (`src/worker.ts`) owns three BullMQ queues, all sharing the API's Redis instance under a `bull:carcam.*` key-prefix:

| Queue | Trigger | Work |
|:--|:--|:--|
| `carcam.incident.report` | `POST /v1/incidents/:clipId/report` | Render PDF via pdfkit, upload to `S3_BUCKET_REPORTS`, flip `sizeBytes` on the `IncidentReport` row. |
| `carcam.gdpr.hard_purge` | Daily cron (`HARD_PURGE_CRON`) + admin manual | Find users whose soft-delete cooldown has elapsed; purge their S3 prefixes + cascade-delete DB rows. |
| `carcam.hazard.expiry` | Every 10 min (`HAZARD_EXPIRY_CRON`) | Delete expired hazard sightings in bounded batches. |

Repeatable jobs are registered idempotently at worker boot via BullMQ's `repeat` primitive, so replicas converge on one schedule regardless of how many you run.

```bash
pnpm dev:worker                   # local
docker build -f docker/Dockerfile.worker -t carcam-worker .
```

---

## ▎ Observability

**Structured logs** — pino with per-request correlation IDs and header redaction for `authorization`, `cookie`, `identityToken`, `refreshToken`, `appleSignedPayload`. In dev, `pino-pretty` renders to the console.

**OpenTelemetry** — opt-in via `OTEL_ENABLED=true`. The SDK is dynamically imported so disabled deploys don't pay the cost. Instruments Fastify, Prisma, ioredis, http, and dns (dns instrumentation disabled — noisy). Export via OTLP HTTP to any compatible collector (Honeycomb, Tempo, Grafana Cloud, Datadog).

```bash
OTEL_ENABLED=true \
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp.honeycomb.io/v1/traces \
OTEL_EXPORTER_OTLP_HEADERS="x-honeycomb-team=$HONEYCOMB_KEY" \
pnpm start
```

**Admin metrics** — `GET /v1/admin/metrics` returns live counts (active users, paying subs, clips, pending PDFs, live hazards). `GET /v1/admin/queues` returns per-queue BullMQ counts.

---

## ▎ Admin surface

Admin endpoints are gated behind a shared-secret API key (`x-admin-api-key` header) and an optional source IP allowlist. **Both** gates must pass; neither is a substitute for the other. Missing or misconfigured `ADMIN_API_KEY` disables the entire surface.

```bash
# User lookup + detail
curl -H "x-admin-api-key: $ADMIN_API_KEY" -H "x-admin-actor: jwillz" \
  "https://api.carcampro.app/v1/admin/users?q=user@example.com"

# Refund history via Apple's App Store Server API
curl -H "x-admin-api-key: $ADMIN_API_KEY" \
  "https://api.carcampro.app/v1/admin/subscriptions/by-original-tx/2000000123456789/refunds"

# Immediate hard-purge (requires soft-delete + explicit acknowledgement)
curl -X POST -H "x-admin-api-key: $ADMIN_API_KEY" -H "x-admin-actor: jwillz" \
  -H 'content-type: application/json' \
  -d '{"acknowledgement":"customer email 2026-04-20 confirms no in-flight disputes"}' \
  "https://api.carcampro.app/v1/admin/users/01HK.../purge"
```

Every admin mutation writes an `audit_logs` row with the actor, reason, and outcome.

All responses follow the envelope:

```json
{ "error": { "code": "NOT_FOUND", "message": "...", "details": {...} }, "requestId": "..." }
```

on failure, or the shape documented in the route's Zod `response` schema on success.

---

## ▎ License

Proprietary. See the repo root [`LICENSE`](../LICENSE).
