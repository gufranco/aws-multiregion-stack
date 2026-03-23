// =============================================================================
// Notification Message Handler
// =============================================================================

import {
  createLogger,
  CURRENT_SCHEMA_VERSION,
  type Message,
  type NotificationEvent,
  notificationEventSchema,
} from '@blueprint/shared';

const logger = createLogger('notification-handler');

function maskEmail(email?: string): string {
  if (!email) return '[none]';
  const [local, domain] = email.split('@');
  if (!local || !domain) return '***';
  return `${local[0]}***@${domain}`;
}

function maskPhone(phone?: string): string {
  if (!phone) return '[none]';
  return `***${phone.slice(-4)}`;
}

export async function processNotificationMessage(message: Message): Promise<void> {
  if (!message.Body) {
    logger.warn({ messageId: message.MessageId }, 'Empty message body');
    return;
  }

  // Parse SNS wrapper if present
  let eventData: unknown;
  try {
    const body: unknown = JSON.parse(message.Body);
    const snsWrapper = body as { Message?: string } | undefined;
    if (snsWrapper?.Message) {
      eventData = JSON.parse(snsWrapper.Message);
    } else {
      eventData = body;
    }
  } catch (error) {
    // Parse failures are permanent: retrying won't fix malformed JSON
    logger.error({ error, body: message.Body }, 'Failed to parse notification message body');
    throw error;
  }

  // Validate event
  const parseResult = notificationEventSchema.safeParse(eventData);
  if (!parseResult.success) {
    logger.error(
      { errors: parseResult.error.issues, event: eventData },
      'Invalid notification event',
    );
    throw new Error('Invalid notification event format');
  }

  const event = parseResult.data;

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
      recipientId: event.data.recipientId,
    },
    'Processing notification event',
  );

  // Handle different notification types
  switch (event.type) {
    case 'notification.email':
      await sendEmailNotification(event);
      break;

    case 'notification.push':
      await sendPushNotification(event);
      break;

    case 'notification.sms':
      await sendSmsNotification(event);
      break;

    default:
      logger.warn({ eventType: event.type }, 'Unknown notification type');
  }
}

// Send email notification
async function sendEmailNotification(event: NotificationEvent): Promise<void> {
  const {
    recipientId,
    recipientEmail,
    subject,
    body: _body,
    templateId,
    templateData: _templateData,
  } = event.data;

  logger.info(
    { recipientId, email: maskEmail(recipientEmail), subject, templateId },
    'Sending email notification',
  );

  // In a real app, you'd integrate with SES, SendGrid, etc.
  // For now, we just log

  // Example SES integration:
  // const sesClient = new SESClient({ region: config.AWS_REGION });
  // await sesClient.send(new SendEmailCommand({
  //   Source: 'noreply@example.com',
  //   Destination: { ToAddresses: [recipientEmail] },
  //   Message: {
  //     Subject: { Data: subject },
  //     Body: { Text: { Data: body } },
  //   },
  // }));

  logger.info(
    { recipientId, email: maskEmail(recipientEmail) },
    'Email notification sent (simulated)',
  );
}

// Send push notification
async function sendPushNotification(event: NotificationEvent): Promise<void> {
  const { recipientId, body: _body, templateId, templateData: _templateData } = event.data;

  logger.info({ recipientId, templateId }, 'Sending push notification');

  // In a real app, you'd integrate with SNS for mobile push or FCM
  // For now, we just log

  logger.info({ recipientId }, 'Push notification sent (simulated)');
}

// Send SMS notification
async function sendSmsNotification(event: NotificationEvent): Promise<void> {
  const { recipientId, recipientPhone, body: _body } = event.data;

  logger.info({ recipientId, phone: maskPhone(recipientPhone) }, 'Sending SMS notification');

  // In a real app, you'd integrate with SNS SMS, Twilio, etc.
  // For now, we just log

  // Example SNS SMS:
  // const snsClient = new SNSClient({ region: config.AWS_REGION });
  // await snsClient.send(new PublishCommand({
  //   PhoneNumber: recipientPhone,
  //   Message: body,
  // }));

  logger.info(
    { recipientId, phone: maskPhone(recipientPhone) },
    'SMS notification sent (simulated)',
  );
}
