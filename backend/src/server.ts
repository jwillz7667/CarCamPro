import { buildApp } from './app.js';
import { env } from './config/env.js';
import { logger } from './config/logger.js';

/**
 * Process entrypoint. Boots Fastify, wires SIGTERM/SIGINT to a graceful
 * shutdown (drains in-flight requests, then closes DB + Redis handles).
 */
const main = async () => {
  const app = await buildApp();

  const shutdown = async (signal: string) => {
    logger.info({ signal }, 'shutdown signal received');
    try {
      await app.close();
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
