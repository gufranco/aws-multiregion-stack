// =============================================================================
// Custom Business Metrics
// =============================================================================

import { CloudWatchClient, PutMetricDataCommand } from '@aws-sdk/client-cloudwatch';
import { config } from '../config/index.js';
import { createLogger } from '../logger.js';

const logger = createLogger('metrics');

const cloudwatchClient = new CloudWatchClient({
  region: config.AWS_REGION,
  ...(config.USE_LOCALSTACK &&
    config.LOCALSTACK_ENDPOINT && {
      endpoint: config.LOCALSTACK_ENDPOINT,
      credentials: {
        accessKeyId: 'test',
        secretAccessKey: 'test',
      },
    }),
});

const NAMESPACE = `${config.PROJECT_NAME || 'MultiRegion'}/${config.NODE_ENV}`;

export interface MetricDimension {
  readonly Name: string;
  readonly Value: string;
}

export interface MetricData {
  readonly metricName: string;
  readonly value: number;
  readonly unit?: 'Count' | 'Seconds' | 'Milliseconds' | 'Percent' | 'Bytes' | 'None';
  readonly dimensions?: readonly MetricDimension[];
}

export async function publishMetric(metric: MetricData): Promise<void> {
  try {
    const defaultDimensions: MetricDimension[] = [
      { Name: 'Region', Value: config.AWS_REGION },
      { Name: 'Service', Value: config.OTEL_SERVICE_NAME || 'unknown' },
      { Name: 'Environment', Value: config.NODE_ENV },
    ];

    await cloudwatchClient.send(
      new PutMetricDataCommand({
        Namespace: NAMESPACE,
        MetricData: [
          {
            MetricName: metric.metricName,
            Value: metric.value,
            Unit: metric.unit ?? 'Count',
            Dimensions: [...defaultDimensions, ...(metric.dimensions ?? [])],
            Timestamp: new Date(),
          },
        ],
      }),
    );
  } catch (error) {
    logger.error({ error, metric }, 'Failed to publish metric');
  }
}

export async function publishMetrics(metrics: MetricData[]): Promise<void> {
  try {
    const defaultDimensions: MetricDimension[] = [
      { Name: 'Region', Value: config.AWS_REGION },
      { Name: 'Service', Value: config.OTEL_SERVICE_NAME || 'unknown' },
      { Name: 'Environment', Value: config.NODE_ENV },
    ];

    await cloudwatchClient.send(
      new PutMetricDataCommand({
        Namespace: NAMESPACE,
        MetricData: metrics.map((metric) => ({
          MetricName: metric.metricName,
          Value: metric.value,
          Unit: metric.unit ?? 'Count',
          Dimensions: [...defaultDimensions, ...(metric.dimensions ?? [])],
          Timestamp: new Date(),
        })),
      }),
    );
  } catch (error) {
    logger.error({ error, metricsCount: metrics.length }, 'Failed to publish metrics');
  }
}

// =============================================================================
// Pre-defined Business Metrics
// =============================================================================

export const BusinessMetrics = {
  // Order metrics
  orderCreated: (customerId: string) =>
    publishMetric({
      metricName: 'OrdersCreated',
      value: 1,
      unit: 'Count',
      dimensions: [{ Name: 'CustomerId', Value: customerId }],
    }),

  orderConfirmed: (orderId: string) =>
    publishMetric({
      metricName: 'OrdersConfirmed',
      value: 1,
      unit: 'Count',
      dimensions: [{ Name: 'OrderId', Value: orderId }],
    }),

  orderCancelled: (orderId: string, reason: string) =>
    publishMetric({
      metricName: 'OrdersCancelled',
      value: 1,
      unit: 'Count',
      dimensions: [
        { Name: 'OrderId', Value: orderId },
        { Name: 'Reason', Value: reason },
      ],
    }),

  orderValue: (amount: number) =>
    publishMetric({
      metricName: 'OrderValue',
      value: amount,
      unit: 'None',
    }),

  // API metrics
  requestLatency: (endpoint: string, method: string, durationMs: number) =>
    publishMetric({
      metricName: 'RequestLatency',
      value: durationMs,
      unit: 'Milliseconds',
      dimensions: [
        { Name: 'Endpoint', Value: endpoint },
        { Name: 'Method', Value: method },
      ],
    }),

  requestError: (endpoint: string, method: string, statusCode: number) =>
    publishMetric({
      metricName: 'RequestErrors',
      value: 1,
      unit: 'Count',
      dimensions: [
        { Name: 'Endpoint', Value: endpoint },
        { Name: 'Method', Value: method },
        { Name: 'StatusCode', Value: statusCode.toString() },
      ],
    }),

  // Queue metrics
  messagesProcessed: (queueName: string, count: number = 1) =>
    publishMetric({
      metricName: 'MessagesProcessed',
      value: count,
      unit: 'Count',
      dimensions: [{ Name: 'QueueName', Value: queueName }],
    }),

  messagesFailed: (queueName: string, count: number = 1) =>
    publishMetric({
      metricName: 'MessagesFailed',
      value: count,
      unit: 'Count',
      dimensions: [{ Name: 'QueueName', Value: queueName }],
    }),

  // Custom generic metric
  custom: (
    name: string,
    value: number,
    unit?: MetricData['unit'],
    dimensions?: MetricDimension[],
  ) =>
    publishMetric({
      metricName: name,
      value,
      ...(unit && { unit }),
      ...(dimensions && { dimensions }),
    }),
};

// =============================================================================
// Metrics Hooks for Fastify
// =============================================================================

// Attach a start timestamp before the request is processed.
// Use as: fastify.addHook('onRequest', metricsOnRequest)
export async function metricsOnRequest(request: {
  method: string;
  url: string;
  startTime?: number;
}): Promise<void> {
  request.startTime = Date.now();
}

// Measure the full request duration after the response is sent.
// Use as: fastify.addHook('onResponse', metricsOnResponse)
export async function metricsOnResponse(
  request: { method: string; url: string; startTime?: number },
  reply: { statusCode: number },
): Promise<void> {
  const duration = request.startTime ? Date.now() - request.startTime : 0;
  const endpoint = request.url.split('?')[0] ?? request.url;

  await BusinessMetrics.requestLatency(endpoint, request.method, duration);

  if (reply.statusCode >= 400) {
    await BusinessMetrics.requestError(endpoint, request.method, reply.statusCode);
  }
}
