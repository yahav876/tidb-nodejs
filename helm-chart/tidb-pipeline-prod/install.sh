#!/bin/bash
set -e

echo "================================================"
echo "TiDB Pipeline Production Installation"
echo "================================================"
echo ""

# Configuration
NAMESPACE=${NAMESPACE:-tidb-pipeline}
RELEASE_NAME=${RELEASE_NAME:-tidb-pipeline}
VALUES_FILE=${VALUES_FILE:-values.yaml}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
echo "Checking prerequisites..."

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} kubectl found"

# Check helm
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Helm is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Helm found"

# Check Kubernetes cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Connected to Kubernetes cluster"

echo ""
echo "Adding Helm repositories..."

# Add Helm repositories
helm repo add elastic https://helm.elastic.co
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add pingcap https://charts.pingcap.org/
helm repo update

echo ""
echo "Installing TiDB Operator CRDs..."

# Install TiDB Operator CRDs
kubectl apply -f https://raw.githubusercontent.com/pingcap/tidb-operator/v1.6.3/manifests/crd.yaml

echo ""
echo "Creating namespace..."

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Creating secrets..."

# Create Elasticsearch password secret (generate if not exists)
if ! kubectl get secret elasticsearch-credentials -n $NAMESPACE &> /dev/null; then
    ES_PASSWORD=$(openssl rand -base64 32)
    kubectl create secret generic elasticsearch-credentials \
        --from-literal=password=$ES_PASSWORD \
        -n $NAMESPACE
    echo -e "${YELLOW}Generated Elasticsearch password: $ES_PASSWORD${NC}"
    echo -e "${YELLOW}Please save this password securely!${NC}"
fi

# Create consumer Elasticsearch password secret
if ! kubectl get secret ${RELEASE_NAME}-tidb-consumer-elasticsearch -n $NAMESPACE &> /dev/null; then
    kubectl create secret generic ${RELEASE_NAME}-tidb-consumer-elasticsearch \
        --from-literal=password=$ES_PASSWORD \
        -n $NAMESPACE
fi

echo ""
echo "Updating Helm dependencies..."

# Update dependencies
helm dependency update

echo ""
echo "Installation Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Release Name: $RELEASE_NAME"
echo "  Values File: $VALUES_FILE"
echo ""

# Install the chart
echo "Installing TiDB Pipeline..."
helm upgrade --install $RELEASE_NAME . \
    --namespace $NAMESPACE \
    --values $VALUES_FILE \
    --timeout 15m \
    --wait

echo ""
echo "================================================"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Check pod status:"
echo "   kubectl get pods -n $NAMESPACE"
echo ""
echo "2. Wait for all pods to be ready:"
echo "   kubectl wait --for=condition=ready pod --all -n $NAMESPACE --timeout=600s"
echo ""
echo "3. Access services:"
echo ""
echo "   # TiDB:"
echo "   kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-tidb-tidb 4000:4000"
echo "   mysql -h 127.0.0.1 -P 4000 -u root"
echo ""
echo "   # Kibana:"
echo "   kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-kibana-kibana 5601:5601"
echo "   Open http://localhost:5601"
echo ""
echo "   # Grafana:"
echo "   kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-kube-prometheus-stack-grafana 3000:80"
echo "   Open http://localhost:3000"
echo "   Username: admin"
echo "   Password: $(kubectl get secret -n $NAMESPACE ${RELEASE_NAME}-kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d)"
echo ""
echo "4. Create CDC changefeed:"
echo "   kubectl exec -it ${RELEASE_NAME}-tidb-ticdc-0 -n $NAMESPACE -- /cdc cli changefeed create \\"
echo "     --pd=http://${RELEASE_NAME}-tidb-pd:2379 \\"
echo "     --sink-uri=\"kafka://${RELEASE_NAME}-kafka:9092/tidb-cdc-events?protocol=canal-json\" \\"
echo "     --changefeed-id=\"tidb-to-kafka\""
echo ""
echo "================================================"