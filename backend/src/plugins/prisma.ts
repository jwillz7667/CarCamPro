import { PrismaClient } from '@prisma/client';
import type { FastifyInstance } from 'fastify';
import fp from 'fastify-plugin';

/**
 * Prisma plugin. Exposes a singleton `PrismaClient` on `app.prisma` and
 * disconnects cleanly on shutdown.
 */
export default fp(async (app: FastifyInstance) => {
  const prisma = new PrismaClient({
    log: [
      { level: 'warn', emit: 'event' },
      { level: 'error', emit: 'event' },
    ],
  });

  prisma.$on('warn', (e) => app.log.warn({ prisma: e }, e.message));
  prisma.$on('error', (e) => app.log.error({ prisma: e }, e.message));

  await prisma.$connect();
  app.log.info('prisma connected');

  app.decorate('prisma', prisma);

  app.addHook('onClose', async () => {
    await prisma.$disconnect();
  });
}, {
  name: 'prisma',
});

declare module 'fastify' {
  interface FastifyInstance {
    prisma: PrismaClient;
  }
}
