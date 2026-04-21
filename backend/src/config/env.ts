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
  S3_FORCE_PATH_STYLE: z.coerce.boolean().default(true),
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
  TRUST_PROXY: z.coerce.boolean().default(false),
});

export type Env = z.infer<typeof EnvSchema>;

const parsed = EnvSchema.safeParse(process.env);

if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error('✗ Invalid environment:\n', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env: Readonly<Env> = Object.freeze(parsed.data);
export const isProd = env.NODE_ENV === 'production';
export const isTest = env.NODE_ENV === 'test';
