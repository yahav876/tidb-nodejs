#!/bin/bash

# TiDB Data Pipeline Helm Installation Script
set -e

NAMESPACE="tidb-pipeline"
RELEASE_NAME="tidb-pipeline"
CHART_PATH="./helm-chart"

echo "🚀 TiDB Data Pipeline Helm Installer"
echo "======================================"

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first."
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -f|--values)
            VALUES_FILE="$2"
            shift 2
            ;;
        --dev)
            DEV_MODE="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="--dry-run"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -n, --namespace <name>   Kubernetes namespace (default: tidb-pipeline)"
            echo "  -r, --release <name>     Helm release name (default: tidb-pipeline)"
            echo "  -f, --values <file>      Custom values file"
            echo "  --dev                    Install with development settings (minimal resources)"
            echo "  --dry-run               Perform a dry run"
            echo "  -h, --help              Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Create namespace if it doesn't exist
echo "📦 Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create development values file if --dev flag is set
if [ "$DEV_MODE" = "true" ]; then
    echo "🔧 Creating development configuration..."
    cat > /tmp/dev-values.yaml <<EOF
global:
  persistence:
    enabled: false

tidb:
  pd:
    replicaCount: 1
    resources:
      limits:
        cpu: 500m
        memory: 1Gi
      requests:
        cpu: 100m
        memory: 256Mi
  tikv:
    replicaCount: 1
    resources:
      limits:
        cpu: 1
        memory: 2Gi
      requests:
        cpu: 200m
        memory: 512Mi
  tidb:
    replicaCount: 1
    resources:
      limits:
        cpu: 1
        memory: 2Gi
      requests:
        cpu: 200m
        memory: 512Mi
  ticdc:
    replicaCount: 1

kafka:
  zookeeper:
    replicaCount: 1
    persistence:
      enabled: false
  broker:
    replicaCount: 1
    persistence:
      enabled: false

elasticsearch:
  replicaCount: 1
  persistence:
    enabled: false
  resources:
    limits:
      cpu: 1
      memory: 2Gi
    requests:
      cpu: 200m
      memory: 1Gi

prometheus:
  persistence:
    enabled: false

grafana:
  persistence:
    enabled: false

consumer:
  replicaCount: 1
  autoscaling:
    enabled: false
EOF
    VALUES_FILE="/tmp/dev-values.yaml"
fi

# Lint the chart
echo "🔍 Linting Helm chart..."
helm lint $CHART_PATH

# Build dependencies if any
echo "📚 Building chart dependencies..."
helm dependency update $CHART_PATH 2>/dev/null || true

# Install or upgrade the chart
if helm list -n $NAMESPACE | grep -q "^$RELEASE_NAME"; then
    echo "⬆️  Upgrading existing release: $RELEASE_NAME"
    if [ -n "$VALUES_FILE" ]; then
        helm upgrade $RELEASE_NAME $CHART_PATH -n $NAMESPACE -f $VALUES_FILE $DRY_RUN
    else
        helm upgrade $RELEASE_NAME $CHART_PATH -n $NAMESPACE $DRY_RUN
    fi
else
    echo "📥 Installing new release: $RELEASE_NAME"
    if [ -n "$VALUES_FILE" ]; then
        helm install $RELEASE_NAME $CHART_PATH -n $NAMESPACE -f $VALUES_FILE $DRY_RUN
    else
        helm install $RELEASE_NAME $CHART_PATH -n $NAMESPACE $DRY_RUN
    fi
fi

if [ -z "$DRY_RUN" ]; then
    echo ""
    echo "✅ Installation complete!"
    echo ""
    echo "📊 Check pod status:"
    echo "   kubectl get pods -n $NAMESPACE"
    echo ""
    echo "🔍 View installation notes:"
    echo "   helm get notes $RELEASE_NAME -n $NAMESPACE"
    echo ""
    echo "🌐 Port forward to access services:"
    echo "   # TiDB:"
    echo "   kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-tidb 4000:4000"
    echo ""
    echo "   # Grafana:"
    echo "   kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-grafana 3000:3000"
    echo ""
    echo "   # Prometheus:"
    echo "   kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-prometheus 9090:9090"
fi