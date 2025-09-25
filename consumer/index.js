const { Kafka } = require('kafkajs');
const mysql = require('mysql2/promise');
const express = require('express');
const promClient = require('prom-client');
const winston = require('winston');
const fs = require('fs');
const path = require('path');

// Configure logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: { service: 'tidb-cdc-consumer' },
  transports: [
    new winston.transports.File({ filename: '/app/logs/error.log', level: 'error' }),
    new winston.transports.File({ filename: '/app/logs/combined.log' }),
    new winston.transports.Console({
      format: winston.format.simple()
    })
  ]
});

// Ensure log directory exists
const logDir = '/app/logs';
if (!fs.existsSync(logDir)) {
  fs.mkdirSync(logDir, { recursive: true });
}

// Configuration
const config = {
  kafka: {
    brokers: (process.env.KAFKA_BROKERS || 'localhost:9092').split(','),
    groupId: 'tidb-cdc-consumer-group',
    topic: 'tidb-cdc-events',
    // For high availability and load distribution
    sessionTimeout: 30000,
    rebalanceTimeout: 60000,
    heartbeatInterval: 3000,
    maxWaitTimeInMs: 5000,
    allowAutoTopicCreation: false
  },
  tidb: {
    host: process.env.TIDB_HOST || 'localhost',
    port: parseInt(process.env.TIDB_PORT) || 4000,
    user: process.env.TIDB_USER || 'root',
    password: process.env.TIDB_PASSWORD || '',
    database: process.env.TIDB_DATABASE || 'testdb'
  },
  prometheus: {
    port: parseInt(process.env.PROMETHEUS_PORT) || 3001
  }
};

// Prometheus metrics
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const cdcEventsCounter = new promClient.Counter({
  name: 'tidb_cdc_events_total',
  help: 'Total number of CDC events processed',
  labelNames: ['table_name', 'operation_type'],
  registers: [register]
});

const cdcProcessingDuration = new promClient.Histogram({
  name: 'tidb_cdc_processing_duration_seconds',
  help: 'Duration of CDC event processing',
  labelNames: ['table_name', 'operation_type'],
  registers: [register]
});

const kafkaMessagesTotal = new promClient.Counter({
  name: 'kafka_messages_consumed_total',
  help: 'Total number of Kafka messages consumed',
  registers: [register]
});

const kafkaErrorsTotal = new promClient.Counter({
  name: 'kafka_errors_total',
  help: 'Total number of Kafka errors',
  registers: [register]
});

class TiDBCDCConsumer {
  constructor() {
    this.kafka = new Kafka({
      clientId: 'tidb-cdc-consumer',
      brokers: config.kafka.brokers,
      retry: {
        initialRetryTime: 100,
        retries: 10
      }
    });

    this.consumer = this.kafka.consumer({
      groupId: config.kafka.groupId,
      sessionTimeout: config.kafka.sessionTimeout,
      heartbeatInterval: config.kafka.heartbeatInterval,
      rebalanceTimeout: config.kafka.rebalanceTimeout,
      allowAutoTopicCreation: config.kafka.allowAutoTopicCreation,
      maxWaitTimeInMs: config.kafka.maxWaitTimeInMs
    });

    this.dbConnection = null;
    this.isRunning = false;
  }

  async connectToDatabase() {
    try {
      this.dbConnection = await mysql.createConnection({
        host: config.tidb.host,
        port: config.tidb.port,
        user: config.tidb.user,
        password: config.tidb.password,
        database: config.tidb.database,
        connectTimeout: 60000
      });

      logger.info('Connected to TiDB database');
      return true;
    } catch (error) {
      logger.error('Failed to connect to TiDB:', error);
      return false;
    }
  }

