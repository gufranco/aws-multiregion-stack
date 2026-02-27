// =============================================================================
// Order Routes
// =============================================================================

import type { FastifyInstance } from 'fastify';
import {
  createOrderSchema,
  cursorPaginationSchema,
  type CreateOrderInput,
  type Order,
} from '@blueprint/shared';
import { orderService } from '../services/orders.js';

export async function orderRoutes(app: FastifyInstance): Promise<void> {
  // Create order
  app.post<{ Body: CreateOrderInput }>(
    '/',
    {
      schema: {
        tags: ['Orders'],
        summary: 'Create a new order',
        description: 'Creates a new order and publishes an event to SNS',
        body: {
          type: 'object',
          required: ['customerId', 'items', 'shippingAddress'],
          properties: {
            customerId: { type: 'string', format: 'uuid' },
            items: {
              type: 'array',
              minItems: 1,
              items: {
                type: 'object',
                required: ['productId', 'productName', 'quantity', 'unitPrice', 'totalPrice'],
                properties: {
                  productId: { type: 'string', format: 'uuid' },
                  productName: { type: 'string', minLength: 1 },
                  quantity: { type: 'integer', minimum: 1 },
                  unitPrice: { type: 'number', minimum: 0 },
                  totalPrice: { type: 'number', minimum: 0 },
                },
              },
            },
            shippingAddress: {
              type: 'object',
              required: ['street', 'city', 'state', 'country', 'postalCode'],
              properties: {
                street: { type: 'string', minLength: 1 },
                city: { type: 'string', minLength: 1 },
                state: { type: 'string', minLength: 1 },
                country: { type: 'string', minLength: 2, maxLength: 2 },
                postalCode: { type: 'string', minLength: 1 },
              },
            },
            metadata: { type: 'object' },
          },
        },
        response: {
          201: {
            type: 'object',
            properties: {
              id: { type: 'string', format: 'uuid' },
              customerId: { type: 'string', format: 'uuid' },
              status: { type: 'string' },
              totalAmount: { type: 'number' },
              currency: { type: 'string' },
              items: { type: 'array' },
              shippingAddress: { type: 'object' },
              metadata: { type: 'object' },
              createdAt: { type: 'string', format: 'date-time' },
              updatedAt: { type: 'string', format: 'date-time' },
            },
          },
        },
      },
    },
    async (request, reply) => {
      // Validate input
      const input = createOrderSchema.parse(request.body);

      // Create order with idempotency key and correlation ID for tracing
      const idempotencyKey = request.headers['idempotency-key'] as string | undefined;
      const order = await orderService.createOrder(input, {
        idempotencyKey,
        correlationId: request.id,
      });

      return reply.status(201).send(order);
    }
  );

  // Get order by ID
  app.get<{ Params: { id: string } }>(
    '/:id',
    {
      schema: {
        tags: ['Orders'],
        summary: 'Get order by ID',
        params: {
          type: 'object',
          required: ['id'],
          properties: {
            id: { type: 'string', format: 'uuid' },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              id: { type: 'string', format: 'uuid' },
              customerId: { type: 'string', format: 'uuid' },
              status: { type: 'string' },
              totalAmount: { type: 'number' },
              currency: { type: 'string' },
              items: { type: 'array' },
              shippingAddress: { type: 'object' },
              metadata: { type: 'object' },
              createdAt: { type: 'string', format: 'date-time' },
              updatedAt: { type: 'string', format: 'date-time' },
            },
          },
          404: {
            type: 'object',
            properties: {
              error: {
                type: 'object',
                properties: {
                  code: { type: 'string' },
                  message: { type: 'string' },
                },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const order = await orderService.getOrder(request.params.id);
      return reply.send(order);
    }
  );

  // List orders (cursor-based pagination)
  app.get<{ Querystring: { cursor?: string; limit?: number; customerId?: string; status?: string } }>(
    '/',
    {
      schema: {
        tags: ['Orders'],
        summary: 'List orders',
        description: 'Returns cursor-paginated list of orders with optional filters',
        querystring: {
          type: 'object',
          properties: {
            cursor: { type: 'string', description: 'Opaque cursor from previous response' },
            limit: { type: 'integer', minimum: 1, maximum: 100, default: 20 },
            customerId: { type: 'string', format: 'uuid' },
            status: { type: 'string' },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              data: { type: 'array' },
              pagination: {
                type: 'object',
                properties: {
                  nextCursor: { type: 'string', nullable: true },
                  hasMore: { type: 'boolean' },
                  limit: { type: 'integer' },
                },
              },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const pagination = cursorPaginationSchema.parse(request.query);
      const filters = {
        customerId: request.query.customerId,
        status: request.query.status,
      };

      const result = await orderService.listOrders(pagination, filters);
      return reply.send(result);
    }
  );

  // Update order status
  app.patch<{ Params: { id: string }; Body: { status: string } }>(
    '/:id/status',
    {
      schema: {
        tags: ['Orders'],
        summary: 'Update order status',
        params: {
          type: 'object',
          required: ['id'],
          properties: {
            id: { type: 'string', format: 'uuid' },
          },
        },
        body: {
          type: 'object',
          required: ['status'],
          properties: {
            status: {
              type: 'string',
              enum: ['pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled'],
            },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              id: { type: 'string', format: 'uuid' },
              status: { type: 'string' },
              updatedAt: { type: 'string', format: 'date-time' },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const order = await orderService.updateOrderStatus(
        request.params.id,
        request.body.status as Order['status']
      );
      return reply.send(order);
    }
  );

  // Cancel order
  app.delete<{ Params: { id: string } }>(
    '/:id',
    {
      schema: {
        tags: ['Orders'],
        summary: 'Cancel order',
        params: {
          type: 'object',
          required: ['id'],
          properties: {
            id: { type: 'string', format: 'uuid' },
          },
        },
        response: {
          200: {
            type: 'object',
            properties: {
              id: { type: 'string', format: 'uuid' },
              status: { type: 'string' },
              message: { type: 'string' },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const order = await orderService.cancelOrder(request.params.id);
      return reply.send({
        id: order.id,
        status: order.status,
        message: 'Order cancelled successfully',
      });
    }
  );
}
