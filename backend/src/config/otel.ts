import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';

import { env, isProd } from './env.js';
import { logger } from './logger.js';

/**
 * OpenTelemetry bootstrap — gated behind `OTEL_ENABLED`.
 *
 * Import ergonomics: the `@opentelemetry/sdk-node` package patches the
 * require/import graph on construction to register instrumentations. Call
 * `maybeStartOtel` BEFORE anything that you want traced is imported — in
 * practice, this means at the top of `server.ts` / `worker.ts`. If OTel
 * is disabled, neither the SDK nor any instrumentation is loaded, so the
 * runtime footprint is zero.
 *
 * Exporter: OTLP HTTP. Set `OTEL_EXPORTER_OTLP_ENDPOINT` to the collector
 * URL (e.g. https://otlp.honeycomb.io/v1/traces). Headers like
 * `x-honeycomb-team=<key>` go into `OTEL_EXPORTER_OTLP_HEADERS` as a
 * comma-separated `k=v,k=v` list.
 */

type Lifecycle = { stop: () => Promise<void> };
let active: Lifecycle | null = null;

export const maybeStartOtel = async (params: { mode: 'api' | 'worker' }): Promise<void> => {
  if (!env.OTEL_ENABLED) return;

  // Pull in the SDK lazily so we only pay the cost when actually enabled.
  const { NodeSDK } = await import('@opentelemetry/sdk-node');
  const { getNodeAutoInstrumentations } = await import(
    '@opentelemetry/auto-instrumentations-node'
  );
  const { OTLPTraceExporter } = await import(
    '@opentelemetry/exporter-trace-otlp-http'
  );
  const { resourceFromAttributes } = await import('@opentelemetry/resources');
  const { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } = await import(
    '@opentelemetry/semantic-conventions'
  );

  diag.setLogger(new DiagConsoleLogger(), isProd ? DiagLogLevel.WARN : DiagLogLevel.INFO);

  const exporter = new OTLPTraceExporter({
    ...(env.OTEL_EXPORTER_OTLP_ENDPOINT ? { url: env.OTEL_EXPORTER_OTLP_ENDPOINT } : {}),
    headers: env.OTEL_EXPORTER_OTLP_HEADERS,
  });

  const sdk = new NodeSDK({
    resource: resourceFromAttributes({
      [ATTR_SERVICE_NAME]: env.OTEL_SERVICE_NAME,
      [ATTR_SERVICE_VERSION]: process.env['npm_package_version'] ?? '0.0.0',
      'deployment.environment': env.NODE_ENV,
      'carcam.process.mode': params.mode,
    }),
    traceExporter: exporter,
    instrumentations: [
      getNodeAutoInstrumentations({
        // Fastify emits rich spans; the `@opentelemetry/instrumentation-fs`
        // module is noisy in Node 22 and rarely useful in production.
        '@opentelemetry/instrumentation-fs': { enabled: false },
        // DNS lookups add depth without value on most routes.
        '@opentelemetry/instrumentation-dns': { enabled: false },
      }),
    ],
  });

  sdk.start();
  active = {
    stop: async () => {
      try {
        await sdk.shutdown();
      } catch (err) {
        logger.warn({ err }, 'otel shutdown error');
      }
    },
  };

  logger.info(
    {
      otel: true,
      mode: params.mode,
      endpoint: env.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'default-otlp-http',
      samplerRatio: env.OTEL_SAMPLER_RATIO,
    },
    'otel tracing started',
  );
};

export const maybeStopOtel = async (): Promise<void> => {
  if (!active) return;
  await active.stop();
  active = null;
};
