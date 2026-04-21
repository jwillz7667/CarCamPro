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
         ┌─────────────────────────────────────────────────────┐
         │                  Fastify 5 app                      │
         │  ┌─ auth ──┬─ clips ──┬─ subs ──┬─ hazards ──┐      │
         │  │  /apple │  /init   │ /verify │ /          │      │
         │  │  /refresh /complete│ /webhook│ /nearby    │      │
         │  │  /logout │ /:id    │ /current│ /:id/vote  │      │
         │  └─────────┴──────────┴─────────┴────────────┘      │
         │                                                     │
         │   @fastify/{helmet, cors, rate-limit, sensible}     │
         │   fastify-type-provider-zod — request + response    │
         │   validated with Zod, JSON-schema derived           │
         │                                                     │
         │   plugins/{prisma, redis, storage, auth, rateLimit} │
         └─┬──────────────┬──────────────┬────────────────────┘
           │              │              │
      ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
      │ Postgres│    │  Redis  │    │  S3/R2  │
      │ + PostGIS│    │         │    │         │
      │ (Prisma)│    │ refresh │    │ clips,  │
      │         │    │ revokes,│    │ thumbs, │
      │         │    │ rate    │    │ reports │
      │         │    │ limit,  │    │ buckets │
      │         │    │ idem    │    │         │
      └─────────┘    └─────────┘    └─────────┘
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
pnpm build                         # TS → dist/
node dist/server.js                # run
# or:
docker build -f docker/Dockerfile -t carcam-api .
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

  GET    /health                          → liveness
  GET    /health/ready                    → DB + Redis probe
```

All responses follow the envelope:

```json
{ "error": { "code": "NOT_FOUND", "message": "...", "details": {...} }, "requestId": "..." }
```

on failure, or the shape documented in the route's Zod `response` schema on success.

---

## ▎ License

Proprietary. See the repo root [`LICENSE`](../LICENSE).
