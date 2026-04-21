import { Redis, type RedisOptions } from 'ioredis';

import { env } from '../config/env.js';

/**
 * BullMQ requires a Redis connection with `maxRetriesPerRequest = null` and
 * `enableReadyCheck = false` (see its docs) — the blocking primitives it uses
 * would otherwise throw during normal stalls. We keep this factory separate
 * from the Fastify `redis` plugin so the API process keeps its own tuned
 * connection for short-lived ops (revocation cache, rate limit, idempotency)
 * and the workers get their own long-lived connection for BRPOP-style ops.
 *
 * Both processes safely share the same Redis instance — BullMQ namespaces its
 * keys under `bull:<queue-name>:*`.
 */
export const createQueueConnection = (overrides: Partial<RedisOptions> = {}): Redis => {
  const client = new Redis(env.REDIS_URL, {
    maxRetriesPerRequest: null,
    enableReadyCheck: false,
    lazyConnect: false,
    ...overrides,
  });
  return client;
};
