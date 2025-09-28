#!/bin/bash
set -e

echo "================================================"
echo "TiDB Data Pipeline - Installation Script"
echo "================================================"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install Helm first."
    exit 1
fi

# Define TiDB Operator version to match the Helm chart
TIDB_OPERATOR_VERSION="v1.6.3"

# Check for TiDB Operator CRDs
echo "Checking for TiDB Operator CRDs..."

# Check for critical CRDs
MISSING_CRDS=()
REQUIRED_CRDS=(
    "tidbclusters.pingcap.com"
    "backups.pingcap.com"
    "restores.pingcap.com"
    "backupschedules.pingcap.com"
    "tidbmonitors.pingcap.com"
    "tidbinitializers.pingcap.com"
    "tidbclusterautoscalers.pingcap.com"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if ! kubectl get crd "$crd" &> /dev/null; then
        MISSING_CRDS+=("$crd")
    fi
done

if [ ${#MISSING_CRDS[@]} -ne 0 ]; then
    echo ""
    echo "⚠️  Some TiDB Operator CRDs are missing:"
    for crd in "${MISSING_CRDS[@]}"; do
        echo "   - $crd"
    done
    echo ""
    read -p "Would you like to install/update TiDB Operator CRDs now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing TiDB Operator CRDs (version $TIDB_OPERATOR_VERSION)..."
        kubectl create -f "https://raw.githubusercontent.com/pingcap/tidb-operator/${TIDB_OPERATOR_VERSION}/manifests/crd.yaml"
        echo "✅ TiDB Operator CRDs installed/updated successfully!"
    else
        echo "❌ Cannot proceed without TiDB Operator CRDs."
        echo "Please install them manually:"
        echo "  kubectl create -f https://raw.githubusercontent.com/pingcap/tidb-operator/${TIDB_OPERATOR_VERSION}/manifests/crd.yaml"
        exit 1
    fi
else
    echo "✅ All required TiDB Operator CRDs are already installed"

    # Check if CRDs need updating for newer version
    echo "Checking CRD versions compatibility..."
    if ! kubectl get crd compactbackups.pingcap.com &> /dev/null; then
        echo "⚠️  Detected older CRD version. Updating to ${TIDB_OPERATOR_VERSION}..."
        kubectl create -f "https://raw.githubusercontent.com/pingcap/tidb-operator/${TIDB_OPERATOR_VERSION}/manifests/crd.yaml"
        echo "✅ TiDB Operator CRDs updated to ${TIDB_OPERATOR_VERSION}!"
    fi
fi

# Set default values
NAMESPACE=${NAMESPACE:-tidb-pipeline}
RELEASE_NAME=${RELEASE_NAME:-tidb}

echo ""
echo "Installation Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Release Name: $RELEASE_NAME"
echo ""

# Create namespace if it doesn't exist
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "Creating namespace $NAMESPACE..."
    kubectl create namespace $NAMESPACE
fi

# Add Helm repository
echo "Adding PingCAP Helm repository..."
helm repo add pingcap https://charts.pingcap.org/ &> /dev/null
helm repo update &> /dev/null

# Update dependencies
echo "Updating Helm dependencies..."
helm dependency update

# Install the chart
echo ""
echo "Installing TiDB Data Pipeline..."
helm install $RELEASE_NAME . \
    --namespace $NAMESPACE \
    --create-namespace \
    --wait \
    --timeout 10m

echo ""
echo "================================================"
echo "✅ Installation Complete!"
echo "================================================"
echo ""
echo "To check the status of your deployment:"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "To connect to TiDB:"
echo "  kubectl port-forward -n $NAMESPACE svc/${RELEASE_NAME}-tidb-data-pipeline-tidb-tidb 4000:4000"
echo "  mysql -h 127.0.0.1 -P 4000 -u root"
echo ""
echo "For more information, see the deployment notes:"
echo "  helm get notes $RELEASE_NAME -n $NAMESPACE"