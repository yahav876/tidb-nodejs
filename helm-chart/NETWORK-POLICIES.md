# Network Policies Documentation

## Overview

This Helm chart implements **Zero Trust Network Security** using Kubernetes Network Policies. Each component is isolated and can only communicate with specifically allowed services on defined ports.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Network Security Model                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Default: DENY ALL (Zero Trust)                            │
│                                                             │
│  Each component has explicit ALLOW rules for:              │
│  • Ingress (who can connect TO this component)             │
│  • Egress (what this component can connect TO)             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Component Communication Matrix

| Source Component | Destination | Port | Purpose |
|-----------------|-------------|------|---------|
| **TiDB** | PD | 2379 | Cluster metadata |
| **TiDB** | TiKV | 20160 | Data operations |
| **TiKV** | PD | 2379 | Region management |
| **TiKV** | TiKV | 20160 | Raft replication |
| **PD** | PD | 2380 | Leader election |
| **TiCDC** | PD | 2379 | Cluster info |
| **TiCDC** | TiKV | 20160 | Change capture |
| **TiCDC** | Kafka | 9092 | Event streaming |
| **Kafka** | Zookeeper | 2181 | Coordination |
| **Consumer** | Kafka | 9092 | Message consumption |
| **Consumer** | TiDB | 4000 | Database queries |
| **Prometheus** | All | Various | Metrics scraping |
| **Grafana** | Prometheus | 9090 | Metrics queries |
| **Grafana** | Elasticsearch | 9200 | Log queries |

## Security Features

### 1. Zero Trust Model
```yaml
networkPolicies:
  enabled: true
  defaultDenyAll: true  # Nothing allowed by default
```

### 2. DNS Resolution
All pods are allowed to perform DNS lookups:
```yaml
allowDNS: true  # Required for service discovery
```

### 3. Component Isolation
Each component has its own network policy with specific rules.

## Configuration Guide

### Enable Network Policies
```yaml
networkPolicies:
  enabled: true
  defaultDenyAll: true
  allowDNS: true
```

### Disable for Specific Component
```yaml
networkPolicies:
  components:
    tidb:
      enabled: false  # Disable network policy for TiDB
```

### Add Custom Rules
```yaml
networkPolicies:
  components:
    tidb:
      ingress:
        - name: "from-custom-app"
          from:
            - podSelector:
                matchLabels:
                  app: my-custom-app
          ports:
            - port: 4000
              protocol: TCP
```

## Common Scenarios

### 1. Allow External Database Access
```yaml
tidb:
  ingress:
    - name: "from-external"
      from:
        - namespaceSelector: {}  # Any namespace
      ports:
        - port: 4000
```

### 2. Restrict to Specific Namespace
```yaml
tidb:
  ingress:
    - name: "from-apps"
      from:
        - namespaceSelector:
            matchLabels:
              name: production-apps
      ports:
        - port: 4000
```

### 3. Allow Specific IP Ranges (requires Calico/Cilium)
```yaml
tidb:
  ingress:
    - name: "from-office"
      from:
        - ipBlock:
            cidr: 10.0.0.0/8
            except:
              - 10.0.1.0/24
      ports:
        - port: 4000
```

## Testing Network Policies

### 1. Test Allowed Connection
```bash
# Should succeed
kubectl exec -it tidb-pod -- nc -zv pd-pod 2379
```

### 2. Test Blocked Connection
```bash
# Should fail
kubectl exec -it grafana-pod -- nc -zv tikv-pod 20160
```

### 3. Debug Network Policies
```bash
# View all network policies
kubectl get networkpolicies -n tidb-pipeline

# Describe specific policy
kubectl describe networkpolicy tidb-pipeline-tidb -n tidb-pipeline

# Check pod labels
kubectl get pods -n tidb-pipeline --show-labels
```

## Troubleshooting

### Issue: Pods Cannot Connect

1. **Check if network policies are enabled:**
```bash
kubectl get networkpolicies -n tidb-pipeline
```

2. **Verify pod labels match selectors:**
```bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.labels}'
```

3. **Check DNS resolution:**
```bash
kubectl exec -it <pod> -- nslookup <service-name>
```

### Issue: External Access Blocked

Add ingress rules for external access:
```yaml
networkPolicies:
  components:
    tidb:
      ingress:
        - name: "from-external"
          from:
            - namespaceSelector:
                matchLabels:
                  name: ingress-nginx
```

### Issue: Metrics Not Working

Ensure Prometheus can access all components:
```yaml
prometheus:
  egress:
    - name: "to-all-metrics"
      to:
        - podSelector: {}  # All pods in namespace
```

## Best Practices

1. **Start with Default Deny**: Always begin with `defaultDenyAll: true`
2. **Be Explicit**: Define exact ports and protocols
3. **Use Labels**: Leverage Kubernetes labels for pod selection
4. **Document Changes**: Keep track of why each rule exists
5. **Test Thoroughly**: Verify both allowed and blocked connections
6. **Monitor Logs**: Check for connection failures in pod logs

## Security Compliance

This network policy configuration helps meet:
- **PCI DSS**: Network segmentation requirements
- **HIPAA**: Access control and audit requirements
- **SOC 2**: Network security controls
- **ISO 27001**: Network access control

## Disabling Network Policies

For development or debugging:
```yaml
networkPolicies:
  enabled: false
```

⚠️ **WARNING**: Disabling network policies removes all network restrictions!