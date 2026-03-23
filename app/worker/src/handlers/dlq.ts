// =============================================================================
// Dead Letter Queue Handler
// =============================================================================

import { config, createLogger, publishMetric, putItem, type Message } from '@blueprint/shared';

const logger = createLogger('dlq-handler');

const ORDERS_TABLE =
  config.DYNAMODB_ORDERS_TABLE ?? `${config.PROJECT_NAME}-${config.NODE_ENV}-orders`;

const DLQ_KEY_PREFIX = 'DLQ#';
const DLQ_RETENTION_DAYS = 90;

export async function processDlqMessage(message: Message): Promise<void> {
  const receiveCount = message.Attributes?.ApproximateReceiveCount;

  logger.error(
    {
      messageId: message.MessageId,
      body: message.Body,
      attributes: message.Attributes,
      messageAttributes: message.MessageAttributes,
      receiveCount,
    },
    'DLQ message received: exhausted all retries',
  );

  // Publish alert metric so CloudWatch alarms fire
  await publishMetric({
    metricName: 'DLQMessagesReceived',
    value: 1,
    unit: 'Count',
  });

  // Extract event details for structured logging
  let eventType: string | undefined;
  let eventId: string | undefined;
  let correlationId: string | undefined;
  let orderId: string | undefined;

  try {
    const body: unknown = JSON.parse(message.Body ?? '{}');
    const snsWrapper = body as { Message?: string } | undefined;
    const eventData = snsWrapper?.Message
      ? (JSON.parse(snsWrapper.Message) as Record<string, unknown>)
      : (body as Record<string, unknown>);

    eventType = eventData['type'] as string | undefined;
    eventId = eventData['id'] as string | undefined;
    correlationId = eventData['correlationId'] as string | undefined;
    const data = eventData['data'] as Record<string, unknown> | undefined;
    orderId = data?.['orderId'] as string | undefined;

    logger.error({ eventType, eventId, correlationId, orderId }, 'DLQ message event details');
  } catch {
    logger.warn({ messageId: message.MessageId }, 'Could not parse DLQ message body');
  }

  // Persist for investigation and replay. If this fails, the message
  // stays in the DLQ for redelivery instead of being silently lost.
  const now = new Date();
  await putItem(ORDERS_TABLE, {
    pk: `${DLQ_KEY_PREFIX}${message.MessageId ?? now.toISOString()}`,
    sk: `${DLQ_KEY_PREFIX}${now.toISOString()}`,
    messageId: message.MessageId,
    body: message.Body,
    attributes: message.Attributes,
    messageAttributes: message.MessageAttributes,
    eventType,
    eventId,
    correlationId,
    orderId,
    receivedAt: now.toISOString(),
    replayedAt: null,
    ttl: Math.floor(now.getTime() / 1000) + DLQ_RETENTION_DAYS * 86400,
  });
}
