import type { PrismaClient, SubscriptionTier } from '@prisma/client';

import { Errors } from '../../lib/errors.js';
import type { StorageClient } from '../../plugins/storage.js';

/**
 * Clip metadata + storage orchestrator.
 *
 * Upload flow:
 *   1. Client POSTs `/clips/init` with {size, contentType, sha256}
 *      → server creates a `Clip` row (status=PENDING) and returns a
 *        presigned PUT URL with required checksum headers.
 *   2. Client uploads directly to S3/R2.
 *   3. Client POSTs `/clips/{id}/complete` with the final duration + metadata.
 *      → server HEADs the object, validates size, flips status=UPLOADED.
 *
 * Quota enforcement is per-subscription-tier. Pro = 10 GiB, Premium =
 * effectively unlimited (100 TiB cap as a safety ceiling).
 */

const QUOTA_BYTES: Record<SubscriptionTier, bigint> = {
  FREE:    2n * 1024n * 1024n * 1024n,          // 2 GiB
  PRO:    10n * 1024n * 1024n * 1024n,          // 10 GiB
  PREMIUM: 100n * 1024n * 1024n * 1024n * 1024n, // 100 TiB
};

export interface ClipsDeps {
  prisma: PrismaClient;
  storage: StorageClient;
  presignTtlSeconds: number;
}

export class ClipsService {
  constructor(private readonly deps: ClipsDeps) {}

  /**
   * Reserve a clip slot + mint a presigned upload URL.
   */
  async initUpload(params: {
    clipId: string;
    userId: string;
    deviceId: string;
    sizeBytes: bigint;
    contentType: string;
    sha256Base64: string;
  }): Promise<{ uploadUrl: string; storageKey: string; expiresInSeconds: number }> {
    await this.enforceQuota(params.userId, params.sizeBytes);

    const storageKey = `users/${params.userId}/clips/${params.clipId}.mp4`;

    await this.deps.prisma.clip.create({
      data: {
        id: params.clipId,
        userId: params.userId,
        deviceId: params.deviceId,
        storageKey,
        sizeBytes: params.sizeBytes,
        durationSeconds: 0,
        resolution: 'unknown',
        frameRate: 0,
        codec: 'unknown',
        startedAt: new Date(),
        endedAt: new Date(),
        uploadStatus: 'PENDING',
      },
    });

    const uploadUrl = await this.deps.storage.presignUpload({
      bucket: this.deps.storage.buckets.clips,
      key: storageKey,
      contentType: params.contentType,
      contentLength: Number(params.sizeBytes),
      sha256Base64: params.sha256Base64,
    });

    return {
      uploadUrl,
      storageKey,
      expiresInSeconds: this.deps.presignTtlSeconds,
    };
  }

