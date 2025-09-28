# TiDB Operator Setup Guide

## Overview

This Helm chart uses TiDB Operator to deploy and manage TiDB clusters on Kubernetes. TiDB Operator is the recommended way to run TiDB in production on Kubernetes.

## Prerequisites

### 1. Install TiDB Operator CRDs (Required)

TiDB Operator uses Custom Resource Definitions (CRDs) to manage TiDB clusters. These must be installed before deploying this Helm chart.

```bash
kubectl create -f https://raw.githubusercontent.com/pingcap/tidb-operator/v1.5.2/manifests/crd.yaml
```

### 2. Verify CRDs Installation

```bash
kubectl get crd | grep pingcap
```

You should see:
- tidbclusters.pingcap.com
- tidbmonitors.pingcap.com
- backups.pingcap.com
- restores.pingcap.com
- backupschedules.pingcap.com
- tidbclusterautoscalers.pingcap.com
- tidbinitializers.pingcap.com
- tidbngmonitorings.pingcap.com

## Installation Methods

### Method 1: Using the Installation Script (Recommended)

```bash
./install.sh
```

The script will:
- Check for required tools (kubectl, helm)
- Check and optionally install TiDB Operator CRDs
- Create the namespace
- Install the Helm chart with TiDB Operator

### Method 2: Manual Installation

1. **Install CRDs** (if not already installed):
   ```bash
   kubectl create -f https://raw.githubusercontent.com/pingcap/tidb-operator/v1.5.2/manifests/crd.yaml
   ```

2. **Add Helm Repository**:
   ```bash
   helm repo add pingcap https://charts.pingcap.org/
   helm repo update
   ```

3. **Update Dependencies**:
   ```bash
   helm dependency update
   ```

4. **Install the Chart**:
   ```bash
   helm install tidb . \
     --namespace tidb-pipeline \
     --create-namespace
   ```

## Configuration

### TiDB Operator Configuration

The TiDB Operator can be configured in `values.yaml`:

```yaml
tidbOperator:
  enabled: true  # Deploy TiDB Operator with this chart
  operatorImage: pingcap/tidb-operator:v1.5.2
  scheduler:
    create: true
  admissionWebhook:
    create: true
```

If you already have TiDB Operator installed in your cluster, set `tidbOperator.enabled: false`.

### TiDB Cluster Configuration

Configure your TiDB cluster in `values.yaml`:

```yaml
tidbCluster:
  enabled: true
  version: v7.5.7

  pd:
    replicas: 3
    storage: 10Gi
    resources:
      requests:
        cpu: 500m
        memory: 1Gi

  tikv:
    replicas: 3
    storage: 50Gi
    resources:
      requests:
        cpu: 1
        memory: 2Gi

  tidb:
    replicas: 2
    service:
      type: LoadBalancer
    resources:
      requests:
        cpu: 1
        memory: 2Gi

  ticdc:
    enabled: true
    replicas: 2
```

## Verification

### Check TiDB Operator Status

```bash
kubectl get pods -n tidb-pipeline -l app.kubernetes.io/component=tidb-operator
```

### Check TiDB Cluster Status

```bash
kubectl get tidbcluster -n tidb-pipeline
```

Expected output:
```
NAME                         READY   PD                  TIKV   TIDB   AGE
tidb-tidb-data-pipeline-tidb   True    3/3 Healthy/Ready   3/3    2/2    10m
```

### Check Individual Components

```bash
# PD pods
kubectl get pods -n tidb-pipeline -l app.kubernetes.io/component=pd

# TiKV pods
kubectl get pods -n tidb-pipeline -l app.kubernetes.io/component=tikv

# TiDB pods
kubectl get pods -n tidb-pipeline -l app.kubernetes.io/component=tidb

# TiCDC pods
kubectl get pods -n tidb-pipeline -l app.kubernetes.io/component=ticdc
```

## Connecting to TiDB

### Port Forward

```bash
kubectl port-forward -n tidb-pipeline svc/tidb-tidb-data-pipeline-tidb-tidb 4000:4000
```

### Connect with MySQL Client

```bash
mysql -h 127.0.0.1 -P 4000 -u root
```

## Troubleshooting

### CRD Not Found Errors

If you see errors like:
```
unable to recognize "": no matches for kind "TidbCluster" in version "pingcap.com/v1alpha1"
```

Solution: Install the TiDB Operator CRDs:
```bash
kubectl create -f https://raw.githubusercontent.com/pingcap/tidb-operator/v1.5.2/manifests/crd.yaml
```

### Pods Not Starting

1. Check pod status:
   ```bash
   kubectl describe pod <pod-name> -n tidb-pipeline
   ```

2. Check logs:
   ```bash
   kubectl logs <pod-name> -n tidb-pipeline
   ```

3. Check PVC status:
   ```bash
   kubectl get pvc -n tidb-pipeline
   ```

### TiDB Cluster Not Ready

Check the TiDB cluster details:
```bash
kubectl describe tidbcluster tidb-tidb-data-pipeline-tidb -n tidb-pipeline
```

## Uninstallation

1. **Uninstall the Helm Release**:
   ```bash
   helm uninstall tidb -n tidb-pipeline
   ```

2. **Clean up PVCs** (if needed):
   ```bash
   kubectl delete pvc --all -n tidb-pipeline
   ```

3. **Delete Namespace** (optional):
   ```bash
   kubectl delete namespace tidb-pipeline
   ```

4. **Remove CRDs** (only if no other TiDB clusters exist):
   ```bash
   kubectl delete -f https://raw.githubusercontent.com/pingcap/tidb-operator/v1.5.2/manifests/crd.yaml
   ```

## Resources

- [TiDB Operator Documentation](https://docs.pingcap.com/tidb-in-kubernetes/stable)
- [TiDB Documentation](https://docs.pingcap.com/tidb/stable)
- [TiDB Operator GitHub](https://github.com/pingcap/tidb-operator)