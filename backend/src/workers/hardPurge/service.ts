import {
  DeleteObjectsCommand,
  ListObjectsV2Command,
  type S3Client,
} from '@aws-sdk/client-s3';
import type { Logger } from 'pino';
import type { PrismaClient } from '@prisma/client';

/**
 * GDPR hard-purge orchestrator.
 *
 * Invariants:
 *   • Never purges a user whose cooldown has not elapsed — the worker is the
 *     ONLY code path that issues hard deletes. Anything else is a bug.
 *   • Purges S3 before the DB so a partial failure never leaves S3 objects
 *     with no row to point at them (unreachable orphans). If the DB step
 *     fails, the job is retried and we re-list an empty prefix — idempotent.
 *   • Uses `ListObjectsV2` + `DeleteObjects` in 1000-key batches (S3 API
 *     ceiling). Paginates until the prefix is drained before touching the DB.
 *   • `prisma.user.delete` cascades through all user-owned tables per the
 *     schema's `onDelete: Cascade` relations, so we don't need per-table
 *     deletes.
 */
export interface HardPurgeDeps {
  prisma: PrismaClient;
  s3: S3Client;
  buckets: {
    clips: string;
    thumbs: string;
    reports: string;
  };
  cooldownDays: number;
  logger: Logger;
}

export interface PurgeResult {
  userId: string;
  objectsDeleted: number;
  bytesDeleted: number;
}

export class HardPurgeService {
  constructor(private readonly deps: HardPurgeDeps) {}

  /**
   * Return up to `batchSize` user IDs whose soft-delete cooldown has expired.
   */
  async findEligible(batchSize: number): Promise<string[]> {
    const cutoff = new Date(Date.now() - this.deps.cooldownDays * 24 * 60 * 60 * 1000);
    const rows = await this.deps.prisma.user.findMany({
      where: { deletedAt: { lte: cutoff } },
      select: { id: true },
      take: batchSize,
      orderBy: { deletedAt: 'asc' },
    });
    return rows.map((r) => r.id);
  }

  /**
   * Purge a single user atomically. Only callable from the worker — never
   * from a user-facing route.
   */
  async purgeUser(userId: string): Promise<PurgeResult> {
    const log = this.deps.logger.child({ op: 'hard_purge', userId });

    const user = await this.deps.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      log.info('user already gone — nothing to purge');
      return { userId, objectsDeleted: 0, bytesDeleted: 0 };
    }
    if (!user.deletedAt) {
      // Defensive: refuse to purge a user who was un-soft-deleted between
      // the scan and the job executing. This path should never fire; if it
      // does, we want loud logs rather than a silent data-loss incident.
      log.error('user is not soft-deleted; refusing to purge');
      throw new Error(`HARD_PURGE_NOT_ELIGIBLE: ${userId}`);
    }
    const cooldownMs = this.deps.cooldownDays * 24 * 60 * 60 * 1000;
    if (Date.now() - user.deletedAt.getTime() < cooldownMs) {
      log.error(
        { deletedAt: user.deletedAt, cooldownDays: this.deps.cooldownDays },
        'user cooldown has not elapsed; refusing to purge',
      );
      throw new Error(`HARD_PURGE_COOLDOWN_ACTIVE: ${userId}`);
    }

    // Every user owns exactly one prefix per bucket: `users/{userId}/...`.
    const prefix = `users/${userId}/`;
    let totalObjects = 0;
    let totalBytes = 0;

    for (const bucket of [this.deps.buckets.clips, this.deps.buckets.thumbs, this.deps.buckets.reports]) {
      const tally = await this.purgePrefix(bucket, prefix, log);
      totalObjects += tally.objects;
      totalBytes += tally.bytes;
    }

    // DB cascade deletes everything user-owned. AuditLog rows survive with
    // `userId` nulled out per the schema's `onDelete: SetNull` — this is
    // intentional: we keep the security trail but lose the PII linkage.
    await this.deps.prisma.user.delete({ where: { id: userId } });
    await this.deps.prisma.auditLog.create({
      data: {
        userId: null,
        action: 'user.hard_purged',
        resource: 'user',
        resourceId: userId,
        metaJson: { objectsDeleted: totalObjects, bytesDeleted: totalBytes },
      },
    });

    log.info(
      { objectsDeleted: totalObjects, bytesDeleted: totalBytes },
      'user hard-purged',
    );

    return { userId, objectsDeleted: totalObjects, bytesDeleted: totalBytes };
  }

  // ─────────────────────────────────────────────────────────
  // Internals
  // ─────────────────────────────────────────────────────────

  /**
   * Delete every object under the given prefix, paginating over the 1000-key
   * list cap. Returns the counts for audit logging.
   */
  private async purgePrefix(
    bucket: string,
    prefix: string,
    log: Logger,
  ): Promise<{ objects: number; bytes: number }> {
    let continuationToken: string | undefined;
    let objects = 0;
    let bytes = 0;

    do {
      const listed = await this.deps.s3.send(
        new ListObjectsV2Command({
          Bucket: bucket,
          Prefix: prefix,
          ContinuationToken: continuationToken,
          MaxKeys: 1000,
        }),
      );
      const contents = listed.Contents ?? [];
      if (contents.length === 0) break;

      const keys = contents.map((obj) => ({ Key: obj.Key! }));
      await this.deps.s3.send(
        new DeleteObjectsCommand({
          Bucket: bucket,
          Delete: { Objects: keys, Quiet: true },
        }),
      );

      for (const o of contents) {
        objects += 1;
        bytes += Number(o.Size ?? 0);
      }
      continuationToken = listed.IsTruncated ? listed.NextContinuationToken : undefined;
    } while (continuationToken);

    if (objects > 0) {
      log.info({ bucket, prefix, objects, bytes }, 'purged s3 prefix');
    }
    return { objects, bytes };
  }
}
