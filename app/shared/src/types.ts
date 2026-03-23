// =============================================================================
// Shared Types
// =============================================================================

import { z } from 'zod';

// =============================================================================
// Order Types
// =============================================================================

export const OrderStatus = {
  PENDING: 'pending',
  CONFIRMED: 'confirmed',
  PROCESSING: 'processing',
  SHIPPED: 'shipped',
  DELIVERED: 'delivered',
  CANCELLED: 'cancelled',
} as const;

export type OrderStatus = (typeof OrderStatus)[keyof typeof OrderStatus];

// Single source of truth for the order status state machine.
// Both the service layer and tests should reference this map.
export const ORDER_STATUS_TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  pending: ['confirmed', 'cancelled'],
  confirmed: ['processing', 'cancelled'],
  processing: ['shipped', 'cancelled'],
  shipped: ['delivered'],
  delivered: [],
  cancelled: [],
} as const;

export function isValidStatusTransition(from: OrderStatus, to: OrderStatus): boolean {
  return ORDER_STATUS_TRANSITIONS[from]?.includes(to) ?? false;
}

export const orderItemSchema = z.object({
  productId: z.string().uuid(),
  productName: z.string().min(1).max(500),
  quantity: z.number().int().positive().max(99999),
  unitPrice: z.number().positive().max(999999.99),
  totalPrice: z.number().positive().max(999999.99),
});

export type OrderItem = z.infer<typeof orderItemSchema>;

export const createOrderSchema = z.object({
  customerId: z.string().uuid(),
  items: z.array(orderItemSchema).min(1),
  shippingAddress: z.object({
    street: z.string().min(1).max(500),
    city: z.string().min(1).max(200),
    state: z.string().min(1).max(100),
    country: z.string().min(2).max(2),
    postalCode: z.string().min(1).max(20),
  }),
  metadata: z
    .record(z.string(), z.unknown())
    .refine((obj) => Object.keys(obj).length <= 50, 'metadata cannot have more than 50 keys')
    .optional(),
});

export type CreateOrderInput = z.infer<typeof createOrderSchema>;

export const orderSchema = createOrderSchema.extend({
  id: z.string().uuid(),
  status: z.nativeEnum(OrderStatus),
  totalAmount: z.number(),
  currency: z.string().default('USD'),
  createdAt: z.coerce.date(),
  updatedAt: z.coerce.date(),
});

export type Order = z.infer<typeof orderSchema>;

// =============================================================================
// Event Types
// =============================================================================

export const eventTypeSchema = z.enum([
  'order.created',
  'order.confirmed',
  'order.processing',
  'order.shipped',
  'order.delivered',
  'order.cancelled',
  'order.updated',
  'notification.email',
  'notification.push',
  'notification.sms',
]);

export type EventType = z.infer<typeof eventTypeSchema>;

export const CURRENT_SCHEMA_VERSION = '1.0';

export const baseEventSchema = z.object({
  id: z.string().uuid(),
  type: eventTypeSchema,
  schemaVersion: z.string().default(CURRENT_SCHEMA_VERSION),
  timestamp: z.coerce.date(),
  source: z.string(),
  region: z.string(),
  correlationId: z.string().uuid().optional(),
  metadata: z.record(z.string(), z.unknown()).optional(),
});

export const orderEventSchema = baseEventSchema.extend({
  type: z.enum([
    'order.created',
    'order.confirmed',
    'order.processing',
    'order.shipped',
    'order.delivered',
    'order.cancelled',
    'order.updated',
  ]),
  data: z.object({
    orderId: z.string().uuid(),
    customerId: z.string().uuid(),
    status: z.nativeEnum(OrderStatus).optional(),
    previousStatus: z.nativeEnum(OrderStatus).optional(),
  }),
});

export type OrderEvent = z.infer<typeof orderEventSchema>;

export const notificationEventSchema = baseEventSchema.extend({
  type: z.enum(['notification.email', 'notification.push', 'notification.sms']),
  data: z.object({
    recipientId: z.string().uuid(),
    recipientEmail: z.string().email().optional(),
    recipientPhone: z.string().optional(),
    subject: z.string().optional(),
    body: z.string(),
    templateId: z.string().optional(),
    templateData: z.record(z.string(), z.unknown()).optional(),
  }),
});

export type NotificationEvent = z.infer<typeof notificationEventSchema>;

// =============================================================================
// SQS Message Types
// =============================================================================

export interface SQSMessageBody<T> {
  readonly Message: string; // JSON stringified event
  readonly MessageId: string;
  readonly Type: 'Notification';
  readonly TopicArn?: string;
  readonly Timestamp: string;
  readonly data?: T; // Parsed event data
}

// =============================================================================
// Health Check Types
// =============================================================================

export interface HealthStatus {
  readonly status: 'healthy' | 'degraded' | 'unhealthy';
  readonly region: string;
  readonly regionKey: string;
  readonly isPrimary: boolean;
  readonly tier: string;
  readonly timestamp: string;
  readonly version: string;
  readonly uptime: number;
  readonly checks: {
    readonly database: 'ok' | 'error';
    readonly redis: 'ok' | 'error';
    readonly sqs: 'ok' | 'error';
    readonly sns: 'ok' | 'error';
  };
}

// =============================================================================
// Pagination Types
// =============================================================================

export const paginationSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(20),
  sortBy: z.string().optional(),
  sortOrder: z.enum(['asc', 'desc']).default('desc'),
});

export type PaginationInput = z.infer<typeof paginationSchema>;

export interface PaginatedResult<T> {
  readonly data: readonly T[];
  readonly pagination: {
    readonly page: number;
    readonly limit: number;
    readonly total: number;
    readonly totalPages: number;
    readonly hasNext: boolean;
    readonly hasPrev: boolean;
  };
}

// Cursor-based pagination (preferred for DynamoDB)
export const cursorPaginationSchema = z.object({
  cursor: z.string().max(2048).optional(),
  limit: z.coerce.number().int().positive().max(100).default(20),
});

export type CursorPaginationInput = z.infer<typeof cursorPaginationSchema>;

export interface CursorPaginatedResult<T> {
  readonly data: readonly T[];
  readonly pagination: {
    readonly nextCursor: string | null;
    readonly hasMore: boolean;
    readonly limit: number;
  };
}
