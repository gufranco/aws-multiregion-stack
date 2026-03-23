// =============================================================================
// DynamoDB Client
// =============================================================================

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
  QueryCommand,
  ScanCommand,
  TransactWriteCommand,
  type GetCommandInput,
  type PutCommandInput,
  type UpdateCommandInput,
  type DeleteCommandInput,
  type QueryCommandInput,
  type ScanCommandInput,
} from '@aws-sdk/lib-dynamodb';
import { config, getAwsEndpoint } from '../config/index.js';
import { createLogger } from '../logger.js';

const logger = createLogger('dynamodb');

// Create DynamoDB client with explicit retry and timeout config
const endpoint = getAwsEndpoint();
const DYNAMODB_MAX_ATTEMPTS = 3;

const dynamoClient = new DynamoDBClient({
  region: config.AWS_REGION,
  maxAttempts: DYNAMODB_MAX_ATTEMPTS,
  ...(endpoint && { endpoint }),
  ...(config.USE_LOCALSTACK && {
    credentials: {
      accessKeyId: 'test',
      secretAccessKey: 'test',
    },
  }),
});

const REQUEST_TIMEOUT_MS = 5000;

// Document client with marshalling
export const dynamoDb = DynamoDBDocumentClient.from(dynamoClient, {
  marshallOptions: {
    convertEmptyValues: true,
    removeUndefinedValues: true,
  },
  unmarshallOptions: {
    wrapNumbers: false,
  },
});

