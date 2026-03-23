// =============================================================================
// Unit Tests - Order Status State Machine
// =============================================================================

import { describe, it, expect } from 'vitest';
import { OrderStatus, ORDER_STATUS_TRANSITIONS, isValidStatusTransition } from '@blueprint/shared';

type OrderStatusValue = (typeof OrderStatus)[keyof typeof OrderStatus];

describe('Order Status State Machine', () => {
  describe('valid transitions', () => {
    const validCases: [string, string][] = [
      ['pending', 'confirmed'],
      ['pending', 'cancelled'],
      ['confirmed', 'processing'],
      ['confirmed', 'cancelled'],
      ['processing', 'shipped'],
      ['processing', 'cancelled'],
      ['shipped', 'delivered'],
    ];

    it.each(validCases)('should allow %s -> %s', (from, to) => {
      expect(isValidStatusTransition(from as OrderStatusValue, to as OrderStatusValue)).toBe(true);
    });
  });

  describe('invalid transitions', () => {
    const invalidCases: [string, string][] = [
      ['pending', 'shipped'],
      ['pending', 'delivered'],
      ['confirmed', 'delivered'],
      ['confirmed', 'shipped'],
      ['processing', 'pending'],
      ['processing', 'confirmed'],
      ['shipped', 'cancelled'],
      ['shipped', 'pending'],
      ['delivered', 'cancelled'],
      ['delivered', 'pending'],
      ['cancelled', 'pending'],
      ['cancelled', 'confirmed'],
    ];

    it.each(invalidCases)('should reject %s -> %s', (from, to) => {
      expect(isValidStatusTransition(from as OrderStatusValue, to as OrderStatusValue)).toBe(false);
    });
  });

  describe('terminal states', () => {
    it('should have no transitions from delivered', () => {
      expect(ORDER_STATUS_TRANSITIONS['delivered']).toEqual([]);
    });

    it('should have no transitions from cancelled', () => {
      expect(ORDER_STATUS_TRANSITIONS['cancelled']).toEqual([]);
    });
  });

  describe('OrderStatus enum', () => {
    it('should have all expected statuses', () => {
      expect(OrderStatus.PENDING).toBe('pending');
      expect(OrderStatus.CONFIRMED).toBe('confirmed');
      expect(OrderStatus.PROCESSING).toBe('processing');
      expect(OrderStatus.SHIPPED).toBe('shipped');
      expect(OrderStatus.DELIVERED).toBe('delivered');
      expect(OrderStatus.CANCELLED).toBe('cancelled');
    });

    it('should cover all states in the transition map', () => {
      // Arrange
      const enumValues = Object.values(OrderStatus);
      const transitionKeys = Object.keys(ORDER_STATUS_TRANSITIONS);

      // Assert
      expect(transitionKeys.toSorted()).toEqual(enumValues.toSorted());
    });
  });
});
