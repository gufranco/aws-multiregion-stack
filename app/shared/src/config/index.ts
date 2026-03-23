// =============================================================================
// Configuration
// =============================================================================

import { z } from 'zod';

// Environment validation schema
const envSchema = z.object({
  // Application
  NODE_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().default(3000),
  PROJECT_NAME: z.string().min(1).default('blueprint'),

  // Region
  AWS_REGION: z.string().min(1).default('us-east-1'),
  REGION_KEY: z.string().min(1).default('us_east_1'),
  IS_PRIMARY_REGION: z.coerce.boolean().default(true),
  REGION_TIER: z.enum(['primary', 'secondary', 'tertiary']).default('primary'),

  // Database
  DATABASE_HOST: z.string().min(1).default('localhost'),
  DATABASE_READ_HOST: z.string().min(1).optional(),
  DATABASE_PORT: z.coerce.number().default(5432),
  DATABASE_NAME: z.string().min(1).default('app'),
  DATABASE_USER: z.string().min(1).default('postgres'),
  DATABASE_PASSWORD: z.string().min(1).default('postgres'),
  DATABASE_URL: z.string().optional(),

  // Redis
  REDIS_HOST: z.string().min(1).default('localhost'),
  REDIS_PORT: z.coerce.number().default(6379),
  REDIS_PASSWORD: z.string().optional(),

  // AWS Services
  SQS_ORDER_QUEUE_URL: z.string().optional(),
  SQS_NOTIFICATION_QUEUE_URL: z.string().optional(),
  SQS_DLQ_URL: z.string().optional(),
  SNS_ORDER_TOPIC_ARN: z.string().optional(),
  SNS_NOTIFICATION_TOPIC_ARN: z.string().optional(),

  // LocalStack (must not be enabled in production)
  LOCALSTACK_ENDPOINT: z.string().optional(),
  USE_LOCALSTACK: z.coerce.boolean().default(false),

  // DynamoDB tables
  DYNAMODB_ORDERS_TABLE: z.string().optional(),

  // Authentication (must be non-empty when set)
  API_KEY: z.string().min(1).optional(),

  // CORS
  CORS_ALLOWED_ORIGINS: z.string().optional(),

  // Tracing
  OTEL_EXPORTER_OTLP_ENDPOINT: z.string().optional(),
  OTEL_SERVICE_NAME: z.string().default('blueprint-app'),
});

export type Env = z.infer<typeof envSchema>;

// Parse and validate environment
function loadConfig(): Env {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    // eslint-disable-next-line no-console -- logger depends on config, so console is the only option here
    console.error('Invalid environment variables:');
    for (const issue of result.error.issues) {
      // eslint-disable-next-line no-console
      console.error(`  ${issue.path.join('.')}: ${issue.message}`);
    }
    throw new Error('Invalid environment configuration');
  }

  const data = result.data;

  if (data.NODE_ENV === 'production' && data.USE_LOCALSTACK) {
    throw new Error('USE_LOCALSTACK must not be enabled in production');
  }

  if (data.NODE_ENV === 'production' && !data.API_KEY) {
    throw new Error('API_KEY must be configured in production');
  }

  return data;
}

export const config = loadConfig();

// Derived configuration
export const isProduction = config.NODE_ENV === 'production';
export const isDevelopment = config.NODE_ENV === 'development';
export const isPrimaryRegion = config.IS_PRIMARY_REGION;

// Database URL builder
export function getDatabaseUrl(): string {
  if (config.DATABASE_URL) {
    return config.DATABASE_URL;
  }

  const base = `postgresql://${config.DATABASE_USER}:${config.DATABASE_PASSWORD}@${config.DATABASE_HOST}:${config.DATABASE_PORT}/${config.DATABASE_NAME}`;
  return config.USE_LOCALSTACK ? base : `${base}?sslmode=require`;
}

// Read replica URL (for secondary regions)
export function getReadDatabaseUrl(): string {
  const host = config.DATABASE_READ_HOST ?? config.DATABASE_HOST;
  const base = `postgresql://${config.DATABASE_USER}:${config.DATABASE_PASSWORD}@${host}:${config.DATABASE_PORT}/${config.DATABASE_NAME}`;
  return config.USE_LOCALSTACK ? base : `${base}?sslmode=require`;
}

// AWS endpoint configuration (for LocalStack)
export function getAwsEndpoint(): string | undefined {
  if (config.USE_LOCALSTACK && config.LOCALSTACK_ENDPOINT) {
    return config.LOCALSTACK_ENDPOINT;
  }
  return undefined;
}
