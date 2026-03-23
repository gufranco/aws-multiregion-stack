// =============================================================================
// Unit Tests - Input Validation Schemas
// =============================================================================

import { describe, it, expect } from 'vitest';
import { faker } from '@faker-js/faker';
import {
  createOrderSchema,
  paginationSchema,
  orderEventSchema,
  notificationEventSchema,
} from '@blueprint/shared';

faker.seed(54321);

function buildValidOrderInput() {
  return {
    customerId: faker.string.uuid(),
    items: [
      {
        productId: faker.string.uuid(),
        productName: faker.commerce.productName(),
        quantity: faker.number.int({ min: 1, max: 100 }),
        unitPrice: faker.number.float({ min: 0.01, max: 1000, fractionDigits: 2 }),
        totalPrice: faker.number.float({ min: 0.01, max: 10000, fractionDigits: 2 }),
      },
    ],
    shippingAddress: {
      street: faker.location.streetAddress(),
      city: faker.location.city(),
      state: faker.location.state({ abbreviated: true }),
      country: faker.location.countryCode('alpha-2'),
      postalCode: faker.location.zipCode(),
    },
  };
}

describe('createOrderSchema', () => {
  it('should accept valid order input', () => {
    // Arrange
    const input = buildValidOrderInput();

    // Act
    const result = createOrderSchema.safeParse(input);

    // Assert
    expect(result.success).toBe(true);
  });

  it('should reject non-UUID customerId', () => {
    // Arrange
    const input = { ...buildValidOrderInput(), customerId: faker.string.alpha(10) };

    // Act
    const result = createOrderSchema.safeParse(input);

    // Assert
    expect(result.success).toBe(false);
  });

  it('should reject empty items array', () => {
    // Arrange
    const input = { ...buildValidOrderInput(), items: [] };

    // Act
    const result = createOrderSchema.safeParse(input);

    // Assert
    expect(result.success).toBe(false);
  });

  it('should reject negative quantity', () => {
    // Arrange
    const base = buildValidOrderInput();
    const input = {
      ...base,
      items: [{ ...base.items[0]!, quantity: -1 }],
    };

    // Act
    const result = createOrderSchema.safeParse(input);

    // Assert
    expect(result.success).toBe(false);
  });

  it('should reject missing shipping address fields', () => {
    // Arrange
    const input = {
      ...buildValidOrderInput(),
      shippingAddress: { street: faker.location.streetAddress() },
    };

    // Act
    const result = createOrderSchema.safeParse(input);

    // Assert
    expect(result.success).toBe(false);
  });

  it('should reject country code longer than 2 chars', () => {
    // Arrange
    const base = buildValidOrderInput();
    const input = {
      ...base,
      shippingAddress: {
        ...base.shippingAddress,
        country: faker.location.countryCode('alpha-3'),
      },
    };

    // Act
    const result = createOrderSchema.safeParse(input);

    // Assert
    expect(result.success).toBe(false);
  });

  it('should accept optional metadata', () => {
    // Arrange
    const input = {
      ...buildValidOrderInput(),
      metadata: {
        source: faker.internet.domainWord(),
        campaign: faker.commerce.department(),
      },
    };

    // Act
    const result = createOrderSchema.safeParse(input);

    // Assert
    expect(result.success).toBe(true);
  });

  it('should reject metadata with more than 50 keys', () => {
    // Arrange
    const bigMetadata: Record<string, string> = {};
    for (let i = 0; i < 51; i++) {
      bigMetadata[`key${i}`] = faker.string.alpha(5);
    }
    const input = { ...buildValidOrderInput(), metadata: bigMetadata };

    // Act
    const result = createOrderSchema.safeParse(input);

    // Assert
    expect(result.success).toBe(false);
  });
});

describe('paginationSchema', () => {
  it('should provide defaults', () => {
    // Arrange & Act
    const result = paginationSchema.parse({});

    // Assert
    expect(result.page).toBe(1);
    expect(result.limit).toBe(20);
    expect(result.sortOrder).toBe('desc');
  });

  it('should coerce string numbers', () => {
    // Arrange
    const page = faker.number.int({ min: 1, max: 50 });
    const limit = faker.number.int({ min: 1, max: 100 });

    // Act
    const result = paginationSchema.parse({ page: String(page), limit: String(limit) });

    // Assert
    expect(result.page).toBe(page);
    expect(result.limit).toBe(limit);
  });

  it('should reject limit over 100', () => {
    // Arrange
    const limit = faker.number.int({ min: 101, max: 999 });

    // Act
    const result = paginationSchema.safeParse({ limit });

    // Assert
    expect(result.success).toBe(false);
  });

  it('should reject page zero', () => {
    // Arrange & Act
    const result = paginationSchema.safeParse({ page: 0 });

    // Assert
    expect(result.success).toBe(false);
  });
});

describe('orderEventSchema', () => {
  it('should accept valid order event', () => {
    // Arrange
    const event = {
      id: faker.string.uuid(),
      type: 'order.created',
      timestamp: faker.date.recent().toISOString(),
      source: faker.internet.domainWord(),
      region: 'us-east-1',
      data: {
        orderId: faker.string.uuid(),
        customerId: faker.string.uuid(),
      },
    };

    // Act
    const result = orderEventSchema.safeParse(event);

    // Assert
    expect(result.success).toBe(true);
  });

  it('should reject unknown event type', () => {
    // Arrange
    const event = {
      id: faker.string.uuid(),
      type: 'order.unknown',
      timestamp: faker.date.recent().toISOString(),
      source: faker.internet.domainWord(),
      region: 'us-east-1',
      data: {
        orderId: faker.string.uuid(),
        customerId: faker.string.uuid(),
      },
    };

    // Act
    const result = orderEventSchema.safeParse(event);

    // Assert
    expect(result.success).toBe(false);
  });
});

describe('notificationEventSchema', () => {
  it('should accept valid email notification', () => {
    // Arrange
    const event = {
      id: faker.string.uuid(),
      type: 'notification.email',
      timestamp: faker.date.recent().toISOString(),
      source: faker.internet.domainWord(),
      region: 'us-east-1',
      data: {
        recipientId: faker.string.uuid(),
        recipientEmail: faker.internet.email(),
        body: faker.lorem.paragraph(),
        subject: faker.lorem.sentence(),
      },
    };

    // Act
    const result = notificationEventSchema.safeParse(event);

    // Assert
    expect(result.success).toBe(true);
  });

  it('should reject invalid email format', () => {
    // Arrange
    const event = {
      id: faker.string.uuid(),
      type: 'notification.email',
      timestamp: faker.date.recent().toISOString(),
      source: faker.internet.domainWord(),
      region: 'us-east-1',
      data: {
        recipientId: faker.string.uuid(),
        recipientEmail: faker.string.alpha(10),
        body: faker.lorem.paragraph(),
      },
    };

    // Act
    const result = notificationEventSchema.safeParse(event);

    // Assert
    expect(result.success).toBe(false);
  });
});