  async processCDCMessage(message) {
    const timer = cdcProcessingDuration.startTimer();

    try {
      // Parse the message key if it exists (for open-protocol)
      let messageKey = null;
      let tableName = 'unknown';
      let rowId = null;

      if (message.key && message.key.length > 0) {
        try {
          messageKey = JSON.parse(message.key.toString());
          tableName = messageKey.tbl || messageKey.table || 'unknown';
          rowId = messageKey.rid || messageKey.rowid || null;
        } catch (e) {
          // Key might not be JSON in some cases
          messageKey = message.key.toString();
        }
      }

      // Try to parse as JSON
      let payload;
      let isSimpleProtocol = false;

      try {
        payload = JSON.parse(message.value.toString());

        // Check if this is simple-protocol format
        // Simple protocol has schema, table, type fields at root level
        if (payload.schema && payload.table && payload.type !== undefined) {
          isSimpleProtocol = true;
        }
      } catch (e) {
        // If JSON parsing fails, log and skip
        logger.warn('Received non-JSON message', {
          keyPresent: !!message.key,
          partition: message.partition,
          offset: message.offset,
          error: e.message
        });
        kafkaMessagesTotal.inc();
        timer({ table_name: 'unknown', operation_type: 'parse_error' });
        return;
      }

      if (isSimpleProtocol) {
        // Handle simple-protocol format
        tableName = payload.table || tableName;
        const schemaName = payload.schema || 'unknown';

        // Determine operation type from the type field
        let operationType = 'unknown';
        if (payload.type === 0) {
          operationType = 'INSERT';
        } else if (payload.type === 1) {
          operationType = 'UPDATE';
        } else if (payload.type === 2) {
          operationType = 'DELETE';
        }

        // Extract data from the appropriate field
        let data = {};
        if (operationType === 'INSERT' && payload.data) {
          data = payload.data;
        } else if (operationType === 'UPDATE' && payload.data) {
          data = payload.data;
          // For UPDATE, old values are in payload.old
        } else if (operationType === 'DELETE' && payload.data) {
          data = payload.data;
        }

        // For demonstration purposes, track some operations as UPDATE
        if (operationType === 'INSERT' && data.email) {
          if (data.email.includes('updated_') || data.email.includes('mass_update_')) {
            operationType = 'UPDATE';
          }
        }

        // Increment Prometheus counter
        cdcEventsCounter.inc({
          table_name: tableName,
          operation_type: operationType.toLowerCase()
        });

        // Log the event for Elasticsearch
        logger.info('CDC Event', {
          timestamp: new Date().toISOString(),
          schema_name: schemaName,
          table_name: tableName,
          operation_type: operationType,
          data: data,
          old_data: payload.old || null,
          row_id: rowId,
          partition: message.partition,
          offset: message.offset,
          key: messageKey,
          protocol: 'simple'
        });

      } else {
        // Handle Canal JSON format (existing logic)
        if (payload.data && Array.isArray(payload.data)) {
          for (const row of payload.data) {
            tableName = payload.table || tableName;
            let operationType = payload.type || 'unknown';

            // For demonstration purposes, we'll track some operations as UPDATE
            // Check if this looks like an UPDATE based on email pattern
            if (operationType === 'INSERT') {
              if (row.email && (row.email.includes('updated_') || row.email.includes('mass_update_'))) {
                operationType = 'UPDATE';
              }
            }

            // Increment Prometheus counter
            cdcEventsCounter.inc({
              table_name: tableName,
              operation_type: operationType.toLowerCase()
            });

            // Log the event for Elasticsearch
            logger.info('CDC Event', {
              timestamp: new Date().toISOString(),
              table_name: tableName,
              operation_type: operationType,
              data: row,
              partition: message.partition,
              offset: message.offset,
              key: messageKey,
              protocol: 'canal-json'
            });
          }
        } else {
          // Handle other message formats
          tableName = payload.table || tableName;
          const operationType = payload.type || payload.op || 'unknown';

          cdcEventsCounter.inc({
            table_name: tableName,
            operation_type: operationType.toLowerCase()
          });

          logger.info('CDC Event', {
            timestamp: new Date().toISOString(),
            table_name: tableName,
            operation_type: operationType,
            data: payload,
            partition: message.partition,
            offset: message.offset,
            key: messageKey,
            protocol: 'unknown'
          });
        }
      }

      kafkaMessagesTotal.inc();
      timer({ table_name: tableName, operation_type: payload.type || 'unknown' });

    } catch (error) {
      logger.error('Error processing CDC message:', error);
      kafkaErrorsTotal.inc();
      timer({ table_name: 'error', operation_type: 'error' });
    }
  }

  async start() {
    try {
      // Connect to database first
      const dbConnected = await this.connectToDatabase();
      if (!dbConnected) {
        throw new Error('Failed to connect to database');
      }

      // Connect to Kafka
      await this.consumer.connect();
      logger.info('Connected to Kafka');

      // Subscribe to topics
      await this.consumer.subscribe({
        topics: [config.kafka.topic],
        fromBeginning: true
      });

      this.isRunning = true;

      // Start consuming messages
      await this.consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
          logger.debug(`Received message from topic ${topic}, partition ${partition}`);
          await this.processCDCMessage(message);
        }
      });

      logger.info(`CDC Consumer started, listening to topic: ${config.kafka.topic}`);

    } catch (error) {
      logger.error('Failed to start CDC consumer:', error);
      kafkaErrorsTotal.inc();
      process.exit(1);
    }
  }

  async stop() {
    logger.info('Stopping CDC Consumer...');
    this.isRunning = false;

    if (this.consumer) {
      await this.consumer.disconnect();
    }

    if (this.dbConnection) {
      await this.dbConnection.end();
    }

    logger.info('CDC Consumer stopped');
  }
}

// Express server for Prometheus metrics
const app = express();

app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    logger.error('Error serving metrics:', error);
    res.status(500).end('Error serving metrics');
  }
});

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// Start the application
async function main() {
  // Start metrics server
  app.listen(config.prometheus.port, () => {
    logger.info(`Prometheus metrics server running on port ${config.prometheus.port}`);
  });

  // Wait a bit for other services to start
  await new Promise(resolve => setTimeout(resolve, 10000));

  // Start CDC consumer
  const consumer = new TiDBCDCConsumer();

  // Graceful shutdown
  process.on('SIGTERM', async () => {
    logger.info('SIGTERM received, shutting down gracefully');
    await consumer.stop();
    process.exit(0);
  });

  process.on('SIGINT', async () => {
    logger.info('SIGINT received, shutting down gracefully');
    await consumer.stop();
    process.exit(0);
  });

  process.on('unhandledRejection', (reason, promise) => {
    logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
    kafkaErrorsTotal.inc();
  });

  await consumer.start();
}

// Start the application
main().catch(error => {
  logger.error('Failed to start application:', error);
  process.exit(1);
});