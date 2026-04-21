import type { PrismaClient } from '@prisma/client';
import { Worker, type Processor } from 'bullmq';
import type { Logger } from 'pino';

import { env } from '../../config/env.js';
import { createQueueConnection } from '../../queues/connection.js';
import { HazardExpiryJobSchema } from '../../queues/jobs.js';
import { QueueNames } from '../../queues/names.js';

export interface HazardExpiryWorkerDeps {
  prisma: PrismaClient;
  logger: Logger;
}

/**
 * Hazard-sighting expiry sweep.
 *
 * Policy:
 *   • Sightings carry an `expiresAt` set at write time (default: now + 2h);
 *     upvotes extend expiry by 1h (handled in the vote route). Once
 *     `expiresAt` is in the past, the sighting is no longer shown — but the
 *     row still occupies space + indexes, so we periodically delete them.
 *   • `HazardVote` rows cascade-delete with the parent sighting
 *     (`onDelete: Cascade` in the schema).
 *   • We delete in bounded batches so a huge backlog can't lock the table
 *     or produce pathological WAL growth.
 *
 * Not safety-critical — if this worker is down for a day the only cost is
 * a larger `hazard_sightings` table. Expired rows are already excluded from
 * `GET /nearby` via a SQL predicate.
 */
export const buildHazardExpiryWorker = (deps: HazardExpiryWorkerDeps): Worker => {
  const processor: Processor = async (job) => {
    const payload = HazardExpiryJobSchema.parse(job.data);
    const log = deps.logger.child({
      queue: QueueNames.hazardExpiry,
      jobId: job.id,
    });

    const now = new Date();
    // Prisma's `deleteMany` does NOT support LIMIT, so we select the IDs
    // first, then delete the slice. Keeps individual statements bounded.
    const expired = await deps.prisma.hazardSighting.findMany({
      where: { expiresAt: { lt: now } },
      select: { id: true },
      take: payload.batchSize,
    });

    if (expired.length === 0) {
      log.debug('no expired sightings');
      return { deleted: 0 };
    }

    const { count } = await deps.prisma.hazardSighting.deleteMany({
      where: { id: { in: expired.map((r) => r.id) } },
    });

    log.info({ deleted: count }, 'hazard sightings expired');
    return { deleted: count };
  };

  return new Worker(QueueNames.hazardExpiry, processor, {
    connection: createQueueConnection(),
    concurrency: env.WORKER_CONCURRENCY_HAZARD_EXPIRY,
    autorun: true,
  });
};
