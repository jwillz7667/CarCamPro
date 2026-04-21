# CarCam Pro — Railway deployment

End-to-end runbook for shipping the backend (+ worker + Postgres + Redis) to Railway. The first deploy takes ~15 minutes; subsequent pushes are ~2 minutes.

---

## 1. Prerequisites

- Railway account with a paid plan (free plan is unreliable for long-running services).
- Railway CLI installed + logged in:
  ```bash
  brew install railway
  railway login
  ```
- An R2 / Backblaze B2 bucket set with access keys (Railway does not offer managed object storage).
- JWT + admin secrets generated locally:
  ```bash
  openssl rand -base64 64   # → JWT_ACCESS_SECRET
  openssl rand -base64 48   # → ADMIN_API_KEY
  ```

---

## 2. Create the Railway project

```bash
cd backend
railway init       # choose "Empty project", name it "carcam-api"
railway link
```

This sets `RAILWAY_PROJECT_ID` locally and binds this directory to the project.

---

## 3. Add the managed plugins

From the Railway dashboard (`Project → + New`):

1. **Postgres** — name it `Postgres`. Railway exposes `DATABASE_URL` automatically.
2. **Redis** — name it `Redis`. Railway exposes `REDIS_URL` automatically.

No configuration needed on either. The init migration creates the `postgis` + `pgcrypto` extensions on first boot.

---

## 4. Deploy the API service

1. In the dashboard: `+ New → Deploy from GitHub` (or `railway up` from the CLI if you prefer direct upload).
2. Name the service `api`.
3. **Settings → Source → Root Directory** → `backend`.
4. **Settings → Config-as-Code → Config Path** → `railway.json` (default; already committed).
5. **Settings → Variables** → paste the entire contents of `backend/.env.railway.example` and fill the blanks. Use Railway's "Add Reference" for `DATABASE_URL` and `REDIS_URL` so they follow the managed plugins.
6. **Settings → Networking → Public Networking** → generate a domain (e.g. `api-production-xxxx.up.railway.app`). Update `JWT_ISSUER` to match.
7. Deploy. Watch the first build for the `pnpm prisma migrate deploy` step — it creates the schema + extensions on first run.

Health check endpoint is wired in `railway.json` → `/health/ready`. If it fails, check the deploy logs for Prisma errors (usually extension-permission issues).

---

## 5. Deploy the worker service

Each Railway service is a separate deploy unit. Workers reuse the same repo but build from `docker/Dockerfile.worker`:

1. In the dashboard: `+ New → Empty Service`, name it `worker`.
2. **Settings → Source** → connect to the same GitHub repo as the API.
3. **Settings → Source → Root Directory** → `backend`.
4. **Settings → Config-as-Code → Config Path** → `railway.worker.json`.
5. **Settings → Variables** → copy every variable from the API service *except* `PORT` (workers don't listen on HTTP). The worker needs:
   - `DATABASE_URL`, `REDIS_URL`
   - `S3_*` (for PDF uploads + hard-purge object deletion)
   - `APPLE_ASSA_*` (renewal-info polling)
   - `WORKER_CONCURRENCY_*`, `HARD_PURGE_CRON`, `HAZARD_EXPIRY_CRON`, `HARD_PURGE_COOLDOWN_DAYS`
6. Deploy. Workers have no health check — look for `"worker ready"` in logs to confirm startup.

---

## 6. Object storage (R2 / B2)

Create three buckets — `carcam-clips`, `carcam-thumbs`, `carcam-reports` — and set:

- **CORS** (R2 dashboard → bucket → Settings → CORS):
  ```json
  [{
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }]
  ```
- **Object lifecycle** (optional but recommended): expire `carcam-thumbs` after 365 days, `carcam-reports` after 7 years for legal-hold compliance.

Paste the access key + secret + endpoint into the API + worker services' `S3_*` variables.

---

## 7. Verify the deploy

From your local machine:

```bash
# Health
curl -s https://api-production-xxxx.up.railway.app/health/ready
# → {"ok":true}

# OpenAPI
curl -s https://api-production-xxxx.up.railway.app/openapi.json | jq .info.version

# End-to-end harness against the deployed URL
E2E_API=https://api-production-xxxx.up.railway.app \
ADMIN_API_KEY=<your admin key> \
JWT_ACCESS_SECRET=<your access secret> \
pnpm tsx scripts/e2e.ts
```

The E2E script seeds a test user directly into Postgres, mints a JWT with the same secret the API uses, and exercises every route. Green = you're shipped.

---

## 8. Custom domain

1. Dashboard → `api` service → **Settings → Domains → Custom Domain** → e.g. `api.carcampro.app`.
2. Add the CNAME Railway shows to your DNS (Cloudflare → DNS → orange-cloud OFF during first cert issuance).
3. Update `JWT_ISSUER` to match. Roll the deployment (`railway redeploy`) so new tokens carry the right `iss`.

---

## 9. Post-deploy checklist

- [ ] `/health/ready` returns 200.
- [ ] `/openapi.json` loads.
- [ ] One successful `/v1/auth/apple` round-trip from iOS using a TestFlight build.
- [ ] Worker log shows `"worker ready"` + the scheduler-registered queues.
- [ ] `HARD_PURGE_CRON` and `HAZARD_EXPIRY_CRON` entries appear in the BullMQ UI (run `pnpm tsx scripts/bullmq-ui.ts` locally against the deployed Redis if needed).
- [ ] R2 / B2 PUT presign + upload succeeds via `scripts/e2e.ts`.
- [ ] Railway project `Observability` tab shows non-zero request/response metrics.

---

## 10. Operational notes

- **Migrations.** The API service's `startCommand` runs `prisma migrate deploy` on every boot. This is idempotent and fast. Prefer landing migrations in a branch deploy before promoting to prod if a schema change is risky.
- **Rolling restarts.** Railway replaces the container on every deploy — in-flight requests get a `SIGTERM` + a 30-second drain window, handled by `backend/src/server.ts`'s shutdown hook.
- **Scaling.** Bump `numReplicas` in `railway.json` if request rate warrants; workers scale via the queue concurrency env vars plus additional Railway replicas.
- **Secrets rotation.** Rotating `JWT_ACCESS_SECRET` invalidates every in-flight access token (users get one forced re-login). Rotating `ADMIN_API_KEY` invalidates admin sessions only.
- **Backups.** Railway takes daily Postgres snapshots automatically. For anything beyond that (point-in-time recovery, off-provider backups), run a nightly `pg_dump` from a worker job to S3.
