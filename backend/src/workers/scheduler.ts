import type { Queue } from 'bullmq';
import type { Logger } from 'pino';

import { env } from '../config/env.js';

/**
 * Cron scheduler. Uses BullMQ's "repeat" jobs (backed by Redis ZSETs) rather
 * than a node-local cron library — this guarantees that multiple worker
 * replicas don't each fire the same schedule; BullMQ's repeat-job primitive
 * is globally consistent across the cluster.
 *
 * Registration is idempotent: the `jobId` + repeat key are deterministic, so
 * re-running the scheduler on every process boot converges on the same
 * repeat state.
 */
export const registerSchedules = async (params: {
  hardPurgeQueue: Queue;
  hazardExpiryQueue: Queue;
  logger: Logger;
}): Promise<void> => {
  const { hardPurgeQueue, hazardExpiryQueue, logger } = params;

  await hardPurgeQueue.add(
    'scan',
    { batchSize: 50 },
    {
      repeat: { pattern: env.HARD_PURGE_CRON, tz: 'UTC' },
      jobId: 'hard-purge:scheduled-scan',
    },
  );
  logger.info({ cron: env.HARD_PURGE_CRON }, 'registered hard-purge schedule');

  await hazardExpiryQueue.add(
    'sweep',
    { batchSize: 1000 },
    {
      repeat: { pattern: env.HAZARD_EXPIRY_CRON, tz: 'UTC' },
      jobId: 'hazard-expiry:scheduled-sweep',
    },
  );
  logger.info({ cron: env.HAZARD_EXPIRY_CRON }, 'registered hazard-expiry schedule');
};

/**
 * Remove any existing repeatable jobs for the given queue names. Used during
 * graceful shutdown of a single-shot migration, or in tests to clear state
 * between runs. Not normally called during production boot.
 */
export const clearSchedules = async (queues: Queue[], logger: Logger): Promise<void> => {
  for (const queue of queues) {
    const repeatables = await queue.getRepeatableJobs();
    for (const r of repeatables) {
      await queue.removeRepeatableByKey(r.key);
      logger.info({ queue: queue.name, key: r.key }, 'removed repeatable job');
    }
  }
};
