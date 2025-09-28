# TiDB Pipeline Production Helm Chart

Production-ready Helm chart for deploying TiDB CDC pipeline with Kafka, Elasticsearch, and monitoring stack using official Helm charts as dependencies.

## Architecture

This chart deploys:
- **TiDB Cluster** with TiCDC for change data capture
- **Kafka** (Bitnami) for event streaming
- **Elasticsearch** (Elastic) for data indexing and search
- **Kibana** (Elastic) for data visualization
- **Prometheus & Grafana** (kube-prometheus-stack) for monitoring
- **Custom Consumer Application** to process CDC events

## Prerequisites

- Kubernetes 1.25+
- Helm 3.10+
- kubectl configured to access your cluster
- StorageClass configured in your cluster
- Minimum cluster resources:
  - 12 CPU cores
  - 24GB RAM
  - 300GB storage

## Quick Start

1. Clone this repository:
```bash
git clone <your-repo>
cd tidb-pipeline-prod
```

2. Review and customize `values.yaml`:
```bash
cp values.yaml values.production.yaml
# Edit values.production.yaml with your settings
```

3. Run the installation:
```bash
./install.sh
```

Or manually:
```bash
# Add Helm repositories
helm repo add elastic https://helm.elastic.co
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add pingcap https://charts.pingcap.org/
helm repo update

# Install TiDB Operator CRDs
kubectl apply -f https://raw.githubusercontent.com/pingcap/tidb-operator/v1.6.3/manifests/crd.yaml

# Create namespace
kubectl create namespace tidb-pipeline

# Install the chart
helm dependency update
helm install tidb-pipeline . -n tidb-pipeline -f values.production.yaml
```

## Configuration

### Key Configuration Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.storageClass` | Storage class for all PVCs | `standard` |
| `tidb-operator.enabled` | Enable TiDB Operator | `true` |
| `elasticsearch.replicas` | Elasticsearch replicas | `3` |
| `kafka.replicaCount` | Kafka broker replicas | `3` |
| `kafka.kraft.enabled` | Use Kafka KRaft (no Zookeeper) | `true` |
| `monitoring.enabled` | Enable Prometheus/Grafana stack | `true` |
| `consumer.replicaCount` | Consumer application replicas | `3` |
| `consumer.image.repository` | Consumer Docker image | `your-registry/tidb-consumer` |

### Storage Requirements

Component | Storage | Purpose
----------|---------|----------
TiDB PD | 10Gi x 3 | Metadata storage
TiKV | 100Gi x 3 | Data storage
Kafka | 50Gi x 3 | Message queue
Elasticsearch | 30Gi x 3 | Search index
Prometheus | 50Gi | Metrics storage
Grafana | 10Gi | Dashboard storage

### Consumer Application Configuration

The consumer application needs to be built and pushed to your registry:

```bash
# Build consumer application
cd ../consumer-app
docker build -t your-registry/tidb-consumer:latest .
docker push your-registry/tidb-consumer:latest

# Update values.yaml
consumer:
  image:
    repository: your-registry/tidb-consumer
    tag: latest
```

## Post-Installation

### 1. Verify Installation

```bash
# Check all pods are running
kubectl get pods -n tidb-pipeline

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod --all -n tidb-pipeline --timeout=600s
```

### 2. Access Services

#### TiDB Database
```bash
kubectl port-forward -n tidb-pipeline svc/tidb-pipeline-tidb-tidb 4000:4000
mysql -h 127.0.0.1 -P 4000 -u root
```

#### Kibana
```bash
kubectl port-forward -n tidb-pipeline svc/tidb-pipeline-kibana-kibana 5601:5601
# Open http://localhost:5601
# Username: elastic
# Password: <from elasticsearch-credentials secret>
```

#### Grafana
```bash
kubectl port-forward -n tidb-pipeline svc/tidb-pipeline-kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000
# Username: admin
# Password: <retrieve using kubectl>
```

### 3. Create CDC Changefeed

