// =============================================================================
// Order Message Handler
// =============================================================================

import {
  createLogger,
  isTransient,
  TransientError,
  CURRENT_SCHEMA_VERSION,
  type Message,
  type OrderEvent,
  orderEventSchema,
  publishNotification,
} from '@blueprint/shared';

const logger = createLogger('order-handler');

export async function processOrderMessage(message: Message): Promise<void> {
  if (!message.Body) {
    logger.warn({ messageId: message.MessageId }, 'Empty message body');
    return;
  }

  // Parse SNS wrapper if present
  let eventData: unknown;
  try {
    const body: unknown = JSON.parse(message.Body);
    const snsWrapper = body as { Message?: string } | undefined;
    // SNS wraps the message
    if (snsWrapper?.Message) {
      eventData = JSON.parse(snsWrapper.Message);
    } else {
      eventData = body;
    }
  } catch (error) {
    logger.error({ error, body: message.Body }, 'Failed to parse message body');
    // Parse failures are permanent: retrying won't fix malformed JSON
    throw error;
  }

  // Validate event
  const parseResult = orderEventSchema.safeParse(eventData);
  if (!parseResult.success) {
    logger.error({ errors: parseResult.error.issues, event: eventData }, 'Invalid order event');
    throw new Error('Invalid order event format');
  }

  const event = parseResult.data;

  // Reject events from incompatible future schema versions
  const majorVersion = (event.schemaVersion ?? '1.0').split('.')[0];
  if (majorVersion !== CURRENT_SCHEMA_VERSION.split('.')[0]) {
    logger.error(
      { schemaVersion: event.schemaVersion, expected: CURRENT_SCHEMA_VERSION },
      'Incompatible event schema version, skipping',
    );
    return;
  }

  logger.info(
    {
      eventId: event.id,
      eventType: event.type,
      orderId: event.data.orderId,
      customerId: event.data.customerId,
    },
    'Processing order event',
  );

  // Handle different event types
  switch (event.type) {
    case 'order.created':
      await handleOrderCreated(event);
      break;

    case 'order.confirmed':
      await handleOrderConfirmed(event);
      break;

    case 'order.processing':
      await handleOrderProcessing(event);
      break;

    case 'order.shipped':
      await handleOrderShipped(event);
      break;

    case 'order.delivered':
      await handleOrderDelivered(event);
      break;

    case 'order.cancelled':
      await handleOrderCancelled(event);
      break;

    default:
      logger.warn({ eventType: event.type }, 'Unknown event type');
  }
}

// Handle order.created event
async function handleOrderCreated(event: OrderEvent): Promise<void> {
  const { orderId, customerId } = event.data;

  logger.info({ orderId, customerId }, 'Processing order.created');

  try {
    await publishNotification(
      'notification.email',
      customerId,
      `Your order ${orderId} has been received and is being processed.`,
      {
        subject: 'Order Confirmation',
        templateId: 'order-confirmation',
        templateData: { orderId },
      },
    );
  } catch (error) {
    if (isTransient(error)) {
      logger.warn({ error, orderId }, 'Transient failure sending order confirmation, will retry');
      throw new TransientError('Failed to send order confirmation notification');
    }
    // Permanent notification failures are non-critical, log and continue
    logger.error({ error, orderId }, 'Permanent failure sending order confirmation notification');
  }
}

// Handle order.confirmed event
async function handleOrderConfirmed(event: OrderEvent): Promise<void> {
  const { orderId, customerId } = event.data;

  logger.info({ orderId, customerId }, 'Processing order.confirmed');

  // Example: Update inventory, start fulfillment process, etc.
  // In a real app, you'd integrate with inventory and fulfillment systems
}

// Handle order.processing event
async function handleOrderProcessing(event: OrderEvent): Promise<void> {
  const { orderId, customerId } = event.data;

  logger.info({ orderId, customerId }, 'Processing order.processing');

  try {
    await publishNotification(
      'notification.email',
      customerId,
      `Your order ${orderId} is now being prepared for shipment.`,
      {
        subject: 'Order Update - Processing',
        templateId: 'order-processing',
        templateData: { orderId },
      },
    );
  } catch (error) {
    if (isTransient(error)) {
      logger.warn({ error, orderId }, 'Transient failure sending processing notification');
      throw new TransientError('Failed to send processing notification');
    }
    logger.error({ error, orderId }, 'Permanent failure sending processing notification');
  }
}

// Handle order.shipped event
async function handleOrderShipped(event: OrderEvent): Promise<void> {
  const { orderId, customerId } = event.data;

  logger.info({ orderId, customerId }, 'Processing order.shipped');

  try {
    await publishNotification(
      'notification.email',
      customerId,
      `Your order ${orderId} has been shipped! You can track your package using the link below.`,
      {
        subject: 'Order Shipped',
        templateId: 'order-shipped',
        templateData: {
          orderId,
          trackingUrl: `https://example.com/track/${orderId}`,
        },
      },
    );
  } catch (error) {
    if (isTransient(error)) {
      logger.warn({ error, orderId }, 'Transient failure sending shipping notification');
      throw new TransientError('Failed to send shipping notification');
    }
    logger.error({ error, orderId }, 'Permanent failure sending shipping notification');
  }
}

// Handle order.delivered event
async function handleOrderDelivered(event: OrderEvent): Promise<void> {
  const { orderId, customerId } = event.data;

  logger.info({ orderId, customerId }, 'Processing order.delivered');

  try {
    await publishNotification(
      'notification.email',
      customerId,
      `Your order ${orderId} has been delivered! We hope you enjoy your purchase.`,
      {
        subject: 'Order Delivered',
        templateId: 'order-delivered',
        templateData: {
          orderId,
          feedbackUrl: `https://example.com/feedback/${orderId}`,
        },
      },
    );
  } catch (error) {
    if (isTransient(error)) {
      logger.warn({ error, orderId }, 'Transient failure sending delivery notification');
      throw new TransientError('Failed to send delivery notification');
    }
    logger.error({ error, orderId }, 'Permanent failure sending delivery notification');
  }
}

// Handle order.cancelled event
async function handleOrderCancelled(event: OrderEvent): Promise<void> {
  const { orderId, customerId } = event.data;

  logger.info({ orderId, customerId }, 'Processing order.cancelled');

  try {
    await publishNotification(
      'notification.email',
      customerId,
      `Your order ${orderId} has been cancelled. If you were charged, a refund will be processed within 5-7 business days.`,
      {
        subject: 'Order Cancelled',
        templateId: 'order-cancelled',
        templateData: { orderId },
      },
    );
  } catch (error) {
    if (isTransient(error)) {
      logger.warn({ error, orderId }, 'Transient failure sending cancellation notification');
      throw new TransientError('Failed to send cancellation notification');
    }
    logger.error({ error, orderId }, 'Permanent failure sending cancellation notification');
  }
}
