import type { FastifyInstance } from 'fastify';
import fp from 'fastify-plugin';
import Redis from 'ioredis';

import { env } from '../config/env.js';

/**
 * Redis plugin. Used for:
 *   - Refresh-token revocation cache (fast "is this session revoked?" check)
 *   - Rate limiting (shared across API replicas)
 *   - Idempotency keys for the ASSN v2 webhook
 */
export default fp(async (app: FastifyInstance) => {
  const redis = new Redis(env.REDIS_URL, {
    lazyConnect: false,
    maxRetriesPerRequest: 2,
    enableReadyCheck: true,
  });

  redis.on('error', (err) => app.log.error({ redis: err }, 'redis error'));
  redis.on('ready', () => app.log.info('redis ready'));

  app.decorate('redis', redis);

  app.addHook('onClose', async () => {
    await redis.quit();
  });
}, {
  name: 'redis',
});

declare module 'fastify' {
  interface FastifyInstance {
    redis: Redis;
  }
}
