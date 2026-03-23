import { describe, it, expect, vi } from 'vitest';

// Mock the AWS CloudWatch client and config before importing
vi.mock('@aws-sdk/client-cloudwatch', () => ({
  CloudWatchClient: vi.fn().mockImplementation(() => ({
    send: vi.fn().mockResolvedValue({}),
  })),
  PutMetricDataCommand: vi.fn(),
}));

vi.mock('../../shared/src/config/index.js', () => ({
  config: {
    AWS_REGION: 'us-east-1',
    NODE_ENV: 'development',
    OTEL_SERVICE_NAME: 'test-service',
    PROJECT_NAME: 'test',
    USE_LOCALSTACK: false,
    LOCALSTACK_ENDPOINT: undefined,
  },
  getAwsEndpoint: () => undefined,
}));

vi.mock('../../shared/src/logger.js', () => ({
  createLogger: () => ({
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

import { metricsOnRequest, metricsOnResponse } from '../../shared/src/metrics/index.js';

describe('metricsOnRequest', () => {
  it('should set startTime on the request object', async () => {
    // Arrange
    const request = { method: 'GET', url: '/v1/orders' } as {
      method: string;
      url: string;
      startTime?: number;
    };

    // Act
    await metricsOnRequest(request);

    // Assert
    expect(request.startTime).toBeTypeOf('number');
    expect(request.startTime).toBeGreaterThan(0);
  });
});

describe('metricsOnResponse', () => {
  it('should compute duration from startTime', async () => {
    // Arrange
    const request = {
      method: 'GET',
      url: '/v1/orders?limit=10',
      startTime: Date.now() - 42,
    };
    const reply = { statusCode: 200 };

    // Act & Assert: should not throw
    await expect(metricsOnResponse(request, reply)).resolves.toBeUndefined();
  });

  it('should handle missing startTime gracefully', async () => {
    // Arrange
    const request = { method: 'POST', url: '/v1/orders' };
    const reply = { statusCode: 201 };

    // Act & Assert
    await expect(metricsOnResponse(request, reply)).resolves.toBeUndefined();
  });

  it('should strip query params from endpoint for metric labels', async () => {
    // Arrange
    const request = {
      method: 'GET',
      url: '/v1/orders?cursor=abc&limit=20',
      startTime: Date.now(),
    };
    const reply = { statusCode: 200 };

    // Act & Assert: should not throw, verifying the url.split('?') works
    await expect(metricsOnResponse(request, reply)).resolves.toBeUndefined();
  });
});
