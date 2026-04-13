# cluster-api-provider-ovhcloud Helm chart

A Helm chart for installing the
[Cluster API Infrastructure Provider for OVH Public Cloud](https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud).

## Prerequisites

- Kubernetes 1.31+
- [Cluster API core](https://cluster-api.sigs.k8s.io/) installed (e.g. via `clusterctl init` or [Rancher Turtles](https://turtles.docs.rancher.com/))
- [cert-manager](https://cert-manager.io/) (only if `webhooks.enabled=true`)

## Install

```bash
helm install capiovh \
  oci://ghcr.io/rancher-sandbox/charts/cluster-api-provider-ovhcloud \
  --version 0.1.0 \
  --namespace capiovh-system --create-namespace
```

### Production deployment with webhooks

```bash
helm install capiovh \
  oci://ghcr.io/rancher-sandbox/charts/cluster-api-provider-ovhcloud \
  --version 0.1.0 \
  --namespace capiovh-system --create-namespace \
  --set webhooks.enabled=true \
  --set webhooks.certManager.enabled=true
```

## Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `image.repository` | `ghcr.io/rancher-sandbox/cluster-api-provider-ovhcloud` | Controller image |
| `image.tag` | `Chart.appVersion` | Image tag (defaults to chart appVersion) |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy |
| `replicas` | `1` | Controller replica count |
| `resources` | see values.yaml | CPU/memory limits and requests |
| `webhooks.enabled` | `false` | Enable validating webhooks (requires cert-manager TLS) |
| `webhooks.certSecretName` | `webhook-server-cert` | Secret holding the webhook TLS cert |
| `webhooks.certManager.enabled` | `false` | When true, the chart creates the cert-manager Issuer + Certificate |
| `leaderElect` | `true` | Enable leader election (recommended for HA) |
| `metrics.bindAddress` | `:8080` | Metrics endpoint bind address |
| `healthProbe.bindAddress` | `:9440` | Health probe bind address |
| `serviceAccount.create` | `true` | Create a ServiceAccount |
| `serviceAccount.name` | `""` | Name of the ServiceAccount (auto-generated if empty) |

## Uninstall

```bash
helm uninstall capiovh -n capiovh-system
```

CRDs are NOT removed by uninstall (Helm convention). To remove them:

```bash
kubectl delete crd ovhclusters.infrastructure.cluster.x-k8s.io
kubectl delete crd ovhclustertemplates.infrastructure.cluster.x-k8s.io
kubectl delete crd ovhmachines.infrastructure.cluster.x-k8s.io
kubectl delete crd ovhmachinetemplates.infrastructure.cluster.x-k8s.io
```

## Source

https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud
