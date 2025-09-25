# TiDB Data Pipeline Helm Chart

Production-ready Helm chart for deploying a complete TiDB CDC data pipeline with Kafka, Elasticsearch, and comprehensive monitoring.

## Overview

This Helm chart deploys a complete data pipeline consisting of:
- **TiDB Cluster**: Distributed SQL database with PD, TiKV, TiDB, and TiCDC components
- **Apache Kafka**: Message broker for CDC events with Zookeeper
- **Elasticsearch**: For log aggregation and search
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Consumer Application**: Node.js application for processing CDC events

## Prerequisites

- Kubernetes 1.21+
- Helm 3.8+
- PV provisioner support in the underlying infrastructure (for persistence)
- Sufficient cluster resources (minimum recommended: 8 CPUs, 32GB RAM)

## Installation

### Add Helm repository (if published)
```bash
helm repo add tidb-pipeline https://example.com/charts
helm repo update
```

### Install from local directory
```bash
# Install with default values
helm install my-pipeline ./helm-chart

# Install with custom values
helm install my-pipeline ./helm-chart -f custom-values.yaml

# Install in specific namespace
helm install my-pipeline ./helm-chart --namespace tidb-pipeline --create-namespace
```

## Configuration

### Quick Start

For development/testing with minimal resources:
```yaml
# dev-values.yaml
global:
  persistence:
    enabled: false

tidb:
  pd:
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
  tikv:
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 512Mi
  tidb:
    replicaCount: 1
    resources:
      requests:
        cpu: 100m
        memory: 512Mi

kafka:
  zookeeper:
    replicaCount: 1
  broker:
    replicaCount: 1

elasticsearch:
  replicaCount: 1
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
```

### Production Configuration

For production environments:
```yaml
# prod-values.yaml
global:
  persistence:
    enabled: true
    storageClass: "fast-ssd"

tidb:
  pd:
    replicaCount: 3
    persistence:
      size: 20Gi
  tikv:
    replicaCount: 3
    persistence:
      size: 100Gi
  tidb:
    replicaCount: 3

kafka:
  zookeeper:
    replicaCount: 3
    persistence:
      size: 10Gi
  broker:
    replicaCount: 3
    persistence:
      size: 50Gi

elasticsearch:
  replicaCount: 3
  persistence:
    size: 100Gi

consumer:
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 20

monitoring:
  alerts:
    enabled: true
```

## Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.storageClass` | Storage class for all PVCs | `standard` |
| `tidb.enabled` | Enable TiDB cluster | `true` |
| `tidb.pd.replicaCount` | Number of PD replicas | `3` |
| `tidb.tikv.replicaCount` | Number of TiKV replicas | `3` |
| `tidb.tidb.replicaCount` | Number of TiDB replicas | `2` |
| `kafka.enabled` | Enable Kafka | `true` |
| `kafka.broker.replicaCount` | Number of Kafka brokers | `3` |
| `elasticsearch.enabled` | Enable Elasticsearch | `true` |
| `prometheus.enabled` | Enable Prometheus | `true` |
| `grafana.enabled` | Enable Grafana | `true` |
| `grafana.adminPassword` | Grafana admin password | `admin` |
| `consumer.enabled` | Enable consumer app | `true` |
| `consumer.autoscaling.enabled` | Enable HPA for consumer | `true` |
| `ingress.enabled` | Enable ingress | `false` |

## Usage Examples

### Access Services

1. **Port Forward to TiDB**:
```bash
kubectl port-forward svc/my-pipeline-tidb 4000:4000
mysql -h localhost -P 4000 -u root
```

2. **Access Grafana Dashboard**:
```bash
kubectl port-forward svc/my-pipeline-grafana 3000:3000
# Open http://localhost:3000 (admin/admin)
```

3. **Access Prometheus**:
```bash
kubectl port-forward svc/my-pipeline-prometheus 9090:9090
# Open http://localhost:9090
```

### Enable Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: tidb.example.com
      paths:
        - path: /
          pathType: Prefix
          service: tidb
          port: 4000
    - host: grafana.example.com
      paths:
        - path: /
          pathType: Prefix
          service: grafana
          port: 3000
  tls:
    - secretName: tidb-tls
      hosts:
        - tidb.example.com
    - secretName: grafana-tls
      hosts:
        - grafana.example.com
```

## Monitoring and Alerts

### Prometheus Alerts

The chart includes pre-configured alerts:
- TiDB instance down
- High Kafka consumer lag
- Elasticsearch cluster health
- Pod memory/CPU usage

### Grafana Dashboards

Pre-configured dashboards include:
- TiDB cluster overview
- CDC event rates and latency
- Kafka throughput
- Consumer application metrics

## Scaling

### Manual Scaling
```bash
# Scale TiDB
helm upgrade my-pipeline ./helm-chart --set tidb.tidb.replicaCount=5

# Scale Kafka
helm upgrade my-pipeline ./helm-chart --set kafka.broker.replicaCount=5
```

### Auto-scaling
The consumer application supports HPA:
```yaml
consumer:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 20
    targetCPUUtilizationPercentage: 70
```

## Backup and Recovery

### TiDB Backup
```yaml
backup:
  enabled: true
  schedule: "0 2 * * *"  # Daily at 2 AM
  retention: 30  # Keep 30 days
  s3:
    enabled: true
    bucket: my-backups
    region: us-east-1
```

## Troubleshooting

### Common Issues

1. **Pods not starting**:
```bash
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

2. **PVC not binding**:
```bash
kubectl get pvc
kubectl describe pvc <pvc-name>
```

3. **CDC not working**:
```bash
kubectl logs <ticdc-pod>
kubectl exec -it <ticdc-pod> -- curl http://localhost:8300/api/v1/changefeeds
```

4. **High memory usage**:
```bash
kubectl top pods
kubectl top nodes
```

## Security Considerations

1. **Enable Pod Security Context**:
```yaml
global:
  security:
    podSecurityContext:
      runAsNonRoot: true
      runAsUser: 1000
      fsGroup: 1000
```

2. **Enable Network Policies**:
```yaml
networkPolicies:
  enabled: true
```

3. **Use Secrets for Passwords**:
```bash
kubectl create secret generic tidb-password --from-literal=password=<secure-password>
```

## Upgrade

```bash
# Upgrade chart
helm upgrade my-pipeline ./helm-chart

# Upgrade with new values
helm upgrade my-pipeline ./helm-chart -f new-values.yaml

# Rollback if needed
helm rollback my-pipeline
```

## Uninstall

```bash
# Delete the release
helm uninstall my-pipeline

# Delete PVCs (if needed)
kubectl delete pvc -l app.kubernetes.io/instance=my-pipeline
```

## Best Practices

1. **Production Deployment**:
   - Use dedicated nodes for database components
   - Enable persistence for all stateful components
   - Configure appropriate resource limits
   - Enable monitoring and alerting
   - Use pod disruption budgets
   - Configure anti-affinity rules

2. **Security**:
   - Enable RBAC
   - Use network policies
   - Encrypt data at rest
   - Rotate credentials regularly
   - Use TLS for all communications

3. **Performance**:
   - Tune JVM heap for Elasticsearch
   - Configure appropriate Kafka partition counts
   - Set proper TiDB cache sizes
   - Use SSD storage for database components

## Contributing

Please submit issues and pull requests to the [GitHub repository](https://github.com/example/tidb-data-pipeline).

## License

This chart is licensed under the Apache 2.0 License.