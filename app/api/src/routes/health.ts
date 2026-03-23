// =============================================================================
// Health Routes
// =============================================================================

import type { FastifyInstance } from 'fastify';
import { config, checkSqsHealth, type HealthStatus } from '@blueprint/shared';
import { checkDatabaseHealth, checkRedisHealth } from '../services/health.js';

const startTime = Date.now();

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  // Basic health check (for ALB/Global Accelerator)
  app.get(
    '/health',
    {
      schema: {
        tags: ['Health'],
        summary: 'Basic health check',
        description: 'Returns 200 if the service is running',
        response: {
          200: {
            type: 'object',
            properties: {
              status: { type: 'string', enum: ['healthy', 'degraded', 'unhealthy'] },
              region: { type: 'string' },
              regionKey: { type: 'string' },
              isPrimary: { type: 'boolean' },
              tier: { type: 'string' },
              timestamp: { type: 'string', format: 'date-time' },
              version: { type: 'string' },
              uptime: { type: 'number' },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const status: Partial<HealthStatus> = {
        status: 'healthy',
        region: config.AWS_REGION,
        regionKey: config.REGION_KEY,
        isPrimary: config.IS_PRIMARY_REGION,
        tier: config.REGION_TIER,
        timestamp: new Date().toISOString(),
        version: process.env['npm_package_version'] ?? '1.0.0',
        uptime: Math.floor((Date.now() - startTime) / 1000),
      };

      return reply.send(status);
    },
  );

  // Detailed health check (for monitoring)
  app.get(
    '/health/detailed',
    {
      schema: {
        tags: ['Health'],
        summary: 'Detailed health check',
        description: 'Returns health status of all dependencies',
        response: {
          '2xx': {
            type: 'object',
            properties: {
              status: { type: 'string', enum: ['healthy', 'degraded', 'unhealthy'] },
              region: { type: 'string' },
              regionKey: { type: 'string' },
              isPrimary: { type: 'boolean' },
              tier: { type: 'string' },
              timestamp: { type: 'string', format: 'date-time' },
              version: { type: 'string' },
              uptime: { type: 'number' },
              checks: {
                type: 'object',
                properties: {
                  database: { type: 'string', enum: ['ok', 'error'] },
                  redis: { type: 'string', enum: ['ok', 'error'] },
                  sqs: { type: 'string', enum: ['ok', 'error'] },
                  sns: { type: 'string', enum: ['ok', 'error'] },
                },
              },
            },
          },
          503: {
            type: 'object',
            properties: {
              status: { type: 'string' },
              region: { type: 'string' },
              regionKey: { type: 'string' },
              isPrimary: { type: 'boolean' },
              tier: { type: 'string' },
              timestamp: { type: 'string', format: 'date-time' },
              version: { type: 'string' },
              uptime: { type: 'number' },
              checks: { type: 'object' },
            },
          },
        },
      },
    },
    async (request, reply) => {
      // Run all health checks in parallel
      const [dbHealth, redisHealth, sqsHealth] = await Promise.all([
        checkDatabaseHealth(),
        checkRedisHealth(),
        checkSqsHealth(),
      ]);

      const checks = {
        database: dbHealth ? 'ok' : 'error',
        redis: redisHealth ? 'ok' : 'error',
        sqs: sqsHealth ? 'ok' : 'error',
        sns: 'ok', // SNS doesn't have easy health check
      } as const;

      // Determine overall status
      const hasErrors = Object.values(checks).some((c) => c === 'error');
      const allErrors = Object.values(checks).every((c) => c === 'error');

      let overallStatus: 'healthy' | 'degraded' | 'unhealthy' = 'healthy';
      if (allErrors) {
        overallStatus = 'unhealthy';
      } else if (hasErrors) {
        overallStatus = 'degraded';
      }

      const status: HealthStatus = {
        status: overallStatus,
        region: config.AWS_REGION,
        regionKey: config.REGION_KEY,
        isPrimary: config.IS_PRIMARY_REGION,
        tier: config.REGION_TIER,
        timestamp: new Date().toISOString(),
        version: process.env['npm_package_version'] ?? '1.0.0',
        uptime: Math.floor((Date.now() - startTime) / 1000),
        checks,
      };

      // Return 503 if unhealthy
      const statusCode = overallStatus === 'unhealthy' ? 503 : 200;
      return reply.status(statusCode).send(status);
    },
  );

  // Liveness probe (for Kubernetes/ECS)
  app.get(
    '/health/live',
    {
      schema: {
        tags: ['Health'],
        summary: 'Liveness probe',
        description: 'Returns 200 if the process is running',
        response: {
          200: {
            type: 'object',
            properties: {
              status: { type: 'string' },
            },
          },
        },
      },
    },
    async (_request, reply) => {
      return reply.send({ status: 'ok' });
    },
  );

  // Readiness probe (for Kubernetes/ECS)
  app.get(
    '/health/ready',
    {
      schema: {
        tags: ['Health'],
        summary: 'Readiness probe',
        description: 'Returns 200 if the service is ready to accept traffic',
        response: {
          200: {
            type: 'object',
            properties: {
              status: { type: 'string' },
            },
          },
          503: {
            type: 'object',
            properties: {
              status: { type: 'string' },
              reason: { type: 'string' },
            },
          },
        },
      },
    },
    async (_request, reply) => {
      // Check critical dependencies
      const dbHealth = await checkDatabaseHealth();

      if (!dbHealth) {
        return reply.status(503).send({ status: 'not_ready', reason: 'database_unavailable' });
      }

      return reply.send({ status: 'ready' });
    },
  );
}
