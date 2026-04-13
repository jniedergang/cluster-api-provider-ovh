# Operations guide

How to install, monitor, upgrade and uninstall CAPIOVH in production.

## Installation

### Option 1 — Helm (recommended)

```bash
helm install capiovh \
  oci://ghcr.io/rancher-sandbox/charts/cluster-api-provider-ovhcloud \
  --version 0.1.0 \
  --namespace capiovh-system --create-namespace \
  --set webhooks.enabled=true \
  --set webhooks.certManager.enabled=true
```

Requires:
- CAPI core installed (`clusterctl init` or Rancher Turtles)
- cert-manager (only if `webhooks.enabled=true`)

### Option 2 — clusterctl

```bash
clusterctl init --infrastructure ovhcloud
```

This works once the provider is added to the
[`clusterctl-provider-list`](https://cluster-api.sigs.k8s.io/clusterctl/configuration.html#provider-list).
While we work on upstream submission, use the manifest directly:

```bash
kubectl apply -f https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud/releases/download/v0.1.0/infrastructure-components.yaml
```

### Option 3 — Rancher Turtles (CAPIProvider)

```yaml
apiVersion: turtles-capi.cattle.io/v1alpha1
kind: CAPIProvider
metadata:
  name: ovhcloud
  namespace: cattle-capi-system
spec:
  type: infrastructure
  configSecret:
    name: ovhcloud-variables
  fetchConfig:
    url: https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud/releases/v0.1.0
```

## Provisioning a cluster

1. Create the OVH credentials Secret in your target namespace:

```bash
kubectl create ns demo
kubectl -n demo create secret generic ovh-credentials \
  --from-literal=endpoint=ovh-eu \
  --from-literal=applicationKey=... \
  --from-literal=applicationSecret=... \
  --from-literal=consumerKey=...
```

See [ovh-credentials-guide.md](ovh-credentials-guide.md) for how to obtain
these credentials with a properly scoped Consumer Key.

2. Apply a cluster template:

```bash
clusterctl generate cluster mycluster \
  --infrastructure ovhcloud \
  --kubernetes-version v1.31.0 \
  --control-plane-machine-count 3 \
  --worker-machine-count 2 | kubectl -n demo apply -f -
```

Or use one of the templates directly (see [../templates/](../templates/)).

3. Watch progress:

```bash
kubectl -n demo get cluster,ovhcluster,machine,ovhmachine -w
```

## Monitoring

### Prometheus metrics

The controller exposes metrics on `:8080/metrics` (configurable via
`--metrics-bind-address`):

| Metric | Type | Description |
|--------|------|-------------|
| `capiovh_machine_create_total` | Counter | Total instance creation attempts |
| `capiovh_machine_create_errors_total` | Counter | Instance creation errors |
| `capiovh_machine_creation_duration_seconds` | Histogram | Time from POST to ACTIVE |
| `capiovh_machine_delete_total` | Counter | Total instance deletion attempts |
| `capiovh_machine_status` | Gauge | 1 if machine is Ready, 0 otherwise |
| `capiovh_cluster_ready` | Gauge | 1 if cluster is Ready, 0 otherwise |
| `capiovh_machine_reconcile_duration_seconds` | Histogram | Reconcile duration (`operation` label: `normal` or `delete`) |
| `capiovh_cluster_reconcile_duration_seconds` | Histogram | Cluster reconcile duration |

A `ServiceMonitor` for Prometheus Operator can be deployed via the
`config/prometheus/` overlay (TODO).

### Logs

```bash
# Live tail
kubectl -n capiovh-system logs -f deploy/capiovh-controller-manager

# Only errors
kubectl -n capiovh-system logs deploy/capiovh-controller-manager | grep -i error

# Specific cluster
kubectl -n capiovh-system logs deploy/capiovh-controller-manager | grep mycluster
```

The controller uses zap with `Development=true` by default; structured
JSON output can be enabled by setting `--zap-encoder=json`.

## Upgrade

### Helm

```bash
helm upgrade capiovh \
  oci://ghcr.io/rancher-sandbox/charts/cluster-api-provider-ovhcloud \
  --version 0.2.0 \
  --namespace capiovh-system \
  --reuse-values
```

Always check the [release notes](https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud/releases)
for breaking changes before upgrading.

### Manifest-based

```bash
kubectl apply -f https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud/releases/download/v0.2.0/infrastructure-components.yaml
```

Existing CRs are preserved; the controller re-reconciles them with the
new version. CRD changes (rare for v0.x) are forward-compatible thanks
to the additive nature of CAPI v1beta1.

## Uninstall

```bash
# 1. Delete all clusters managed by the provider first
kubectl get cluster -A -l cluster.x-k8s.io/provider=infrastructure-ovhcloud
# (delete each one)

# 2. Wait for cleanup to complete (no OVHMachine / OVHCluster left)
kubectl get ovhcluster,ovhmachine -A

# 3. Uninstall the provider
helm uninstall capiovh -n capiovh-system

# 4. Remove CRDs (Helm convention is to NOT remove them automatically)
kubectl delete crd ovhclusters.infrastructure.cluster.x-k8s.io
kubectl delete crd ovhclustertemplates.infrastructure.cluster.x-k8s.io
kubectl delete crd ovhmachines.infrastructure.cluster.x-k8s.io
kubectl delete crd ovhmachinetemplates.infrastructure.cluster.x-k8s.io
```

## Backup / disaster recovery

The provider is stateless; all state lives in:

- The management cluster's etcd (CRD instances)
- The OVH project (instances, network, LB)

For DR:
- Back up the management cluster (Velero or similar)
- Re-deploy CAPIOVH and re-apply CRs after restore — the controller
  will re-discover existing OVH resources via list-by-name
  (idempotent reconciliation)

## Tuning

| Knob | Default | Effect |
|------|---------|--------|
| `replicas` | 1 | Set to 2+ for HA. `leaderElect=true` ensures only one is active. |
| `resources.limits.memory` | 256Mi | Increase if you have many clusters or large reconcile cycles. |
| `--reconcile-interval` (default ~30s requeue) | hardcoded | Not currently configurable. |

## Observability via Grafana

A pre-built Grafana dashboard (`config/grafana/dashboard.json`) shows:
- Reconcile rate / errors per cluster
- Machine create/delete rate
- Time-to-ACTIVE histogram

(TODO: ship the dashboard JSON.)
