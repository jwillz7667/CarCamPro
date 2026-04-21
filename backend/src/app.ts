import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import sensible from '@fastify/sensible';
import Fastify, { type FastifyInstance } from 'fastify';
import {
  ZodTypeProvider,
  serializerCompiler,
  validatorCompiler,
} from 'fastify-type-provider-zod';
import { nanoid } from 'nanoid';

import { env, isProd } from './config/env.js';
import { logger } from './config/logger.js';
import { AppError } from './lib/errors.js';

import authPlugin from './plugins/auth.js';
import prismaPlugin from './plugins/prisma.js';
import queuesPlugin from './plugins/queues.js';
import rateLimitPlugin from './plugins/rateLimit.js';
import redisPlugin from './plugins/redis.js';
import storagePlugin from './plugins/storage.js';
import swaggerPlugin from './plugins/swagger.js';

import { adminRoutes } from './modules/admin/routes.js';
import { authRoutes } from './modules/auth/routes.js';
import { clipsRoutes } from './modules/clips/routes.js';
import { devicesRoutes } from './modules/devices/routes.js';
import { hazardsRoutes } from './modules/hazards/routes.js';
import { incidentsRoutes } from './modules/incidents/routes.js';
import { subscriptionsRoutes } from './modules/subscriptions/routes.js';
import { usersRoutes } from './modules/users/routes.js';

/**
 * Builds and returns a fully-configured Fastify instance — does NOT start
 * listening. Split from `server.ts` so tests can spin up the app without
 * binding a port.
 */
export const buildApp = async (): Promise<FastifyInstance> => {
  const app = Fastify({
    logger,
    disableRequestLogging: false,
    trustProxy: env.TRUST_PROXY,
    requestIdHeader: 'x-request-id',
    genReqId: () => nanoid(12),
    ajv: {
      customOptions: {
        removeAdditional: 'all',
        useDefaults: true,
        coerceTypes: 'array',
        allErrors: !isProd,
      },
    },
  }).withTypeProvider<ZodTypeProvider>();

  // Zod ↔ JSON schema compilers.
  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  // Security + plumbing plugins first.
  await app.register(helmet, {
    contentSecurityPolicy: isProd ? undefined : false,
    crossOriginEmbedderPolicy: false,
  });

  await app.register(cors, {
    origin: (origin, cb) => {
      if (!origin) return cb(null, true); // curl / native iOS
      if (env.ACCESS_ORIGINS.length === 0) return cb(null, true);
      if (env.ACCESS_ORIGINS.includes(origin)) return cb(null, true);
      cb(new Error('Origin not allowed'), false);
    },
    credentials: true,
  });

  await app.register(sensible);

  // Data plugins.
  await app.register(prismaPlugin);
  await app.register(redisPlugin);
  await app.register(storagePlugin);

  // Auth + rate limit + queues (depend on redis).
  await app.register(authPlugin);
  await app.register(rateLimitPlugin);
  await app.register(queuesPlugin);

  // OpenAPI must register BEFORE routes so it can hook into the compiler.
  await app.register(swaggerPlugin);

  // Health probes.
  app.get('/health', async () => ({
    ok: true,
    service: 'carcam-api',
    env: env.NODE_ENV,
    time: new Date().toISOString(),
  }));

  app.get('/health/ready', async (_req, reply) => {
    try {
      await app.prisma.$queryRaw`SELECT 1`;
      await app.redis.ping();
      return { ok: true };
    } catch (err: unknown) {
      app.log.error({ err }, 'readiness check failed');
      return reply.status(503).send({ ok: false });
    }
  });

  // Domain routes.
  await app.register(authRoutes, { prefix: '/v1/auth' });
  await app.register(usersRoutes, { prefix: '/v1/users' });
  await app.register(devicesRoutes, { prefix: '/v1/devices' });
  await app.register(clipsRoutes, { prefix: '/v1/clips' });
  await app.register(subscriptionsRoutes, { prefix: '/v1/subscriptions' });
  await app.register(incidentsRoutes, { prefix: '/v1/incidents' });
  await app.register(hazardsRoutes, { prefix: '/v1/hazards' });
  await app.register(adminRoutes, { prefix: '/v1/admin' });

  // Error handler — renders a typed JSON envelope.
  app.setErrorHandler((err, request, reply) => {
    const requestId = request.id;

    if (err instanceof AppError) {
      return reply.status(err.statusCode).send({
        error: { code: err.code, message: err.message, details: err.details },
        requestId,
      });
    }

    if ((err as { code?: string }).code === 'FST_ERR_VALIDATION') {
      return reply.status(400).send({
        error: {
          code: 'BAD_REQUEST',
          message: 'Request validation failed',
          details: err.validation,
        },
        requestId,
      });
    }

    request.log.error({ err }, 'unhandled error');
    return reply.status(500).send({
      error: {
        code: 'INTERNAL',
        message: isProd ? 'Internal server error' : err.message,
      },
      requestId,
    });
  });

  app.setNotFoundHandler((request, reply) => {
    reply.status(404).send({
      error: { code: 'NOT_FOUND', message: `Route ${request.method} ${request.url} not found` },
      requestId: request.id,
    });
  });

  return app;
};
