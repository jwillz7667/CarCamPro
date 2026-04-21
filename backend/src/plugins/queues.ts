import type { FastifyInstance } from 'fastify';
import fp from 'fastify-plugin';

import { QueueRegistry } from '../queues/index.js';

/**
 * Exposes `app.queues` — a typed producer-only façade over BullMQ. Workers
 * never register through this plugin; they live in the dedicated worker
 * process (`src/worker.ts`) which bootstraps its own `QueueRegistry` and
 * binds consumers.
 *
 * Registered AFTER `redis` so a Redis outage fails fast at boot rather than
 * on first enqueue.
 */
export default fp(
  async (app: FastifyInstance) => {
    const registry = new QueueRegistry();
    registry.attachObservability();

    app.decorate('queues', registry);

    app.addHook('onClose', async () => {
      await registry.close();
    });
  },
  { name: 'queues', dependencies: ['redis'] },
);

declare module 'fastify' {
  interface FastifyInstance {
    queues: QueueRegistry;
  }
}