```bash
# Access TiCDC pod
kubectl exec -it tidb-pipeline-tidb-ticdc-0 -n tidb-pipeline -- bash

# Create changefeed
/cdc cli changefeed create \
  --pd=http://tidb-pipeline-tidb-pd:2379 \
  --sink-uri="kafka://tidb-pipeline-kafka:9092/tidb-cdc-events?protocol=canal-json" \
  --changefeed-id="tidb-to-kafka"

# List changefeeds
/cdc cli changefeed list --pd=http://tidb-pipeline-tidb-pd:2379
```

## Monitoring

### Prometheus Metrics

- TiDB metrics: `http://prometheus:9090/targets`
- Kafka metrics: JMX exporter enabled
- Consumer metrics: Custom metrics on port 9090

### Grafana Dashboards

Pre-configured dashboards:
- TiDB Cluster Overview
- Kafka Cluster Metrics
- Elasticsearch Cluster Health
- Consumer Application Metrics

### Alerts

AlertManager is configured with default rules for:
- Pod failures
- High resource usage
- Kafka lag
- Elasticsearch cluster health

## Troubleshooting

### Check Component Logs

```bash
# TiDB
kubectl logs -n tidb-pipeline tidb-pipeline-tidb-tidb-0

# Kafka
kubectl logs -n tidb-pipeline tidb-pipeline-kafka-0

# Elasticsearch
kubectl logs -n tidb-pipeline elasticsearch-master-0

# Consumer
kubectl logs -n tidb-pipeline -l app.kubernetes.io/name=tidb-consumer
```

### Common Issues

1. **Pods stuck in Pending**: Check StorageClass and PVC
```bash
kubectl get pvc -n tidb-pipeline
kubectl describe pvc <pvc-name> -n tidb-pipeline
```

2. **TiDB not ready**: Check PD first
```bash
kubectl logs -n tidb-pipeline tidb-pipeline-tidb-pd-0
```

3. **Kafka connection issues**: Verify service DNS
```bash
kubectl run -it --rm debug --image=busybox -n tidb-pipeline -- nslookup tidb-pipeline-kafka
```

## Scaling

### Horizontal Scaling

```bash
# Scale TiKV
kubectl scale --replicas=5 statefulset/tidb-pipeline-tidb-tikv -n tidb-pipeline

# Scale Kafka
helm upgrade tidb-pipeline . -n tidb-pipeline --set kafka.replicaCount=5

# Consumer auto-scales based on CPU/Memory
```

### Vertical Scaling

Update `values.yaml` with new resource limits and upgrade:
```bash
helm upgrade tidb-pipeline . -n tidb-pipeline -f values.production.yaml
```

## Backup and Recovery

### TiDB Backup

```bash
# Create backup (requires S3 or compatible storage)
kubectl apply -f - <<EOF
apiVersion: pingcap.com/v1alpha1
kind: Backup
metadata:
  name: tidb-backup-$(date +%Y%m%d)
  namespace: tidb-pipeline
spec:
  cluster: tidb-pipeline-tidb
  storageType: s3
  s3:
    bucket: your-backup-bucket
    region: us-west-2
EOF
```

### Elasticsearch Snapshots

```bash
# Configure snapshot repository
curl -X PUT "localhost:9200/_snapshot/backup" -H 'Content-Type: application/json' -d'
{
  "type": "fs",
  "settings": {
    "location": "/backup"
  }
}'
```

## Uninstall

```bash
# Remove the release
helm uninstall tidb-pipeline -n tidb-pipeline

# Delete PVCs (data will be lost!)
kubectl delete pvc --all -n tidb-pipeline

# Delete namespace
kubectl delete namespace tidb-pipeline
```

## Production Checklist

- [ ] Configure production StorageClass
- [ ] Set resource requests/limits appropriately
- [ ] Configure backup strategy
- [ ] Set up monitoring alerts
- [ ] Configure network policies
- [ ] Enable TLS/SSL for all services
- [ ] Set strong passwords for all services
- [ ] Configure pod disruption budgets
- [ ] Set up log aggregation
- [ ] Configure ingress for external access
- [ ] Review and apply security policies

## Support

For issues and questions:
- TiDB: https://github.com/pingcap/tidb/issues
- Kafka: https://github.com/bitnami/charts/issues
- Elasticsearch: https://github.com/elastic/helm-charts/issues
- This Chart: [Your repo issues]

## License

[Your License]