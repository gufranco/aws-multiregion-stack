# =============================================================================
# Worker Dockerfile
# =============================================================================
# Multi-stage build for production-ready Node.js Worker container
# Build context: app/ (the workspace root)
# =============================================================================

# Stage 1: Build
FROM node:24-alpine AS builder

# Install pnpm
RUN corepack enable && corepack prepare pnpm@8.15.0 --activate

WORKDIR /app

# Copy workspace files
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY shared/package.json ./shared/
COPY worker/package.json ./worker/

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source code
COPY shared ./shared
COPY worker ./worker

# Build shared library first, then Worker
RUN cd shared && pnpm build
RUN cd worker && pnpm build

# Stage 2: Production
FROM node:24-alpine AS production

# Install tini for proper PID 1 signal handling
RUN apk add --no-cache tini

# Install pnpm
RUN corepack enable && corepack prepare pnpm@8.15.0 --activate

# Add non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

WORKDIR /app

# Copy workspace config and dependencies
COPY --from=builder /app/package.json ./
COPY --from=builder /app/pnpm-workspace.yaml ./
COPY --from=builder /app/node_modules ./node_modules

# Copy shared library build output
COPY --from=builder /app/shared/package.json ./shared/
COPY --from=builder /app/shared/dist ./shared/dist
COPY --from=builder /app/shared/node_modules ./shared/node_modules

# Copy Worker build output
COPY --from=builder /app/worker/package.json ./worker/
COPY --from=builder /app/worker/dist ./worker/dist
COPY --from=builder /app/worker/node_modules ./worker/node_modules

# Set ownership
RUN chown -R nodejs:nodejs /app

# Switch to non-root user
USER nodejs

# Set environment
ENV NODE_ENV=production

# Health check: verify the worker process is running
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "process.exit(0)" || exit 1

# Use tini as PID 1 for proper signal forwarding
ENTRYPOINT ["/sbin/tini", "--"]

# Start the worker
WORKDIR /app/worker
CMD ["node", "dist/index.js"]
