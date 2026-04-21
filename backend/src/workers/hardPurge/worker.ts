import type { S3Client } from '@aws-sdk/client-s3';
import type { PrismaClient } from '@prisma/client';
import { Worker, type Processor } from 'bullmq';
import type { Logger } from 'pino';

import { env } from '../../config/env.js';
import { createQueueConnection } from '../../queues/connection.js';
import { HardPurgeJobSchema } from '../../queues/jobs.js';
import { QueueNames } from '../../queues/names.js';

import { HardPurgeService } from './service.js';

export interface HardPurgeWorkerDeps {
  prisma: PrismaClient;
  s3: S3Client;
  buckets: { clips: string; thumbs: string; reports: string };
  logger: Logger;
}

/**
 * Hard-purge worker. Processes two job shapes:
 *
 *   • { userId }         → purge one specific user (admin-triggered).
 *   • { batchSize }      → scan and purge eligible users (cron-triggered).
 *
 * Scans iterate in small batches to bound worker latency: if 10 000 users
 * hit eligibility in a single day (unlikely), the scheduler will enqueue
 * repeat sweeps — we do not try to drain them all in one pass.
 */
export const buildHardPurgeWorker = (deps: HardPurgeWorkerDeps): Worker => {
  const service = new HardPurgeService({
    prisma: deps.prisma,
    s3: deps.s3,
    buckets: deps.buckets,
    cooldownDays: env.HARD_PURGE_COOLDOWN_DAYS,
    logger: deps.logger,
  });

  const processor: Processor = async (job) => {
    const payload = HardPurgeJobSchema.parse(job.data);
    const log = deps.logger.child({
      queue: QueueNames.hardPurge,
      jobId: job.id,
    });

    if (payload.userId) {
      return service.purgeUser(payload.userId);
    }

    const eligible = await service.findEligible(payload.batchSize);
    if (eligible.length === 0) {
      log.debug('no eligible users — skipping sweep');
      return { scanned: 0, purged: 0 };
    }

    log.info({ batch: eligible.length }, 'hard-purge sweep starting');

    // Sequential on purpose: one S3 ListObjectsV2 burst at a time is cheaper
    // than N parallel bursts, and most buckets rate-limit per-prefix anyway.
    let purged = 0;
    const errors: Array<{ userId: string; message: string }> = [];
    for (const userId of eligible) {
      try {
        await service.purgeUser(userId);
        purged += 1;
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        errors.push({ userId, message });
        log.error({ err, userId }, 'failed to purge user; continuing');
      }
    }

    if (errors.length > 0) {
      // Return info so BullMQ records it; still surface a throw so the job
      // ends up in the failed queue for ops review. Partial success is still
      // captured in the per-user audit logs written by `service.purgeUser`.
      throw new Error(
        `hard_purge_partial_failure: scanned=${eligible.length} purged=${purged} failed=${errors.length}`,
      );
    }

    return { scanned: eligible.length, purged, errors: [] };
  };

  return new Worker(QueueNames.hardPurge, processor, {
    connection: createQueueConnection(),
    concurrency: env.WORKER_CONCURRENCY_HARD_PURGE,
    lockDuration: 10 * 60 * 1000, // sweeps can run a while
    autorun: true,
  });
};
