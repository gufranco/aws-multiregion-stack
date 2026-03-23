// =============================================================================
// Outbox Sweeper
// =============================================================================
// Polls DynamoDB for outbox events that were not published to SNS (publishedAt
// is null). This covers the case where the best-effort publish in the API
// failed or the circuit breaker was open. Runs on a timer inside WorkerManager,
// not via SQS.
// =============================================================================

import {
  config,
  createLogger,
  scanItems,
  updateItem,
  publishOrderEvent,
  isTransient,
  type EventType,
} from '@blueprint/shared';

const logger = createLogger('outbox-sweeper');

const ORDERS_TABLE =
  config.DYNAMODB_ORDERS_TABLE ?? `${config.PROJECT_NAME}-${config.NODE_ENV}-orders`;

const OUTBOX_KEY_PREFIX = 'OUTBOX#';
const MAX_ITEMS_PER_SWEEP = 25;

interface OutboxRecord {
  readonly pk: string;
  readonly sk: string;
  readonly eventId: string;
  readonly eventType: string;
  readonly payload: string;
  readonly correlationId: string | null;
  readonly createdAt: string;
  readonly publishedAt: string | null;
}

export async function sweepOutboxEvents(): Promise<number> {
  const result = await scanItems<OutboxRecord>(ORDERS_TABLE, {
    filterExpression: 'begins_with(pk, :prefix) AND attribute_type(publishedAt, :nullType)',
    expressionAttributeValues: { ':prefix': OUTBOX_KEY_PREFIX, ':nullType': 'NULL' },
    limit: MAX_ITEMS_PER_SWEEP,
  });

  if (result.items.length === 0) {
    return 0;
  }

  logger.info({ count: result.items.length }, 'Found unpublished outbox events');

  let published = 0;

  for (const item of result.items) {
    try {
      const payload = JSON.parse(item.payload) as {
        orderId: string;
        customerId: string;
        [key: string]: unknown;
      };

      const { orderId, customerId, ...additionalData } = payload;

      await publishOrderEvent(
        item.eventType as EventType,
        orderId,
        customerId,
        Object.keys(additionalData).length > 0 ? additionalData : undefined,
        item.correlationId ?? undefined,
      );

      await updateItem(
        ORDERS_TABLE,
        { pk: item.pk, sk: item.sk },
        { publishedAt: new Date().toISOString() },
      );

      published++;
      logger.info({ eventId: item.eventId, eventType: item.eventType }, 'Outbox event published');
    } catch (error) {
      if (isTransient(error)) {
        logger.warn(
          { error, eventId: item.eventId },
          'Transient failure publishing outbox event, will retry next sweep',
        );
      } else {
        logger.error({ error, eventId: item.eventId }, 'Permanent failure publishing outbox event');
      }
    }
  }

  return published;
}
