import { z } from 'zod';

/**
 * Environment schema.
 *
 * Every config value the backend reads is defined here, validated with Zod
 * at startup, and exported as a strongly-typed frozen object. Referencing
 * `process.env.FOO` anywhere else in the codebase is a lint error.
 *
 * On validation failure the process exits with code 1 and prints the list of
 * missing / malformed variables — never start a partially-configured service.
 */

/**
 * Proper boolean env coercion. `z.coerce.boolean()` alone is broken for env
 * vars — it runs `Boolean(input)`, which returns `true` for any non-empty
 * string including `"false"` and `"0"`. This factory parses the canonical
 * truthy strings explicitly and treats everything else as false.
 */
const envBool = (defaultValue: boolean) =>
  z
    .union([z.boolean(), z.string()])
    .default(defaultValue)
    .transform((v) => {
      if (typeof v === 'boolean') return v;
      const n = v.trim().toLowerCase();
      return n === 'true' || n === '1' || n === 'yes' || n === 'y' || n === 'on';
    });

const EnvSchema = z.object({
  // Node / server
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(4000),
  HOST: z.string().default('0.0.0.0'),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']).default('info'),

  // Database
  DATABASE_URL: z.string().url(),
  SHADOW_DATABASE_URL: z.string().url().optional(),

  // Redis
  REDIS_URL: z.string().url(),

  // JWT
  JWT_ACCESS_SECRET: z.string().min(32, 'JWT_ACCESS_SECRET must be ≥ 32 bytes'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL: z.string().default('30d'),
  JWT_ISSUER: z.string().url(),
  JWT_AUDIENCE: z.string(),

  // Apple — Sign in with Apple (public verification only)
  APPLE_APP_BUNDLE_ID: z.string(),

  // Apple — App Store Server API
  APPLE_ASSA_KEY_ID: z.string().optional(),
  APPLE_ASSA_ISSUER_ID: z.string().uuid().optional(),
  APPLE_ASSA_PRIVATE_KEY: z.string().optional(),
  APPLE_ASSA_ENVIRONMENT: z.enum(['Sandbox', 'Production']).default('Sandbox'),

  // Object storage
  S3_ENDPOINT: z.string().url(),
  S3_REGION: z.string().default('auto'),
  S3_BUCKET_CLIPS: z.string(),
  S3_BUCKET_THUMBS: z.string(),
  S3_BUCKET_REPORTS: z.string(),
  S3_ACCESS_KEY_ID: z.string(),
  S3_SECRET_ACCESS_KEY: z.string(),
  S3_FORCE_PATH_STYLE: envBool(true),
  S3_PRESIGN_TTL: z.coerce.number().int().positive().default(900),

  // Security
  ACCESS_ORIGINS: z
    .string()
    .default('')
    .transform((s) =>
      s
        .split(',')
        .map((o) => o.trim())
        .filter(Boolean),
    ),
  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(120),
  TRUST_PROXY: envBool(false),

  // Admin surface — disabled when unset. Treat as a shared secret; rotate via
  // the deploy environment, never commit. Minimum length is 32 bytes so a
  // wrong-entropy key fails fast at boot.
  ADMIN_API_KEY: z.string().min(32).optional(),
  /// Comma-separated CIDRs permitted to reach `/v1/admin/*`. Empty = any.
  ADMIN_IP_ALLOWLIST: z
    .string()
    .default('')
    .transform((s) =>
      s
        .split(',')
        .map((c) => c.trim())
        .filter(Boolean),
    ),

  // Background workers / queue tuning
  WORKER_CONCURRENCY_INCIDENT_REPORT: z.coerce.number().int().positive().default(2),
  WORKER_CONCURRENCY_HARD_PURGE: z.coerce.number().int().positive().default(1),
  WORKER_CONCURRENCY_HAZARD_EXPIRY: z.coerce.number().int().positive().default(1),
  /// Cron expression for the GDPR hard-purge scan. Default: daily at 03:15 UTC.
  HARD_PURGE_CRON: z.string().default('15 3 * * *'),
  /// Minimum age (days) before a soft-deleted user/clip is hard-purged.
  HARD_PURGE_COOLDOWN_DAYS: z.coerce.number().int().nonnegative().default(30),
  /// Cron expression for the hazard-sighting expiry sweep. Default: every 10 min.
  HAZARD_EXPIRY_CRON: z.string().default('*/10 * * * *'),

  // Observability — OpenTelemetry. When disabled the SDK is never imported
  // so the binary stays lean in environments that don't need tracing.
  OTEL_ENABLED: envBool(false),
  OTEL_SERVICE_NAME: z.string().default('carcam-api'),
  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().url().optional(),
  OTEL_EXPORTER_OTLP_HEADERS: z
    .string()
    .default('')
    .transform((s) => {
      // Parses the OTel standard format: "key1=value1,key2=value2".
      const out: Record<string, string> = {};
      for (const pair of s.split(',').map((p) => p.trim()).filter(Boolean)) {
        const idx = pair.indexOf('=');
        if (idx === -1) continue;
        out[pair.slice(0, idx).trim()] = pair.slice(idx + 1).trim();
      }
      return out;
    }),
  OTEL_SAMPLER_RATIO: z.coerce.number().min(0).max(1).default(1),

  // OpenAPI — docs exposure. In prod, lock down behind a feature flag to
  // avoid advertising admin surface area.
  OPENAPI_ENABLED: envBool(true),
  OPENAPI_UI_ENABLED: envBool(true),
});

export type Env = z.infer<typeof EnvSchema>;

const parsed = EnvSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('✗ Invalid environment:\n', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env: Readonly<Env> = Object.freeze(parsed.data);
export const isProd = env.NODE_ENV === 'production';
export const isTest = env.NODE_ENV === 'test';
