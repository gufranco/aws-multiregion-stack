// =============================================================================
// Order Service
// =============================================================================

import {
  config,
  createLogger,
  NotFoundError,
  ValidationError,
  ConflictError,
  putItem,
  getItem,
  queryItems,
  updateItem,
  transactWriteItems,
  publishOrderEvent,
  BusinessMetrics,
  cacheGet,
  cacheSet,
  cacheDelete,
  createCircuitBreaker,
  ORDER_STATUS_TRANSITIONS,
  type CreateOrderInput,
  type Order,
  type OrderStatus,
  type CursorPaginationInput,
  type CursorPaginatedResult,
  type TransactWriteItem,
} from '@blueprint/shared';

const logger = createLogger('orders');

// Circuit breaker for SNS calls. When SNS is degraded, the outbox pattern
// handles delivery, so the fallback just logs and returns a synthetic ID.
const snsBreaker = createCircuitBreaker(
  async (...args: unknown[]) => {
    const [eventType, orderId, customerId, additionalData, correlationId] = args as [
      string, string, string, Record<string, unknown> | undefined, string | undefined
    ];
    return publishOrderEvent(
      eventType as 'order.created',
      orderId,
      customerId,
      additionalData,
      correlationId,
    );
  },
  { name: 'sns-order-events', timeout: 5000, errorThresholdPercentage: 50, resetTimeout: 15000 }
);

snsBreaker.fallback(() => {
  logger.warn('SNS circuit breaker open, relying on outbox for event delivery');
  return 'fallback-outbox';
});

const ORDERS_TABLE =
  config.DYNAMODB_ORDERS_TABLE ?? `${config.PROJECT_NAME}-${config.NODE_ENV}-orders`;

const ORDER_KEY_PREFIX = 'ORDER#';
const IDEMPOTENCY_KEY_PREFIX = 'IDEMPOTENCY#';
const OUTBOX_KEY_PREFIX = 'OUTBOX#';
const HISTORY_KEY_PREFIX = 'HISTORY#';

const ENTITY_TYPE_ORDER = 'ORDER';
const CACHE_PREFIX = 'order:';
const CACHE_TTL_SECONDS = 300; // 5 minutes

interface CreateOrderOptions {
  idempotencyKey?: string;
  correlationId?: string;
}

