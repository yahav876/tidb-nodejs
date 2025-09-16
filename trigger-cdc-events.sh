#!/bin/bash

# CDC Event Trigger Script
# This script generates INSERT, UPDATE, and DELETE operations to test CDC flow
# Usage: ./trigger-cdc-events.sh [count] [delay]
# count: number of operations to perform (default: 5)
# delay: delay between operations in seconds (default: 2)

set -e

# Configuration
COUNT=${1:-5}
DELAY=${2:-2}
TIDB_HOST="tidb"
TIDB_PORT="4000"
TIDB_USER="root"
TIDB_PASSWORD=""
TIDB_DATABASE="testdb"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 CDC Event Trigger Script${NC}"
echo -e "${BLUE}=================================${NC}"
echo -e "Operations: ${GREEN}$COUNT${NC}"
echo -e "Delay: ${GREEN}$DELAY seconds${NC}"
echo -e "Target: ${GREEN}$TIDB_HOST:$TIDB_PORT/$TIDB_DATABASE${NC}"
echo ""

# Function to execute SQL command
execute_sql() {
    local sql="$1"
    local description="$2"

    echo -e "${YELLOW}📝 $description${NC}"
    echo -e "${BLUE}SQL:${NC} $sql"

    docker run --rm --network tidb-nodejs_tidb-network mysql:8.0 \
        mysql -h "$TIDB_HOST" -P "$TIDB_PORT" -u "$TIDB_USER" \
        -e "USE $TIDB_DATABASE; $sql"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Success${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
        return 1
    fi
    echo ""
}

# Function to show current metrics
show_metrics() {
    echo -e "${BLUE}📊 Current CDC Metrics:${NC}"
    curl -s http://localhost:3001/metrics | grep tidb_cdc_events_total | while read line; do
        echo -e "${GREEN}  $line${NC}"
    done
    echo ""
}

# Function to show recent CDC events from logs
show_recent_events() {
    echo -e "${BLUE}📋 Recent CDC Events (last 3):${NC}"
    tail -3 logs/consumer/combined.log | grep "CDC Event" | while read line; do
        echo -e "${GREEN}  $(echo $line | jq -r '.timestamp // .@timestamp') - $(echo $line | jq -r '.operation_type') on $(echo $line | jq -r '.table_name')${NC}"
    done 2>/dev/null || echo -e "${YELLOW}  No recent events found${NC}"
    echo ""
}

# Clean up existing test users first
echo -e "${BLUE}🧹 Cleaning up existing test users...${NC}"
docker run --rm --network tidb-nodejs_tidb-network mysql:8.0 \
    mysql -h "$TIDB_HOST" -P "$TIDB_PORT" -u "$TIDB_USER" \
    -e "USE $TIDB_DATABASE; DELETE FROM users WHERE username LIKE 'test_user_%' OR username LIKE 'bulk_%';" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Cleanup complete${NC}"
else
    echo -e "${YELLOW}⚠️  No existing test users to clean or cleanup skipped${NC}"
fi
echo ""

# Show initial state
echo -e "${BLUE}🔍 Initial State:${NC}"
show_metrics
show_recent_events

# Generate test data
echo -e "${BLUE}🎯 Generating CDC Events...${NC}"
echo ""

for i in $(seq 1 $COUNT); do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${BLUE}--- Operation Set $i ---${NC}"

    # INSERT operation
    execute_sql "INSERT INTO users (username, email, password_hash, created_at, updated_at) VALUES ('test_user_$i', 'test_$i@cdc.com', 'hash_$i', '$timestamp', '$timestamp');" \
        "INSERT: Creating test user $i"

    sleep $DELAY

    # UPDATE operation - get the last inserted ID
    last_id=$(docker run --rm --network tidb-nodejs_tidb-network mysql:8.0 \
        mysql -h "$TIDB_HOST" -P "$TIDB_PORT" -u "$TIDB_USER" \
        -se "USE $TIDB_DATABASE; SELECT id FROM users WHERE username='test_user_$i' LIMIT 1;")

    if [ ! -z "$last_id" ]; then
        # For UPDATE, use NOW() to ensure updated_at is different from created_at
        execute_sql "UPDATE users SET email = 'updated_test_$i@cdc.com', updated_at = NOW() WHERE id = $last_id;" \
            "UPDATE: Modifying test user $i (ID: $last_id)"

        sleep $DELAY

        # DELETE operation (for some users, to demonstrate DELETE events)
        if [ $((i % 2)) -eq 0 ]; then
            execute_sql "DELETE FROM users WHERE id = $last_id;" \
                "DELETE: Removing test user $i (ID: $last_id)"
        else
            echo -e "${YELLOW}⏭️  SKIP: Keeping test user $i for variety${NC}"
        fi
    else
        echo -e "${RED}⚠️  Could not find inserted user $i for UPDATE/DELETE${NC}"
    fi

    echo ""
    sleep $DELAY
done

# Show final state
echo -e "${BLUE}🏁 Final State:${NC}"
show_metrics
show_recent_events

# Additional operations for variety
echo -e "${BLUE}🎲 Bonus Operations for Dashboard Variety:${NC}"

# Multiple inserts
execute_sql "INSERT INTO users (username, email, password_hash, created_at, updated_at) VALUES
    ('bulk_1', 'bulk1@cdc.com', 'hash_bulk1', NOW(), NOW()),
    ('bulk_2', 'bulk2@cdc.com', 'hash_bulk2', NOW(), NOW()),
    ('bulk_3', 'bulk3@cdc.com', 'hash_bulk3', NOW(), NOW());" \
    "BULK INSERT: Adding 3 users at once"

sleep $DELAY

# Update multiple records
execute_sql "UPDATE users SET email = CONCAT('mass_update_', id, '@cdc.com'), updated_at = NOW() WHERE username LIKE 'bulk_%';" \
    "BULK UPDATE: Updating all bulk users"

sleep $DELAY

# Conditional delete
execute_sql "DELETE FROM users WHERE username LIKE 'bulk_%' AND id % 2 = 1;" \
    "CONDITIONAL DELETE: Removing odd-numbered bulk users"

echo -e "${GREEN}🎉 CDC Event Generation Complete!${NC}"
echo -e "${BLUE}👀 Check your Grafana dashboard at: ${GREEN}http://localhost:3000/d/tidb-cdc-events${NC}"
echo ""
echo -e "${BLUE}📊 You can also check:${NC}"
echo -e "${GREEN}  • Prometheus: http://localhost:9090${NC}"
echo -e "${GREEN}  • Consumer metrics: http://localhost:3001/metrics${NC}"
echo -e "${GREEN}  • Elasticsearch: http://localhost:9200/tidb-cdc-logs-*/_search${NC}"
echo ""

# Final metrics
echo -e "${BLUE}📈 Final CDC Metrics:${NC}"
show_metrics