// =============================================================================
// Worker Manager
// =============================================================================

import {
  config,
  createLogger,
  receiveMessages,
  deleteMessage,
  putItem,
  isTransient,
  BusinessMetrics,
  type Message,
} from '@blueprint/shared';
import { processOrderMessage } from './handlers/orders.js';
import { processNotificationMessage } from './handlers/notifications.js';
import { processDlqMessage } from './handlers/dlq.js';
import { sweepOutboxEvents } from './handlers/outbox.js';

const logger = createLogger('worker-manager');

const ORDERS_TABLE =
  config.DYNAMODB_ORDERS_TABLE ?? `${config.PROJECT_NAME}-${config.NODE_ENV}-orders`;

const DEDUP_KEY_PREFIX = 'DEDUP#';
const DEDUP_TTL_SECONDS = 86400; // 24h

// Cap concurrent message processing across all queues to avoid
// resource exhaustion under burst load.
const MAX_CONCURRENT_MESSAGES = 20;

class Semaphore {
  private current = 0;
  private waiting: Array<() => void> = [];

  constructor(private readonly max: number) {}

  async acquire(): Promise<void> {
    if (this.current < this.max) {
      this.current++;
      return;
    }
    return new Promise<void>((resolve) => {
      this.waiting.push(resolve);
    });
  }

  release(): void {
    const next = this.waiting.shift();
    if (next) {
      next();
    } else if (this.current > 0) {
      this.current--;
    }
  }
}

interface QueueConfig {
  readonly name: string;
  readonly url: string | undefined;
  readonly handler: (message: Message) => Promise<void>;
  readonly enabled: boolean;
}

export class WorkerManager {
  private isRunning = false;
  private queues: QueueConfig[];
  private readonly semaphore = new Semaphore(MAX_CONCURRENT_MESSAGES);

  constructor() {
    this.queues = [
      {
        name: 'order-processing',
        url: config.SQS_ORDER_QUEUE_URL,
        handler: processOrderMessage,
        enabled: !!config.SQS_ORDER_QUEUE_URL,
      },
      {
        name: 'notification',
        url: config.SQS_NOTIFICATION_QUEUE_URL,
        handler: processNotificationMessage,
        enabled: !!config.SQS_NOTIFICATION_QUEUE_URL,
      },
      {
        name: 'dlq',
        url: config.SQS_DLQ_URL,
        handler: processDlqMessage,
        enabled: !!config.SQS_DLQ_URL,
      },
    ];
  }

  async start(): Promise<void> {
    this.isRunning = true;

    const enabledQueues = this.queues.filter((q) => q.enabled);

    if (enabledQueues.length === 0) {
      logger.warn('No queues configured, worker will idle');
      return;
    }

    logger.info({ queues: enabledQueues.map((q) => q.name) }, 'Starting queue polling');

    for (const queue of enabledQueues) {
      void this.pollQueue(queue);
    }

    void this.startOutboxSweeper();
  }

  async stop(): Promise<void> {
    this.isRunning = false;
    logger.info('Worker stopping...');
  }

  private async pollQueue(queue: QueueConfig): Promise<void> {
    while (this.isRunning) {
      try {
        await this.processQueueBatch(queue);
      } catch (error) {
        if (isTransient(error)) {
          logger.warn({ error, queue: queue.name }, 'Transient error polling queue, backing off');
        } else {
          logger.error({ error, queue: queue.name }, 'Permanent error polling queue');
        }
        await this.sleep(5000);
      }
    }
  }

  private async processQueueBatch(queue: QueueConfig): Promise<void> {
    if (!queue.url) return;

    const messages = await receiveMessages(queue.url, {
      maxMessages: 10,
      waitTimeSeconds: 20,
      visibilityTimeout: 60,
    });

    if (messages.length === 0) {
      return;
    }

    logger.debug({ queue: queue.name, count: messages.length }, 'Received messages');

    const results = await Promise.allSettled(
      messages.map(async (message) => {
        await this.semaphore.acquire();
        try {
          return await this.processMessage(queue, message);
        } finally {
          this.semaphore.release();
        }
      }),
    );

    const succeeded = results.filter((r) => r.status === 'fulfilled').length;
    const failed = results.filter((r) => r.status === 'rejected').length;

    // Report batch-level metrics
    if (succeeded > 0) {
      void BusinessMetrics.messagesProcessed(queue.name, succeeded);
    }
    if (failed > 0) {
      void BusinessMetrics.messagesFailed(queue.name, failed);
      logger.warn({ queue: queue.name, succeeded, failed }, 'Some messages failed processing');
    }
  }

  private async processMessage(queue: QueueConfig, message: Message): Promise<void> {
    const messageId = message.MessageId;
    const startTime = Date.now();

    try {
      // Claim this message atomically before processing. The condition expression
      // prevents a concurrent worker from processing the same message.
      if (messageId) {
        try {
          await putItem(
            ORDERS_TABLE,
            {
              pk: `${DEDUP_KEY_PREFIX}${messageId}`,
              sk: `${DEDUP_KEY_PREFIX}${messageId}`,
              startedAt: new Date().toISOString(),
              queue: queue.name,
              ttl: Math.floor(Date.now() / 1000) + DEDUP_TTL_SECONDS,
            },
            {
              conditionExpression: 'attribute_not_exists(pk)',
            },
          );
        } catch (err) {
          if ((err as { name?: string }).name === 'ConditionalCheckFailedException') {
            logger.info({ messageId, queue: queue.name }, 'Duplicate message, skipping');
            if (message.ReceiptHandle && queue.url) {
              await deleteMessage(queue.url, message.ReceiptHandle);
            }
            return;
          }
          throw err;
        }
      }

      await queue.handler(message);

      // Delete from queue on success
      if (message.ReceiptHandle && queue.url) {
        await deleteMessage(queue.url, message.ReceiptHandle);
      }

      const duration = Date.now() - startTime;
      logger.info({ messageId, queue: queue.name, duration }, 'Message processed successfully');
    } catch (error) {
      const duration = Date.now() - startTime;

      if (isTransient(error)) {
        logger.warn(
          { error, messageId, queue: queue.name, duration },
          'Transient failure processing message, will retry via SQS',
        );
      } else {
        logger.error(
          { error, messageId, queue: queue.name, duration },
          'Permanent failure processing message',
        );
      }

      // Don't delete: SQS will redeliver after visibility timeout.
      // After maxReceiveCount retries, the message goes to DLQ.
      throw error;
    }
  }

  private async startOutboxSweeper(): Promise<void> {
    const SWEEP_INTERVAL_MS = 30_000;

    while (this.isRunning) {
      try {
        const published = await sweepOutboxEvents();
        if (published > 0) {
          logger.info({ published }, 'Outbox sweep completed');
        }
      } catch (error) {
        if (isTransient(error)) {
          logger.warn({ error }, 'Transient error during outbox sweep, will retry');
        } else {
          logger.error({ error }, 'Permanent error during outbox sweep');
        }
      }
      await this.sleep(SWEEP_INTERVAL_MS);
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
