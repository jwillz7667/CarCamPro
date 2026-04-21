import {
  S3Client,
  DeleteObjectCommand,
  HeadObjectCommand,
  type HeadObjectCommandOutput,
} from '@aws-sdk/client-s3';
import { PutObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { FastifyInstance } from 'fastify';
import fp from 'fastify-plugin';

import { env } from '../config/env.js';

export interface PresignUploadInput {
  bucket: string;
  key: string;
  contentType: string;
  contentLength: number;
  /// SHA-256 digest, base64-encoded. Object uploaded with a mismatching
  /// checksum is rejected by S3 / R2 / B2.
  sha256Base64: string;
}

export interface PresignDownloadInput {
  bucket: string;
  key: string;
  /// Optional lifetime override; defaults to env.S3_PRESIGN_TTL.
  ttlSeconds?: number;
}

/**
 * Object-storage plugin. Wraps the AWS SDK's S3 client with a tiny domain
 * API: presign upload / download, head (exists / size check), and delete.
 * Bucket names and credentials come from env only — never pass keys through
 * request bodies.
 */
export interface StorageClient {
  presignUpload(input: PresignUploadInput, ttlSeconds?: number): Promise<string>;
  presignDownload(input: PresignDownloadInput): Promise<string>;
  head(bucket: string, key: string): Promise<HeadObjectCommandOutput | null>;
  delete(bucket: string, key: string): Promise<void>;
  readonly buckets: {
    clips: string;
    thumbs: string;
    reports: string;
  };
}

export default fp(async (app: FastifyInstance) => {
  const s3 = new S3Client({
    region: env.S3_REGION,
    endpoint: env.S3_ENDPOINT,
    credentials: {
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    },
    forcePathStyle: env.S3_FORCE_PATH_STYLE,
  });

  const storage: StorageClient = {
    buckets: {
      clips: env.S3_BUCKET_CLIPS,
      thumbs: env.S3_BUCKET_THUMBS,
      reports: env.S3_BUCKET_REPORTS,
    },

    async presignUpload(input, ttlSeconds = env.S3_PRESIGN_TTL) {
      const cmd = new PutObjectCommand({
        Bucket: input.bucket,
        Key: input.key,
        ContentType: input.contentType,
        ContentLength: input.contentLength,
        ChecksumSHA256: input.sha256Base64,
      });
      return getSignedUrl(s3, cmd, {
        expiresIn: ttlSeconds,
        unhoistableHeaders: new Set(['x-amz-checksum-sha256']),
      });
    },

    async presignDownload(input) {
      const cmd = new GetObjectCommand({
        Bucket: input.bucket,
        Key: input.key,
      });
      return getSignedUrl(s3, cmd, { expiresIn: input.ttlSeconds ?? env.S3_PRESIGN_TTL });
    },

    async head(bucket, key) {
      try {
        return await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
      } catch (err: unknown) {
        const errCode = (err as { name?: string }).name;
        if (errCode === 'NotFound' || errCode === 'NoSuchKey') return null;
        throw err;
      }
    },

    async delete(bucket, key) {
      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
    },
  };

  app.decorate('storage', storage);

  app.addHook('onClose', async () => {
    s3.destroy();
  });
}, {
  name: 'storage',
});

declare module 'fastify' {
  interface FastifyInstance {
    storage: StorageClient;
  }
}
