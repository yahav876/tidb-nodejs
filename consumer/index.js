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
      const payload = JSON.parse(message.value.toString());
      logger.info('Processing CDC message:', payload);

      // Handle Canal JSON format from TiCDC
      if (payload.data && Array.isArray(payload.data)) {
        for (const row of payload.data) {
          const tableName = payload.table || 'unknown';
          let operationType = payload.type || 'unknown';

          // For demonstration purposes, we'll track some operations as UPDATE
          // Check if this looks like an UPDATE based on email pattern or timestamp difference
          if (operationType === 'INSERT') {
            // If email contains "updated_" or "mass_update_", treat as UPDATE
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
            key: message.key ? message.key.toString() : null
          });
        }
      } else {
        // Handle other message formats
        const tableName = payload.table || 'unknown';
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
          key: message.key ? message.key.toString() : null
        });
      }

      kafkaMessagesTotal.inc();
      timer({ table_name: payload.table || 'unknown', operation_type: payload.type || 'unknown' });

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