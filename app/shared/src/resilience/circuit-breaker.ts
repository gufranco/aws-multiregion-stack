// =============================================================================
// Circuit Breaker Pattern
// =============================================================================

import CircuitBreaker from 'opossum';
import { createLogger } from '../logger.js';

const logger = createLogger('circuit-breaker');

export interface CircuitBreakerOptions {
  readonly timeout?: number;
  readonly errorThresholdPercentage?: number;
  readonly resetTimeout?: number;
  readonly volumeThreshold?: number;
  readonly name?: string;
}

const defaultOptions: CircuitBreakerOptions = {
  timeout: 10000, // 10 seconds
  errorThresholdPercentage: 50, // Open circuit if 50% of requests fail
  resetTimeout: 30000, // Try again after 30 seconds
  volumeThreshold: 5, // Minimum requests before calculating error percentage
};

export function createCircuitBreaker(
  fn: (...args: unknown[]) => Promise<unknown>,
  options: CircuitBreakerOptions = {},
): CircuitBreaker {
  const opts = { ...defaultOptions, ...options };
  const name = opts.name ?? fn.name ?? 'unnamed';

  const breaker = new CircuitBreaker(fn, {
    timeout: opts.timeout,
    errorThresholdPercentage: opts.errorThresholdPercentage,
    resetTimeout: opts.resetTimeout,
    volumeThreshold: opts.volumeThreshold,
    name,
  });

  // Event handlers
  breaker.on('success', () => {
    logger.debug({ circuit: name }, 'Circuit breaker: success');
  });

  breaker.on('timeout', () => {
    logger.warn({ circuit: name }, 'Circuit breaker: timeout');
  });

  breaker.on('reject', () => {
    logger.warn({ circuit: name }, 'Circuit breaker: rejected (circuit open)');
  });

  breaker.on('open', () => {
    logger.error({ circuit: name }, 'Circuit breaker: OPENED');
  });

  breaker.on('halfOpen', () => {
    logger.info({ circuit: name }, 'Circuit breaker: half-open (testing)');
  });

  breaker.on('close', () => {
    logger.info({ circuit: name }, 'Circuit breaker: CLOSED (recovered)');
  });

  breaker.on('fallback', () => {
    logger.debug({ circuit: name }, 'Circuit breaker: fallback executed');
  });

  return breaker;
}

// Pre-configured circuit breakers for common services
export const circuitBreakers = {
  database: (fn: () => Promise<unknown>) =>
    createCircuitBreaker(fn, {
      name: 'database',
      timeout: 5000,
      errorThresholdPercentage: 50,
      resetTimeout: 10000,
    }),

  redis: (fn: () => Promise<unknown>) =>
    createCircuitBreaker(fn, {
      name: 'redis',
      timeout: 2000,
      errorThresholdPercentage: 50,
      resetTimeout: 5000,
    }),

  externalApi: (fn: () => Promise<unknown>, apiName: string) =>
    createCircuitBreaker(fn, {
      name: `external-api-${apiName}`,
      timeout: 30000,
      errorThresholdPercentage: 30,
      resetTimeout: 60000,
    }),

  sqs: (fn: () => Promise<unknown>) =>
    createCircuitBreaker(fn, {
      name: 'sqs',
      timeout: 5000,
      errorThresholdPercentage: 50,
      resetTimeout: 10000,
    }),

  sns: (fn: () => Promise<unknown>) =>
    createCircuitBreaker(fn, {
      name: 'sns',
      timeout: 5000,
      errorThresholdPercentage: 50,
      resetTimeout: 10000,
    }),
};

// Health check for circuit breakers
export function getCircuitBreakerStats(breaker: CircuitBreaker): {
  name: string;
  state: string;
  stats: {
    successes: number;
    failures: number;
    timeouts: number;
    rejects: number;
    fallbacks: number;
  };
} {
  const stats = breaker.stats;
  return {
    name: breaker.name ?? 'unnamed',
    state: breaker.opened ? 'OPEN' : breaker.halfOpen ? 'HALF-OPEN' : 'CLOSED',
    stats: {
      successes: stats.successes,
      failures: stats.failures,
      timeouts: stats.timeouts,
      rejects: stats.rejects,
      fallbacks: stats.fallbacks,
    },
  };
}
