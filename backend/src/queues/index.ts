import { Queue, QueueEvents, type JobsOptions } from 'bullmq';

import { logger } from '../config/logger.js';

import { createQueueConnection } from './connection.js';
import type {
  HardPurgeJob,
  HazardExpiryJob,
  IncidentReportJob,
} from './jobs.js';
import {
  HardPurgeJobSchema,
  HazardExpiryJobSchema,
  IncidentReportJobSchema,
} from './jobs.js';
import { QueueNames } from './names.js';

/**
 * Typed producer for our three queues. Consumers (workers) live in
 * `src/workers/*` — they are deliberately NOT referenced from this file so
 * the API process can import the producer without pulling in worker code
 * (PDFKit etc) and inflating the cold-start footprint.
 *
 * Design notes:
 *   • One shared Redis connection per producer is cheaper than N connections
 *     but risks one queue's slow Redis op blocking the others. We accept the
 *     trade-off because producer ops are all O(1) RPUSH + XADD — never
 *     blocking. Workers open their own connections.
 *   • Defaults on `JobsOptions` favor durability: `removeOnComplete.age`
 *     lets us inspect recent successes for ops while keeping Redis bounded.
 *   • `attempts` + exponential backoff is set per producer rather than
 *     globally so slow-growing tasks (PDFs) and must-not-lose tasks (GDPR)
 *     can tune independently.
 */
export class QueueRegistry {
  private readonly connection = createQueueConnection();
  private readonly events: QueueEvents[] = [];

  readonly incidentReport = new Queue<IncidentReportJob>(QueueNames.incidentReport, {
    connection: this.connection,
    defaultJobOptions: {
      attempts: 5,
      backoff: { type: 'exponential', delay: 30_000 },
      removeOnComplete: { age: 60 * 60 * 24 * 7, count: 10_000 }, // 7 days
      removeOnFail: { age: 60 * 60 * 24 * 30 },                   // 30 days
    },
  });

  readonly hardPurge = new Queue<HardPurgeJob>(QueueNames.hardPurge, {
    connection: this.connection,
    defaultJobOptions: {
      attempts: 3,
      backoff: { type: 'exponential', delay: 60_000 },
      removeOnComplete: { age: 60 * 60 * 24 * 30 },
      removeOnFail: { age: 60 * 60 * 24 * 90 },
    },
  });

  readonly hazardExpiry = new Queue<HazardExpiryJob>(QueueNames.hazardExpiry, {
    connection: this.connection,
    defaultJobOptions: {
      attempts: 2,
      backoff: { type: 'fixed', delay: 60_000 },
      removeOnComplete: { age: 60 * 60 * 24 },
      removeOnFail: { age: 60 * 60 * 24 * 7 },
    },
  });

  /**
   * Emit structured logs when jobs fail or stall so ops can wire alerts
   * without touching worker code.
   */
  attachObservability(): void {
    for (const queue of [this.incidentReport, this.hardPurge, this.hazardExpiry]) {
      const evs = new QueueEvents(queue.name, { connection: createQueueConnection() });
      evs.on('failed', ({ jobId, failedReason }) => {
        logger.error({ queue: queue.name, jobId, failedReason }, 'queue job failed');
      });
      evs.on('stalled', ({ jobId }) => {
        logger.warn({ queue: queue.name, jobId }, 'queue job stalled');
      });
      this.events.push(evs);
    }
  }

  /** Typed producer helpers. Validate every payload client-side so a bad
   *  shape never reaches Redis. */
  async enqueueIncidentReport(payload: IncidentReportJob, options?: JobsOptions): Promise<string> {
    const parsed = IncidentReportJobSchema.parse(payload);
    // BullMQ reserves `:` inside job IDs for its own key prefixing, so the
    // separator is `-` here; the report ULID is already unique.
    const job = await this.incidentReport.add('render', parsed, {
      jobId: `incident-${parsed.reportId}`, // idempotent — one report per clip
      ...options,
    });
    return job.id ?? parsed.reportId;
  }

  async enqueueHardPurge(payload: HardPurgeJob, options?: JobsOptions): Promise<string> {
    const parsed = HardPurgeJobSchema.parse(payload);
    const jobId = parsed.userId ? `purge-user-${parsed.userId}` : `purge-scan-${Date.now()}`;
    const job = await this.hardPurge.add('purge', parsed, { jobId, ...options });
    return job.id ?? jobId;
  }

  async enqueueHazardExpiry(
    payload: HazardExpiryJob = { batchSize: 1000 },
    options?: JobsOptions,
  ): Promise<string> {
    const parsed = HazardExpiryJobSchema.parse(payload);
    const job = await this.hazardExpiry.add('sweep', parsed, options);
    return job.id ?? 'sweep';
  }

  async close(): Promise<void> {
    await Promise.allSettled([
      this.incidentReport.close(),
      this.hardPurge.close(),
      this.hazardExpiry.close(),
      ...this.events.map((e) => e.close()),
    ]);
    await this.connection.quit().catch(() => void 0);
  }
}

export interface QueueSnapshot {
  name: string;
  waiting: number;
  active: number;
  delayed: number;
  failed: number;
  completed: number;
}

/**
 * Derive a human-readable queue health snapshot — used by the admin
 * dashboard and `/health/ready` if we ever surface it.
 */
export const snapshotQueues = async (registry: QueueRegistry): Promise<QueueSnapshot[]> => {
  const snapshot = async (queue: Queue): Promise<QueueSnapshot> => {
    const counts = await queue.getJobCounts('waiting', 'active', 'delayed', 'failed', 'completed');
    return {
      name: queue.name,
      waiting: Number(counts['waiting'] ?? 0),
      active: Number(counts['active'] ?? 0),
      delayed: Number(counts['delayed'] ?? 0),
      failed: Number(counts['failed'] ?? 0),
      completed: Number(counts['completed'] ?? 0),
    };
  };
  return Promise.all([
    snapshot(registry.incidentReport),
    snapshot(registry.hardPurge),
    snapshot(registry.hazardExpiry),
  ]);
};
