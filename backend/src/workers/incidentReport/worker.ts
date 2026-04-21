import { createHash } from 'node:crypto';
import { PutObjectCommand, type S3Client } from '@aws-sdk/client-s3';
import type { PrismaClient } from '@prisma/client';
import { Worker, type Processor } from 'bullmq';
import type { Logger } from 'pino';

import { env } from '../../config/env.js';
import { createQueueConnection } from '../../queues/connection.js';
import { IncidentReportJobSchema } from '../../queues/jobs.js';
import { QueueNames } from '../../queues/names.js';

import { renderIncidentReportPdf, type IncidentReportPayload } from './renderer.js';

export interface IncidentReportWorkerDeps {
  prisma: PrismaClient;
  s3: S3Client;
  bucket: string;
  logger: Logger;
}

/**
 * Incident-report worker.
 *
 * Pipeline per job:
 *   1. Validate payload shape.
 *   2. Refetch the `IncidentReport` + related `Clip` / `Device` / `User` so
 *      we render against freshly authoritative state, not a serialized
 *      snapshot that may be minutes old.
 *   3. Render the PDF in memory.
 *   4. Upload to the reports bucket with a SHA-256 integrity header.
 *   5. Update the `IncidentReport` row with the real size so the API layer
 *      can flip its `/report` GET response from QUEUED → READY.
 *
 * Retries + backoff are configured on the queue itself (see queues/index.ts),
 * so the processor throws on any non-permanent failure and BullMQ reattempts.
 * Permanent failures (clip hard-deleted, report row vanished) return early
 * without throwing so BullMQ marks the job as "completed but no-op".
 */
export const buildIncidentReportWorker = (deps: IncidentReportWorkerDeps): Worker => {
  const processor: Processor = async (job) => {
    const payload = IncidentReportJobSchema.parse(job.data);
    const log = deps.logger.child({
      queue: QueueNames.incidentReport,
      jobId: job.id,
      reportId: payload.reportId,
    });

    const report = await deps.prisma.incidentReport.findUnique({
      where: { id: payload.reportId },
      include: {
        user: true,
        clip: { include: { device: true } },
      },
    });

    if (!report || report.deletedAt) {
      log.info('report no longer exists; skipping');
      return { skipped: 'report_missing' };
    }
    if (report.sizeBytes > 0) {
      log.info('report already rendered; skipping');
      return { skipped: 'already_rendered' };
    }

    const renderPayload: IncidentReportPayload = {
      clip: {
        id: report.clip.id,
        startedAt: report.clip.startedAt.toISOString(),
        endedAt: report.clip.endedAt.toISOString(),
        durationSeconds: report.clip.durationSeconds,
        resolution: report.clip.resolution,
        codec: report.clip.codec,
      },
      telemetry: {
        peakGForce: report.clip.peakGForce,
        severity: report.clip.incidentSeverity,
        startLatitude: report.clip.startLatitude,
        startLongitude: report.clip.startLongitude,
        endLatitude: report.clip.endLatitude,
        endLongitude: report.clip.endLongitude,
        averageSpeedMPH: report.clip.averageSpeedMPH,
      },
      user: {
        id: report.user.id,
        email: report.user.email,
        displayName: report.user.displayName,
      },
      device: report.clip.device
        ? {
            id: report.clip.device.id,
            name: report.clip.device.name,
            model: report.clip.device.model,
            osVersion: report.clip.device.osVersion,
            appVersion: report.clip.device.appVersion,
          }
        : null,
      generatedAt: new Date().toISOString(),
    };

    const { bytes, sizeBytes } = await renderIncidentReportPdf(renderPayload);
    const checksumBase64 = createHash('sha256').update(bytes).digest('base64');

    await deps.s3.send(
      new PutObjectCommand({
        Bucket: deps.bucket,
        Key: report.pdfStorageKey,
        Body: bytes,
        ContentType: 'application/pdf',
        ContentLength: sizeBytes,
        ChecksumSHA256: checksumBase64,
        Metadata: {
          reportId: report.id,
          clipId: report.clipId,
          userId: report.userId,
        },
      }),
    );

    await deps.prisma.incidentReport.update({
      where: { id: report.id },
      data: { sizeBytes, generatedAt: new Date() },
    });

    log.info({ sizeBytes }, 'incident report rendered');
    return { sizeBytes };
  };

  return new Worker(QueueNames.incidentReport, processor, {
    connection: createQueueConnection(),
    concurrency: env.WORKER_CONCURRENCY_INCIDENT_REPORT,
    lockDuration: 60_000, // PDF render + S3 PUT fits comfortably in 60s.
    autorun: true,
  });
};
