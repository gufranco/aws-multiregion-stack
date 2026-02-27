// =============================================================================
// Authentication Middleware
// =============================================================================

import { timingSafeEqual } from 'node:crypto';
import type { FastifyRequest, FastifyReply } from 'fastify';
import { config, UnauthorizedError } from '@blueprint/shared';

const SKIP_AUTH_PREFIXES = ['/health', '/docs'];

function constantTimeCompare(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  return timingSafeEqual(Buffer.from(a), Buffer.from(b));
}

export async function authMiddleware(
  request: FastifyRequest,
  _reply: FastifyReply
): Promise<void> {
  const shouldSkip = SKIP_AUTH_PREFIXES.some((prefix) => request.url.startsWith(prefix));
  if (shouldSkip) {
    return;
  }

  // When no API_KEY is configured, auth is disabled (local dev)
  if (!config.API_KEY) {
    return;
  }

  const rawKey = request.headers['x-api-key'];
  const apiKey =
    (Array.isArray(rawKey) ? rawKey[0] : rawKey) ??
    request.headers['authorization']?.replace('Bearer ', '');

  if (!apiKey || typeof apiKey !== 'string' || !constantTimeCompare(apiKey, config.API_KEY)) {
    throw new UnauthorizedError('Invalid or missing API key');
  }
}