// Get item by key
export async function getItem<T>(
  tableName: string,
  key: Record<string, unknown>,
): Promise<T | null> {
  const input: GetCommandInput = {
    TableName: tableName,
    Key: key,
  };

  const command = new GetCommand(input);
  const response = await dynamoDb.send(command, {
    abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  return (response.Item as T) ?? null;
}

// Put item
export async function putItem<T extends Record<string, unknown>>(
  tableName: string,
  item: T,
  options?: {
    conditionExpression?: string;
    expressionAttributeNames?: Record<string, string>;
    expressionAttributeValues?: Record<string, unknown>;
  },
): Promise<void> {
  const input: PutCommandInput = {
    TableName: tableName,
    Item: item,
    ConditionExpression: options?.conditionExpression,
    ExpressionAttributeNames: options?.expressionAttributeNames,
    ExpressionAttributeValues: options?.expressionAttributeValues,
  };

  const command = new PutCommand(input);
  await dynamoDb.send(command, {
    abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  logger.debug({ tableName, item }, 'DynamoDB item put');
}

// Update item
export async function updateItem<T>(
  tableName: string,
  key: Record<string, unknown>,
  updates: Record<string, unknown>,
  options?: {
    conditionExpression?: string;
    conditionAttributeNames?: Record<string, string>;
    conditionAttributeValues?: Record<string, unknown>;
    returnValues?: 'NONE' | 'ALL_OLD' | 'UPDATED_OLD' | 'ALL_NEW' | 'UPDATED_NEW';
  },
): Promise<T | null> {
  // Build update expression from the updates map
  const entries = Object.entries(updates);
  const updateExpressionParts = entries.map((_, i) => `#f${i} = :v${i}`);

  const baseNames = Object.fromEntries(entries.map(([field], i) => [`#f${i}`, field]));
  const baseValues = Object.fromEntries(entries.map(([, value], i) => [`:v${i}`, value]));

  // Merge condition expression attributes if provided
  const expressionAttributeNames: Record<string, string> = {
    ...baseNames,
    ...options?.conditionAttributeNames,
  };
  const expressionAttributeValues: Record<string, unknown> = {
    ...baseValues,
    ...options?.conditionAttributeValues,
  };

  const input: UpdateCommandInput = {
    TableName: tableName,
    Key: key,
    UpdateExpression: `SET ${updateExpressionParts.join(', ')}`,
    ExpressionAttributeNames: expressionAttributeNames,
    ExpressionAttributeValues: expressionAttributeValues,
    ConditionExpression: options?.conditionExpression,
    ReturnValues: options?.returnValues ?? 'ALL_NEW',
  };

  const command = new UpdateCommand(input);
  const response = await dynamoDb.send(command, {
    abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  return (response.Attributes as T) ?? null;
}

// Delete item
export async function deleteItem(
  tableName: string,
  key: Record<string, unknown>,
  options?: {
    conditionExpression?: string;
  },
): Promise<void> {
  const input: DeleteCommandInput = {
    TableName: tableName,
    Key: key,
    ConditionExpression: options?.conditionExpression,
  };

  const command = new DeleteCommand(input);
  await dynamoDb.send(command, {
    abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  logger.debug({ tableName, key }, 'DynamoDB item deleted');
}

// Query items
export async function queryItems<T>(
  tableName: string,
  keyConditionExpression: string,
  expressionAttributeValues: Record<string, unknown>,
  options?: {
    indexName?: string;
    filterExpression?: string;
    expressionAttributeNames?: Record<string, string>;
    limit?: number;
    scanIndexForward?: boolean;
    exclusiveStartKey?: Record<string, unknown>;
  },
): Promise<{ items: T[]; lastKey?: Record<string, unknown> }> {
  const input: QueryCommandInput = {
    TableName: tableName,
    KeyConditionExpression: keyConditionExpression,
    ExpressionAttributeValues: expressionAttributeValues,
    IndexName: options?.indexName,
    FilterExpression: options?.filterExpression,
    ExpressionAttributeNames: options?.expressionAttributeNames,
    Limit: options?.limit,
    ScanIndexForward: options?.scanIndexForward,
    ExclusiveStartKey: options?.exclusiveStartKey,
  };

  const command = new QueryCommand(input);
  const response = await dynamoDb.send(command, {
    abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  const result: { items: T[]; lastKey?: Record<string, unknown> } = {
    items: (response.Items as T[]) ?? [],
  };
  if (response.LastEvaluatedKey) {
    result.lastKey = response.LastEvaluatedKey;
  }
  return result;
}

// Transact write items (atomic multi-item writes)
export interface TransactWriteItem {
  put?: {
    tableName: string;
    item: Record<string, unknown>;
    conditionExpression?: string;
    expressionAttributeNames?: Record<string, string>;
    expressionAttributeValues?: Record<string, unknown>;
  };
  update?: {
    tableName: string;
    key: Record<string, unknown>;
    updateExpression: string;
    conditionExpression?: string;
    expressionAttributeNames?: Record<string, string>;
    expressionAttributeValues?: Record<string, unknown>;
  };
  delete?: {
    tableName: string;
    key: Record<string, unknown>;
    conditionExpression?: string;
  };
}

export async function transactWriteItems(items: TransactWriteItem[]): Promise<void> {
  const transactItems = items.map((item) => {
    if (item.put) {
      return {
        Put: {
          TableName: item.put.tableName,
          Item: item.put.item,
          ConditionExpression: item.put.conditionExpression,
          ExpressionAttributeNames: item.put.expressionAttributeNames,
          ExpressionAttributeValues: item.put.expressionAttributeValues,
        },
      };
    }
    if (item.update) {
      return {
        Update: {
          TableName: item.update.tableName,
          Key: item.update.key,
          UpdateExpression: item.update.updateExpression,
          ConditionExpression: item.update.conditionExpression,
          ExpressionAttributeNames: item.update.expressionAttributeNames,
          ExpressionAttributeValues: item.update.expressionAttributeValues,
        },
      };
    }
    if (item.delete) {
      return {
        Delete: {
          TableName: item.delete.tableName,
          Key: item.delete.key,
          ConditionExpression: item.delete.conditionExpression,
        },
      };
    }
    throw new Error('TransactWriteItem must have put, update, or delete');
  });

  const command = new TransactWriteCommand({ TransactItems: transactItems });
  await dynamoDb.send(command, {
    abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  logger.debug({ itemCount: items.length }, 'DynamoDB transaction committed');
}

// Scan items (use sparingly)
export async function scanItems<T>(
  tableName: string,
  options?: {
    filterExpression?: string;
    expressionAttributeNames?: Record<string, string>;
    expressionAttributeValues?: Record<string, unknown>;
    limit?: number;
    exclusiveStartKey?: Record<string, unknown>;
  },
): Promise<{ items: T[]; lastKey?: Record<string, unknown> }> {
  const input: ScanCommandInput = {
    TableName: tableName,
    FilterExpression: options?.filterExpression,
    ExpressionAttributeNames: options?.expressionAttributeNames,
    ExpressionAttributeValues: options?.expressionAttributeValues,
    Limit: options?.limit,
    ExclusiveStartKey: options?.exclusiveStartKey,
  };

  const command = new ScanCommand(input);
  const response = await dynamoDb.send(command, {
    abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  const result: { items: T[]; lastKey?: Record<string, unknown> } = {
    items: (response.Items as T[]) ?? [],
  };
  if (response.LastEvaluatedKey) {
    result.lastKey = response.LastEvaluatedKey;
  }
  return result;
}
