import { S3Client } from '@aws-sdk/client-s3';
import { PrismaClient } from '@prisma/client';
import type { Worker } from 'bullmq';

import { env } from './config/env.js';
import { logger } from './config/logger.js';
import { maybeStartOtel, maybeStopOtel } from './config/otel.js';
import { QueueRegistry } from './queues/index.js';
import { buildHardPurgeWorker } from './workers/hardPurge/worker.js';
import { buildHazardExpiryWorker } from './workers/hazardExpiry/worker.js';
import { buildIncidentReportWorker } from './workers/incidentReport/worker.js';
import { registerSchedules } from './workers/scheduler.js';

/**
 * Worker process entrypoint — a separate deploy unit from the Fastify API.
 *
 * Why separate?
 *   • Workers do CPU-heavy things (PDF rendering, bulk S3 ops). Isolating
 *     them prevents a runaway job from starving API request latency.
 *   • Horizontal scaling is different — we scale API on requests/sec,
 *     workers on queue depth.
 *   • Restarts can be independent. A bad worker deploy doesn't take the
 *     API down, and vice versa.
 *
 * Responsibilities on boot:
 *   1. Initialize OTel (if enabled) BEFORE importing any instrumented lib.
 *      `config/otel.ts` handles the enable-flag gating internally.
 *   2. Open shared resources: Prisma, S3, BullMQ queues.
 *   3. Spin up each worker with its own Redis connection + concurrency.
 *   4. Register cron schedules idempotently.
 *   5. Handle SIGTERM/SIGINT — stop accepting new jobs, finish in-flight,
 *      close resources, exit.
 */
const main = async () => {
  await maybeStartOtel({ mode: 'worker' });

  const prisma = new PrismaClient();
  await prisma.$connect();
  logger.info('prisma connected (worker)');

  const s3 = new S3Client({
    region: env.S3_REGION,
    endpoint: env.S3_ENDPOINT,
    credentials: {
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    },
    forcePathStyle: env.S3_FORCE_PATH_STYLE,
  });

  const queues = new QueueRegistry();
  queues.attachObservability();

  const workers: Worker[] = [
    buildIncidentReportWorker({
      prisma,
      s3,
      bucket: env.S3_BUCKET_REPORTS,
      logger,
    }),
    buildHardPurgeWorker({
      prisma,
      s3,
      buckets: {
        clips: env.S3_BUCKET_CLIPS,
        thumbs: env.S3_BUCKET_THUMBS,
        reports: env.S3_BUCKET_REPORTS,
      },
      logger,
    }),
    buildHazardExpiryWorker({ prisma, logger }),
  ];

  for (const w of workers) {
    w.on('error', (err) => logger.error({ err, worker: w.name }, 'worker error'));
    w.on('failed', (job, err) =>
      logger.warn({ worker: w.name, jobId: job?.id, err }, 'job failed'),
    );
    w.on('completed', (job) =>
      logger.debug({ worker: w.name, jobId: job.id }, 'job completed'),
    );
  }

  await registerSchedules({
    hardPurgeQueue: queues.hardPurge,
    hazardExpiryQueue: queues.hazardExpiry,
    logger,
  });

  logger.info(
    {
      workers: workers.map((w) => w.name),
      concurrency: {
        incident: env.WORKER_CONCURRENCY_INCIDENT_REPORT,
        purge: env.WORKER_CONCURRENCY_HARD_PURGE,
        expiry: env.WORKER_CONCURRENCY_HAZARD_EXPIRY,
      },
    },
    'worker ready',
  );

  // ─── Graceful shutdown ───────────────────────────────────
  let shuttingDown = false;
  const shutdown = async (signal: string) => {
    if (shuttingDown) return;
    shuttingDown = true;
    logger.info({ signal }, 'worker shutdown starting');

    // Stop accepting new jobs, let in-flight ones finish.
    await Promise.allSettled(workers.map((w) => w.close()));
    await queues.close();
    await prisma.$disconnect();
    await maybeStopOtel();

    logger.info('worker shutdown complete');
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));

  process.on('uncaughtException', (err) => {
    logger.fatal({ err }, 'worker uncaught exception');
    process.exit(1);
  });
  process.on('unhandledRejection', (reason) => {
    logger.fatal({ reason }, 'worker unhandled rejection');
    process.exit(1);
  });
};

void main();
