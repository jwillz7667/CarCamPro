import pino from 'pino';

import { env, isProd } from './env.js';

/**
 * Root Pino logger. Structured JSON in production, pretty-printed in dev.
 * Fastify's own logger attaches a child logger per-request so correlation
 * IDs flow through automatically.
 */
export const logger = pino({
  level: env.LOG_LEVEL,
  base: {
    service: 'carcam-api',
    env: env.NODE_ENV,
  },
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      'req.body.password',
      'req.body.refreshToken',
      'req.body.identityToken',
      '*.password',
      '*.refreshToken',
      '*.identityToken',
      '*.appleSignedPayload',
    ],
    censor: '[REDACTED]',
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  ...(isProd
    ? {}
    : {
        transport: {
          target: 'pino-pretty',
          options: {
            colorize: true,
            ignore: 'pid,hostname,service,env',
            translateTime: 'SYS:HH:MM:ss.l',
          },
        },
      }),
});
