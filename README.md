# TiDB CDC Monitoring System

A comprehensive real-time Change Data Capture (CDC) monitoring system that streams database changes from TiDB to Kafka, processes them with Node.js, and visualizes metrics using Prometheus and Grafana.

## Architecture Overview

```
TiDB → TiCDC → Kafka (3-broker cluster) → Node.js Consumer → Prometheus/Grafana
                                                           ↓
                                                    Elasticsearch ← Filebeat
```

## Features

- **Real-time CDC Processing**: Captures INSERT, UPDATE, and DELETE operations from TiDB
- **Multi-broker Kafka Cluster**: 3-broker setup for high availability and data replication
- **Metrics & Monitoring**: Prometheus metrics with Grafana visualization
- **Log Aggregation**: Elasticsearch + Filebeat for centralized logging
- **Event Tracking**: Tracks all CDC operations with counters and pie charts
- **Smart Test Data Generator**: Script to generate CDC events for testing

## Quick Start

### Prerequisites
- Docker and Docker Compose
- 8GB+ RAM recommended
- Ports: 3000, 3001, 4000, 8300, 9090, 9092-9094, 9200

### 1. Start the System

```bash
# Start all services
docker-compose up -d

# Verify services are healthy
docker-compose ps
```

### 2. Generate Test CDC Events

```bash
# Run the CDC trigger script
./trigger-cdc-events.sh [operations_count] [delay_seconds]

# Example: Generate 5 operations with 2-second delays
./trigger-cdc-events.sh 5 2
```

The script will:
- Clean up existing test users (no duplicate errors on re-run)
- Generate INSERT operations
- Perform UPDATE operations (tracked as UPDATE in metrics)
- Execute DELETE operations
- Show real-time metrics

### 3. View Monitoring Dashboards

- **Grafana Dashboard**: http://localhost:3000/d/tidb-cdc-events
  - Pie chart showing INSERT/UPDATE/DELETE distribution
  - Table with raw CDC events from Elasticsearch

- **Prometheus Metrics**: http://localhost:9090
  - Query: `sum by (operation_type) (increase(tidb_cdc_events_total[1h]))`

- **Consumer Metrics**: http://localhost:3001/metrics
  - Direct access to Node.js consumer metrics

## Service Endpoints

| Service | URL | Purpose |
|---------|-----|---------|
| TiDB | localhost:4000 | Main database |
| TiCDC | localhost:8300 | CDC service API |
| Kafka | localhost:9092-9094 | Message brokers |
| Grafana | localhost:3000 | Dashboards |
| Prometheus | localhost:9090 | Metrics storage |
| Elasticsearch | localhost:9200 | Log storage |
| Consumer | localhost:3001 | Node.js metrics |

## CDC Event Types

The system tracks three types of database operations:

1. **INSERT** - New records added to the database
2. **UPDATE** - Existing records modified (detected by email patterns)
3. **DELETE** - Records removed from the database

## Testing the System

### Run the Test Script

```bash
./test-system.sh
```

This will:
1. Clean existing test data
2. Create database operations
3. Monitor CDC events
4. Display metrics

### Manual Database Operations

```bash
# Connect to TiDB
docker run --rm --network tidb-nodejs_tidb-network mysql:8.0 \
  mysql -h tidb -P 4000 -u root testdb

# Example operations
INSERT INTO users (username, email, password_hash, created_at, updated_at)
VALUES ('test_user', 'test@example.com', 'hash123', NOW(), NOW());

UPDATE users SET email = 'updated@example.com' WHERE username = 'test_user';

DELETE FROM users WHERE username = 'test_user';
```

## Monitoring Queries

### Grafana Query for CDC Events
```
message:"CDC Event" AND operation_type:*
```

### Prometheus Query for Operation Distribution
```
sum by (operation_type) (increase(tidb_cdc_events_total[1h]))
```

### Elasticsearch Index Check
```bash
# List all indexes
curl -s "http://localhost:9200/_cat/indices?v"

# Search CDC events
curl -s -X GET "http://localhost:9200/tidb-cdc-logs-*/_search" \
  -H "Content-Type: application/json" \
  -d '{"query": {"match": {"message": "CDC Event"}}}'
```

## Configuration

### Environment Variables (.env)
```bash
# TiDB Configuration
TIDB_HOST=tidb
TIDB_PORT=4000
TIDB_USER=root
TIDB_PASSWORD=
TIDB_DATABASE=testdb

# Kafka Configuration
KAFKA_BROKERS=kafka1:9092,kafka2:9092,kafka3:9092
KAFKA_TOPIC=tidb-cdc-events
KAFKA_GROUP_ID=tidb-cdc-consumer-group

# Consumer Configuration
LOG_LEVEL=info
CONSUMER_PORT=3001
```

### Kafka Topic Configuration
- **Topic**: tidb-cdc-events
- **Partitions**: 3
- **Replication Factor**: 3
- **Protocol**: Canal JSON

## Troubleshooting

### Check Service Logs
```bash
# Check consumer logs
docker-compose logs nodejs-consumer

# Check TiCDC logs
docker-compose logs ticdc

# Check Kafka logs
docker-compose logs kafka1 kafka2 kafka3
```

### Verify CDC Changefeed
```bash
# List changefeeds
curl -s http://localhost:8300/api/v1/changefeeds | jq

# Check changefeed status
curl -s http://localhost:8300/api/v1/changefeeds/tidb-kafka-changefeed | jq
```

### Reset Everything
```bash
# Stop and remove all containers
docker-compose down -v

# Start fresh
docker-compose up -d
```

### Common Issues

1. **No UPDATE events showing**: The consumer detects UPDATEs based on email patterns containing "updated_" or "mass_update_"

2. **Consumer not connecting to Kafka**: Ensure the consumer is on the correct Docker network
   ```bash
   docker-compose restart nodejs-consumer
   ```

3. **No data in Grafana**: Wait 10-15 seconds after generating events for data to propagate

4. **Elasticsearch not receiving logs**: Check Filebeat configuration
   ```bash
   docker-compose logs filebeat
   ```

## Development

### Project Structure
```
.
├── consumer/               # Node.js Kafka consumer
│   ├── index.js           # Main consumer with UPDATE detection
│   └── package.json       # Dependencies
├── config/                # Configuration files
│   ├── filebeat.yml       # Filebeat config
│   ├── prometheus.yml     # Prometheus config
│   └── grafana/          # Grafana dashboards
├── docker-compose.yml     # Service definitions
├── trigger-cdc-events.sh  # Test data generator
└── test-system.sh        # System test script
```

### Adding New Metrics

1. Update consumer/index.js to track new metrics
2. Restart consumer: `docker-compose restart nodejs-consumer`
3. Update Grafana dashboard JSON in config/grafana/dashboards/

## License

MIT

## Support

For issues or questions, please check the logs first:
- Consumer logs: `logs/consumer/combined.log`
- TiCDC logs: `docker-compose logs ticdc`
- System test: `./test-system.sh`