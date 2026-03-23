// =============================================================================
// OpenTelemetry Tracing Configuration
// =============================================================================

import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { AWSXRayPropagator } from '@opentelemetry/propagator-aws-xray';
import { AWSXRayIdGenerator } from '@opentelemetry/id-generator-aws-xray';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
  SEMRESATTRS_DEPLOYMENT_ENVIRONMENT,
} from '@opentelemetry/semantic-conventions';
import { config } from '../config/index.js';

let sdk: NodeSDK | null = null;

export function initTracing(): void {
  if (sdk) {
    return; // Already initialized
  }

  // Resource attributes
  const resource = resourceFromAttributes({
    [ATTR_SERVICE_NAME]: config.OTEL_SERVICE_NAME,
    [ATTR_SERVICE_VERSION]: process.env['npm_package_version'] ?? '1.0.0',
    [SEMRESATTRS_DEPLOYMENT_ENVIRONMENT]: config.NODE_ENV,
    'aws.region': config.AWS_REGION,
    'region.key': config.REGION_KEY,
    'region.is_primary': String(config.IS_PRIMARY_REGION),
    'region.tier': config.REGION_TIER,
  });

  // OTLP exporter (sends to X-Ray daemon or OTLP collector)
  const traceExporter = new OTLPTraceExporter({
    url: config.OTEL_EXPORTER_OTLP_ENDPOINT ?? 'http://localhost:4318/v1/traces',
  });

  // Initialize SDK
  sdk = new NodeSDK({
    resource,
    traceExporter,
    instrumentations: [
      getNodeAutoInstrumentations({
        // Disable some noisy instrumentations
        '@opentelemetry/instrumentation-fs': {
          enabled: false,
        },
        '@opentelemetry/instrumentation-dns': {
          enabled: false,
        },
        // Configure HTTP instrumentation
        '@opentelemetry/instrumentation-http': {
          ignoreIncomingRequestHook: (request) => {
            const url = request.url ?? '';
            return url.startsWith('/health') || url.startsWith('/metrics');
          },
        },
      }),
    ],
    // AWS X-Ray compatible propagator and ID generator
    textMapPropagator: new AWSXRayPropagator(),
    idGenerator: new AWSXRayIdGenerator(),
  });

  // Start the SDK
  sdk.start();

  // eslint-disable-next-line no-console -- startup log before logger is available
  console.log('OpenTelemetry tracing initialized');
}

export function shutdownTracing(): Promise<void> {
  if (sdk) {
    return sdk.shutdown();
  }
  return Promise.resolve();
}

// Re-export tracing utilities
export { trace, context, SpanStatusCode } from '@opentelemetry/api';
export type { Span, SpanContext, Tracer } from '@opentelemetry/api';
