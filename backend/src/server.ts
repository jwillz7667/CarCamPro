import { env } from './config/env.js';
import { logger } from './config/logger.js';
import { maybeStartOtel, maybeStopOtel } from './config/otel.js';

/**
 * Process entrypoint. Boots Fastify, wires SIGTERM/SIGINT to a graceful
 * shutdown (drains in-flight requests, then closes DB + Redis handles).
 *
 * OTel initialization happens BEFORE `buildApp` is imported so auto-
 * instrumentations can patch Fastify / Prisma / ioredis on their first
 * require. `buildApp` is imported dynamically for the same reason.
 */
const main = async () => {
  await maybeStartOtel({ mode: 'api' });

  const { buildApp } = await import('./app.js');
  const app = await buildApp();

  const shutdown = async (signal: string) => {
    logger.info({ signal }, 'shutdown signal received');
    try {
      await app.close();
      await maybeStopOtel();
      process.exit(0);
    } catch (err) {
      logger.error({ err }, 'error during shutdown');
      process.exit(1);
    }
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));

  process.on('uncaughtException', (err) => {
    logger.fatal({ err }, 'uncaught exception');
    process.exit(1);
  });

  process.on('unhandledRejection', (reason) => {
    logger.fatal({ reason }, 'unhandled rejection');
    process.exit(1);
  });

  try {
    await app.listen({ host: env.HOST, port: env.PORT });
  } catch (err) {
    logger.fatal({ err }, 'failed to start server');
    process.exit(1);
  }
};

void main();
