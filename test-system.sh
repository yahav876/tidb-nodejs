#!/bin/bash

echo "🧪 TiDB CDC System Test Script"
echo "================================"

# Check if Docker Compose is running
echo "📋 Checking system status..."

# Function to check if a service is responsive
check_service() {
    local service_name=$1
    local url=$2
    local expected_code=${3:-200}

    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "$expected_code"; then
        echo "✅ $service_name is responsive"
        return 0
    else
        echo "❌ $service_name is not responding"
        return 1
    fi
}

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Check all services
services_ok=true

if check_service "TiDB" "http://localhost:4000" 200; then
    echo "✅ TiDB is running"
else
    # TiDB doesn't have a direct HTTP endpoint, try different approach
    if docker-compose ps tidb | grep -q "Up"; then
        echo "✅ TiDB container is running"
    else
        echo "❌ TiDB is not running"
        services_ok=false
    fi
fi

check_service "Prometheus" "http://localhost:9090" 200 || services_ok=false
check_service "Grafana" "http://localhost:3000/api/health" 200 || services_ok=false
check_service "Elasticsearch" "http://localhost:9200" 200 || services_ok=false
check_service "Consumer Metrics" "http://localhost:3001/metrics" 200 || services_ok=false
check_service "Consumer Health" "http://localhost:3001/health" 200 || services_ok=false

if [ "$services_ok" = true ]; then
    echo ""
    echo "🎉 All services are running successfully!"
    echo ""
    echo "🔗 Access URLs:"
    echo "   Grafana Dashboard: http://localhost:3000 (admin/admin)"
    echo "   Prometheus: http://localhost:9090"
    echo "   Consumer Metrics: http://localhost:3001/metrics"
    echo ""
    echo "📝 To generate test data, run:"
    echo "   docker-compose exec tidb mysql -u root -e \"USE testdb; INSERT INTO users (username, email, password_hash) VALUES ('test', 'test@example.com', 'hash');\""
    echo ""
else
    echo ""
    echo "❌ Some services are not running properly."
    echo "💡 Check logs with: docker-compose logs <service-name>"
    echo ""
fi

# Test data insertion
echo "🧪 Testing CDC with sample data..."
if docker-compose exec -T tidb mysql -u root -e "
USE testdb;
INSERT INTO categories (name, description) VALUES ('Test Category', 'Test Description');
INSERT INTO products (name, description, price, stock_quantity, category_id) VALUES ('Test Product', 'Test Description', 99.99, 10, LAST_INSERT_ID());
"; then
    echo "✅ Sample data inserted successfully"
    echo "📊 Check Grafana dashboard for CDC events: http://localhost:3000"
else
    echo "❌ Failed to insert sample data"
fi

echo ""
echo "🔍 Recent CDC events (last 10):"
sleep 5
curl -s "http://localhost:9200/tidb-cdc-logs-$(date +%Y.%m.%d)/_search?size=10&sort=@timestamp:desc" | \
python3 -m json.tool 2>/dev/null | grep -A 5 -B 5 "CDC Event" | head -20 || \
echo "No CDC events found yet. Wait a few moments and check Grafana."

echo ""
echo "✨ Test completed! Visit the Grafana dashboard to see real-time CDC monitoring."