class OrderService {
  async createOrder(input: CreateOrderInput, options?: CreateOrderOptions): Promise<Order> {
    const { idempotencyKey, correlationId } = options ?? {};

    // Check idempotency: if the same key was used before, return the existing order
    if (idempotencyKey) {
      const existing = await getItem<{ orderId: string }>(ORDERS_TABLE, {
        pk: `${IDEMPOTENCY_KEY_PREFIX}${idempotencyKey}`,
        sk: `${IDEMPOTENCY_KEY_PREFIX}${idempotencyKey}`,
      });
      if (existing) {
        logger.info({ idempotencyKey, orderId: existing.orderId }, 'Returning existing order for idempotency key');
        return this.getOrder(existing.orderId);
      }
    }

    const orderId = crypto.randomUUID();
    const eventId = crypto.randomUUID();
    const now = new Date();

    const totalAmount = input.items.reduce((sum, item) => sum + item.totalPrice, 0);

    const order: Order = {
      id: orderId,
      customerId: input.customerId,
      status: 'pending',
      items: input.items,
      shippingAddress: input.shippingAddress,
      totalAmount,
      currency: 'USD',
      metadata: input.metadata ?? {},
      createdAt: now,
      updatedAt: now,
    };

    const dynamoItem = {
      pk: `${ORDER_KEY_PREFIX}${orderId}`,
      sk: `${ORDER_KEY_PREFIX}${orderId}`,
      id: order.id,
      customerId: order.customerId,
      status: order.status,
      items: order.items,
      shippingAddress: order.shippingAddress,
      totalAmount: order.totalAmount,
      currency: order.currency,
      metadata: order.metadata,
      entityType: ENTITY_TYPE_ORDER,
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
    };

    // Atomic write: order + outbox event (+ idempotency record if key provided)
    const transactItems: TransactWriteItem[] = [
      {
        put: {
          tableName: ORDERS_TABLE,
          item: dynamoItem,
          conditionExpression: 'attribute_not_exists(pk)',
        },
      },
      {
        put: {
          tableName: ORDERS_TABLE,
          item: {
            pk: `${OUTBOX_KEY_PREFIX}${eventId}`,
            sk: `${OUTBOX_KEY_PREFIX}${eventId}`,
            eventId,
            eventType: 'order.created',
            payload: JSON.stringify({
              orderId,
              customerId: input.customerId,
              totalAmount,
              itemCount: input.items.length,
            }),
            correlationId: correlationId ?? null,
            createdAt: now.toISOString(),
            publishedAt: null,
            ttl: Math.floor(now.getTime() / 1000) + 7 * 86400,
          },
        },
      },
    ];

    if (idempotencyKey) {
      transactItems.push({
        put: {
          tableName: ORDERS_TABLE,
          item: {
            pk: `${IDEMPOTENCY_KEY_PREFIX}${idempotencyKey}`,
            sk: `${IDEMPOTENCY_KEY_PREFIX}${idempotencyKey}`,
            orderId,
            createdAt: now.toISOString(),
            ttl: Math.floor(now.getTime() / 1000) + 86400,
          },
          conditionExpression: 'attribute_not_exists(pk)',
        },
      });
    }

    try {
      await transactWriteItems(transactItems);
    } catch (error) {
      // If idempotency key conflict, return existing order
      if (idempotencyKey && (error as { name?: string }).name === 'TransactionCanceledException') {
        const existing = await getItem<{ orderId: string }>(ORDERS_TABLE, {
          pk: `${IDEMPOTENCY_KEY_PREFIX}${idempotencyKey}`,
          sk: `${IDEMPOTENCY_KEY_PREFIX}${idempotencyKey}`,
        });
        if (existing) {
          logger.info({ idempotencyKey }, 'Idempotency conflict, returning existing order');
          return this.getOrder(existing.orderId);
        }
      }
      throw error;
    }

    logger.info({ orderId, customerId: input.customerId, correlationId }, 'Order created');

    // Track business metrics
    BusinessMetrics.orderCreated(input.customerId);
    BusinessMetrics.orderValue(totalAmount);

    // Best-effort publish via circuit breaker. If SNS is degraded, the outbox handles delivery.
    try {
      const messageId = await snsBreaker.fire(
        'order.created',
        orderId,
        input.customerId,
        { totalAmount, itemCount: input.items.length },
        correlationId
      ) as string;

      if (messageId !== 'fallback-outbox') {
        await updateItem(
          ORDERS_TABLE,
          { pk: `${OUTBOX_KEY_PREFIX}${eventId}`, sk: `${OUTBOX_KEY_PREFIX}${eventId}` },
          { publishedAt: now.toISOString() }
        );
      }
    } catch (error) {
      logger.warn(
        { error, orderId, eventId },
        'Failed to publish order.created event, outbox will retry'
      );
    }

    return order;
  }

  async getOrder(orderId: string): Promise<Order> {
    // Cache-aside: check Redis first
    const cached = await cacheGet<Order>(`${CACHE_PREFIX}${orderId}`);
    if (cached) return cached;

    const item = await getItem<Order & { pk: string; sk: string }>(ORDERS_TABLE, {
      pk: `${ORDER_KEY_PREFIX}${orderId}`,
      sk: `${ORDER_KEY_PREFIX}${orderId}`,
    });

    if (!item) {
      throw new NotFoundError('Order', orderId);
    }

    const { pk, sk, ...order } = item;

    // Populate cache for subsequent reads
    await cacheSet(`${CACHE_PREFIX}${orderId}`, order, CACHE_TTL_SECONDS);

    return order as Order;
  }

  async listOrders(
    pagination: CursorPaginationInput,
    filters?: { customerId?: string; status?: string }
  ): Promise<CursorPaginatedResult<Order>> {
    const { cursor, limit } = pagination;

    // Decode the opaque cursor into a DynamoDB ExclusiveStartKey
    let exclusiveStartKey: Record<string, unknown> | undefined;
    if (cursor) {
      try {
        exclusiveStartKey = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf-8'));
      } catch {
        throw new ValidationError('Invalid pagination cursor');
      }
    }

    let result;

    if (filters?.customerId) {
      result = await queryItems<Order>(
        ORDERS_TABLE,
        'customerId = :customerId',
        { ':customerId': filters.customerId },
        {
          indexName: 'CustomerOrders',
          limit,
          exclusiveStartKey,
        }
      );
    } else if (filters?.status) {
      result = await queryItems<Order>(
        ORDERS_TABLE,
        '#status = :status',
        { ':status': filters.status },
        {
          indexName: 'StatusIndex',
          expressionAttributeNames: { '#status': 'status' },
          limit,
          exclusiveStartKey,
        }
      );
    } else {
      // Query the AllOrders GSI using the synthetic entityType partition key.
      // This avoids a full table scan that would read OUTBOX#, DEDUP#, HISTORY#,
      // and IDEMPOTENCY# items just to discard them.
      result = await queryItems<Order>(
        ORDERS_TABLE,
        'entityType = :entityType',
        { ':entityType': ENTITY_TYPE_ORDER },
        {
          indexName: 'AllOrders',
          limit,
          exclusiveStartKey,
          scanIndexForward: false,
        }
      );
    }

    // Encode the LastEvaluatedKey as an opaque base64url cursor
    const nextCursor = result.lastKey
      ? Buffer.from(JSON.stringify(result.lastKey)).toString('base64url')
      : null;

    return {
      data: result.items,
      pagination: {
        nextCursor,
        hasMore: !!result.lastKey,
        limit,
      },
    };
  }

