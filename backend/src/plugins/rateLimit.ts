import rateLimit from '@fastify/rate-limit';
import type { FastifyInstance } from 'fastify';
import fp from 'fastify-plugin';

import { env } from '../config/env.js';

/**
 * Rate-limit plugin. Shared across API replicas via Redis so a caller can't
 * dodge the limit by hitting a different pod.
 *
 * The defaults applied at the app level are deliberately loose; high-risk
 * routes (login, webhook, presigned-URL issuance) attach tighter per-route
 * `config.rateLimit` overrides.
 */
export default fp(async (app: FastifyInstance) => {
  await app.register(rateLimit, {
    global: true,
    max: env.RATE_LIMIT_MAX,
    timeWindow: '1 minute',
    redis: app.redis,
    nameSpace: 'rl:',
    keyGenerator: (req) => {
      // Prefer authenticated user id; fall back to IP.
      return req.auth?.userId ?? req.ip;
    },
    errorResponseBuilder: (_req, context) => ({
      error: {
        code: 'RATE_LIMITED',
        message: 'Too many requests',
        details: { retryAfterSeconds: Math.ceil(context.ttl / 1000) },
      },
    }),
  });
}, {
  name: 'rate-limit',
  dependencies: ['redis'],
});
