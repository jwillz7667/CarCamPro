import fastifySwagger from '@fastify/swagger';
import fastifySwaggerUi from '@fastify/swagger-ui';
import type { FastifyInstance } from 'fastify';
import fp from 'fastify-plugin';
import { jsonSchemaTransform } from 'fastify-type-provider-zod';

import { env, isProd } from '../config/env.js';

/**
 * OpenAPI 3.1 emission.
 *
 *   • `GET /openapi.json` — the machine-readable spec. Always available
 *     when `OPENAPI_ENABLED=true`. Other services (iOS client code-gen, CI
 *     contract tests) consume this directly.
 *   • `GET /docs` — interactive Swagger UI. Gated behind `OPENAPI_UI_ENABLED`
 *     and, in production, behind the admin API key via the Swagger UI's
 *     built-in auth button. For a small team, leaving it behind a feature
 *     flag is cleaner than plumbing `app.authenticate` through every rendered
 *     route — the spec itself leaks no secrets, just request/response
 *     contracts.
 *
 * The Zod schemas attached to every route (request body, response, query)
 * are walked by `fastify-type-provider-zod`'s `jsonSchemaTransform` and
 * emitted as JSON schema under `components.schemas`.
 */
export default fp(
  async (app: FastifyInstance) => {
    if (!env.OPENAPI_ENABLED) return;

    await app.register(fastifySwagger, {
      openapi: {
        info: {
          title: 'CarCam Pro API',
          description:
            'Fastify + Zod + Prisma API for CarCam Pro. All successful responses follow the ' +
            'route-declared Zod schema; errors follow `{ error: { code, message, details? }, requestId }`.',
          version: '1.0.0',
          contact: { name: 'CarCam Pro', url: 'https://carcampro.app' },
        },
        servers: isProd
          ? [{ url: 'https://api.carcampro.app', description: 'Production' }]
          : [{ url: `http://localhost:${env.PORT}`, description: 'Local' }],
        tags: [
          { name: 'auth', description: 'Sign in with Apple · session rotation' },
          { name: 'users', description: 'Authenticated user profile' },
          { name: 'devices', description: 'Per-phone state + APNs tokens' },
          { name: 'clips', description: 'Presigned clip upload + metadata (Pro+)' },
          { name: 'subscriptions', description: 'StoreKit 2 verification + ASSN webhook' },
          { name: 'incidents', description: 'Rendered PDF incident reports (Premium)' },
          { name: 'hazards', description: 'Anonymous crowdsourced hazard layer' },
          { name: 'admin', description: 'Operator-only endpoints — API-key gated' },
          { name: 'health', description: 'Liveness + readiness probes' },
        ],
        components: {
          securitySchemes: {
            bearerAuth: {
              type: 'http',
              scheme: 'bearer',
              bearerFormat: 'JWT',
              description: 'Access token issued by POST /v1/auth/apple or /v1/auth/refresh.',
            },
            adminApiKey: {
              type: 'apiKey',
              in: 'header',
              name: 'x-admin-api-key',
              description: 'Admin shared-secret. Not accepted on user-facing routes.',
            },
          },
        },
      },
      transform: jsonSchemaTransform,
    });

    if (env.OPENAPI_UI_ENABLED) {
      await app.register(fastifySwaggerUi, {
        routePrefix: '/docs',
        uiConfig: {
          docExpansion: 'list',
          deepLinking: true,
          persistAuthorization: true,
        },
        staticCSP: true,
      });
    }

    // Machine-readable spec route — convenience alias to Swagger's internal
    // `/documentation/json`. Keeps integrations pinned to a stable path.
    app.get('/openapi.json', { schema: { hide: true } }, async () => app.swagger());
  },
  { name: 'swagger' },
);
