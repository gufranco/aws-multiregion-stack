// =============================================================================
// Fastify Application
// =============================================================================

import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';
import { config, isAppError } from '@blueprint/shared';

import { healthRoutes } from './routes/health.js';
import { orderRoutes } from './routes/orders.js';
import { regionMiddleware } from './middleware/region.js';
import { authMiddleware } from './middleware/auth.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: config.NODE_ENV === 'production' ? 'info' : 'debug',
      ...(config.NODE_ENV === 'development' && {
        transport: {
          target: 'pino-pretty',
          options: {
            colorize: true,
            translateTime: 'SYS:standard',
          },
        },
      }),
    },
    trustProxy: true,
    requestIdHeader: 'x-request-id',
    requestIdLogLabel: 'requestId',
  });

  // ==========================================================================
  // Plugins
  // ==========================================================================

  // CORS - restrict to configured origins (defaults to same-origin only in production)
  const allowedOrigins = process.env.CORS_ALLOWED_ORIGINS?.split(',') ?? [];
  await app.register(cors, {
    origin: config.NODE_ENV === 'development' ? true : allowedOrigins,
    credentials: true,
  });

  // Security headers
  await app.register(helmet, {
    contentSecurityPolicy: false,
  });

  // Rate limiting (exclude health endpoints used by ALB/probes)
  await app.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
    keyGenerator: (request) => {
      return request.headers['x-forwarded-for']?.toString() ?? request.ip;
    },
    allowList: (request) => {
      return request.url.startsWith('/health');
    },
    errorResponseBuilder: (_request, context) => ({
      error: {
        code: 'RATE_LIMIT_EXCEEDED',
        message: `Too many requests. Retry after ${Math.ceil(context.ttl / 1000)}s`,
        retryAfter: Math.ceil(context.ttl / 1000),
      },
    }),
  });

  // OpenAPI documentation
  await app.register(swagger, {
    openapi: {
      info: {
        title: 'Multi-Region API',
        description: 'Production-grade multi-region API with ECS Fargate',
        version: '1.0.0',
      },
      servers: [
        {
          url: `http://localhost:${config.PORT}`,
          description: 'Local development',
        },
        {
          url: 'https://api.example.com',
          description: 'Production (via Global Accelerator)',
        },
      ],
      tags: [
        { name: 'Health', description: 'Health check endpoints' },
        { name: 'Orders', description: 'Order management' },
      ],
    },
  });

  await app.register(swaggerUi, {
    routePrefix: '/docs',
    uiConfig: {
      docExpansion: 'list',
      deepLinking: true,
    },
  });

  // ==========================================================================
  // Middleware
  // ==========================================================================

  // Add region info to all requests
  app.addHook('preHandler', regionMiddleware);

  // Authenticate API requests (skips health/docs endpoints)
  app.addHook('preHandler', authMiddleware);

  // ==========================================================================
  // Routes
  // ==========================================================================

  await app.register(healthRoutes, { prefix: '' });
  await app.register(orderRoutes, { prefix: '/v1/orders' });

  // ==========================================================================
  // Error Handler
  // ==========================================================================

  app.setErrorHandler((error, request, reply) => {
    request.log.error({ error }, 'Request error');

    if (isAppError(error)) {
      const { error: errBody } = error.toJSON();
      return reply.status(error.statusCode).send({
        error: { ...errBody, requestId: request.id },
      });
    }

    // Fastify validation errors
    if (error.validation) {
      return reply.status(400).send({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Invalid request',
          requestId: request.id,
          details: error.validation,
        },
      });
    }

    // Generic error
    return reply.status(500).send({
      error: {
        code: 'INTERNAL_ERROR',
        message: config.NODE_ENV === 'production' ? 'Internal server error' : error.message,
        requestId: request.id,
      },
    });
  });

  // ==========================================================================
  // Not Found Handler
  // ==========================================================================

  app.setNotFoundHandler((request, reply) => {
    return reply.status(404).send({
      error: {
        code: 'NOT_FOUND',
        message: `Route ${request.method} ${request.url} not found`,
        requestId: request.id,
      },
    });
  });

  return app;
}