  /**
   * Client-side upload has finished. Verify the object exists + matches the
   * declared size, then persist the metadata the client captured
   * (resolution, duration, incident flags, GPS).
   */
  async completeUpload(params: {
    clipId: string;
    userId: string;
    durationSeconds: number;
    resolution: string;
    frameRate: number;
    codec: string;
    startedAt: Date;
    endedAt: Date;
    isProtected: boolean;
    protectionReason?: string;
    hasIncident: boolean;
    incidentSeverity?: string;
    peakGForce?: number;
    incidentTimestamp?: Date;
    startLatitude?: number;
    startLongitude?: number;
    endLatitude?: number;
    endLongitude?: number;
    averageSpeedMPH?: number;
  }) {
    const clip = await this.deps.prisma.clip.findUnique({
      where: { id: params.clipId },
    });
    if (!clip) throw Errors.notFound('Clip');
    if (clip.userId !== params.userId) throw Errors.forbidden();
    if (clip.uploadStatus !== 'PENDING' && clip.uploadStatus !== 'UPLOADING') {
      throw Errors.conflict(`Clip already in state ${clip.uploadStatus}`);
    }

    const head = await this.deps.storage.head(this.deps.storage.buckets.clips, clip.storageKey);
    if (!head || head.ContentLength === undefined) {
      throw Errors.unprocessable('Upload not found — did the PUT succeed?');
    }
    if (BigInt(head.ContentLength) !== clip.sizeBytes) {
      throw Errors.unprocessable(
        `Uploaded size ${head.ContentLength} ≠ declared size ${clip.sizeBytes}`,
      );
    }

    return this.deps.prisma.clip.update({
      where: { id: params.clipId },
      data: {
        durationSeconds: params.durationSeconds,
        resolution: params.resolution,
        frameRate: params.frameRate,
        codec: params.codec,
        startedAt: params.startedAt,
        endedAt: params.endedAt,
        isProtected: params.isProtected,
        protectionReason: params.protectionReason ?? null,
        hasIncident: params.hasIncident,
        incidentSeverity: params.incidentSeverity ?? null,
        peakGForce: params.peakGForce ?? null,
        incidentTimestamp: params.incidentTimestamp ?? null,
        startLatitude: params.startLatitude ?? null,
        startLongitude: params.startLongitude ?? null,
        endLatitude: params.endLatitude ?? null,
        endLongitude: params.endLongitude ?? null,
        averageSpeedMPH: params.averageSpeedMPH ?? null,
        uploadStatus: 'UPLOADED',
        uploadedAt: new Date(),
      },
    });
  }

  async listClips(params: {
    userId: string;
    protectedOnly?: boolean;
    cursor?: string;
    limit: number;
  }) {
    const where = {
      userId: params.userId,
      deletedAt: null,
      ...(params.protectedOnly ? { isProtected: true } : {}),
    };
    return this.deps.prisma.clip.findMany({
      where,
      orderBy: { startedAt: 'desc' },
      take: params.limit + 1,
      ...(params.cursor ? { cursor: { id: params.cursor }, skip: 1 } : {}),
    });
  }

  async getClip(params: { userId: string; clipId: string }) {
    const clip = await this.deps.prisma.clip.findUnique({ where: { id: params.clipId } });
    if (!clip || clip.deletedAt) throw Errors.notFound('Clip');
    if (clip.userId !== params.userId) throw Errors.forbidden();
    return clip;
  }

  async presignDownload(params: { userId: string; clipId: string }) {
    const clip = await this.getClip(params);
    if (clip.uploadStatus !== 'UPLOADED') {
      throw Errors.conflict('Clip not yet uploaded');
    }
    return this.deps.storage.presignDownload({
      bucket: this.deps.storage.buckets.clips,
      key: clip.storageKey,
    });
  }

  async softDelete(params: { userId: string; clipId: string }) {
    const clip = await this.getClip(params);
    if (clip.isProtected) {
      throw Errors.conflict('Protected clips must be explicitly unlocked before deletion');
    }
    await this.deps.prisma.clip.update({
      where: { id: params.clipId },
      data: { deletedAt: new Date() },
    });
  }

  // MARK: - Quota

  private async enforceQuota(userId: string, newSize: bigint): Promise<void> {
    const user = await this.deps.prisma.user.findUnique({
      where: { id: userId },
      select: { subscriptionTier: true, storageQuotaBytes: true },
    });
    if (!user) throw Errors.notFound('User');

    const quota = user.storageQuotaBytes ?? QUOTA_BYTES[user.subscriptionTier];

    const agg = await this.deps.prisma.clip.aggregate({
      where: { userId, uploadStatus: 'UPLOADED', deletedAt: null },
      _sum: { sizeBytes: true },
    });

    const used = agg._sum.sizeBytes ?? 0n;
    if (used + newSize > quota) {
      throw Errors.paymentRequired(
        `Storage quota exceeded: used ${used} + new ${newSize} > quota ${quota}`,
      );
    }
  }

  static quotaFor(tier: SubscriptionTier): bigint {
    return QUOTA_BYTES[tier];
  }
}