  async updateOrderStatus(orderId: string, newStatus: OrderStatus): Promise<Order> {
    const order = await this.getOrder(orderId);
    const currentStatus = order.status;

    const allowedTransitions = ORDER_STATUS_TRANSITIONS[currentStatus];
    if (!allowedTransitions?.includes(newStatus)) {
      throw new ValidationError(
        `Invalid status transition from '${currentStatus}' to '${newStatus}'`,
        { currentStatus, newStatus, allowedTransitions }
      );
    }

    const now = new Date();
    const eventId = crypto.randomUUID();

    // Atomic write: status update + outbox event. If SNS is degraded, the outbox
    // guarantees eventual delivery without reverting a valid business state change.
    const transactItems: TransactWriteItem[] = [
      {
        update: {
          tableName: ORDERS_TABLE,
          key: { pk: `${ORDER_KEY_PREFIX}${orderId}`, sk: `${ORDER_KEY_PREFIX}${orderId}` },
          updateExpression: 'SET #status = :newStatus, #updatedAt = :now',
          conditionExpression: '#status = :expectedStatus',
          expressionAttributeNames: { '#status': 'status', '#updatedAt': 'updatedAt' },
          expressionAttributeValues: {
            ':newStatus': newStatus,
            ':expectedStatus': currentStatus,
            ':now': now.toISOString(),
          },
        },
      },
      {
        put: {
          tableName: ORDERS_TABLE,
          item: {
            pk: `${OUTBOX_KEY_PREFIX}${eventId}`,
            sk: `${OUTBOX_KEY_PREFIX}${eventId}`,
            eventId,
            eventType: `order.${newStatus}`,
            payload: JSON.stringify({
              orderId,
              customerId: order.customerId,
              previousStatus: currentStatus,
              status: newStatus,
            }),
            createdAt: now.toISOString(),
            publishedAt: null,
            ttl: Math.floor(now.getTime() / 1000) + 7 * 86400,
          },
        },
      },
    ];

    try {
      await transactWriteItems(transactItems);
    } catch (error) {
      if ((error as { name?: string }).name === 'TransactionCanceledException') {
        throw new ConflictError('Order status was modified concurrently, retry the request', {
          orderId,
          expectedStatus: currentStatus,
        });
      }
      throw error;
    }

    // Record status change in history for audit trail (best-effort)
    await putItem(ORDERS_TABLE, {
      pk: `${HISTORY_KEY_PREFIX}${orderId}`,
      sk: `${HISTORY_KEY_PREFIX}${now.toISOString()}`,
      orderId,
      previousStatus: currentStatus,
      newStatus,
      changedAt: now.toISOString(),
      ttl: Math.floor(now.getTime() / 1000) + 90 * 86400,
    }).catch((err) => {
      logger.warn({ err, orderId }, 'Failed to record status history');
    });

    // Invalidate cache so next read fetches fresh state
    await cacheDelete(`${CACHE_PREFIX}${orderId}`);

    logger.info({ orderId, previousStatus: currentStatus, newStatus }, 'Order status updated');

    // Best-effort publish via circuit breaker. Outbox handles delivery if this fails.
    try {
      const messageId = await snsBreaker.fire(
        `order.${newStatus}`,
        orderId,
        order.customerId,
        { previousStatus: currentStatus, status: newStatus },
        undefined
      ) as string;

      if (messageId !== 'fallback-outbox') {
        await updateItem(
          ORDERS_TABLE,
          { pk: `${OUTBOX_KEY_PREFIX}${eventId}`, sk: `${OUTBOX_KEY_PREFIX}${eventId}` },
          { publishedAt: now.toISOString() }
        );
      }
    } catch (error) {
      logger.warn(
        { error, orderId, eventId },
        `Failed to publish order.${newStatus} event, outbox will retry`
      );
    }

    return { ...order, status: newStatus, updatedAt: now };
  }

  async cancelOrder(orderId: string): Promise<Order> {
    const result = await this.updateOrderStatus(orderId, 'cancelled');
    BusinessMetrics.orderCancelled(orderId, 'customer_request');
    return result;
  }
}

export const orderService = new OrderService();
