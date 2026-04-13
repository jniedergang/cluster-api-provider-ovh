# Fleet / CAAPF addon management

CAPIOVH delegates workload cluster addon management (CNI tuning, CSI
drivers, observability agents…) to [Fleet](https://fleet.rancher.io/),
orchestrated by the [Cluster API Addon Provider for
Fleet](https://github.com/rancher/cluster-api-addon-provider-fleet)
(CAAPF). The provider itself is intentionally minimal — instance +
network + LB lifecycle, nothing more. Everything above the cluster
boundary goes through Fleet.

This document explains how to wire up CAAPF on the management cluster,
what the repository layout should look like, and how to target a
workload cluster from the addon manifests.

## Architecture

```
                    Management cluster
              ┌────────────────────────────┐
              │ CAPIOVH controller         │  ← installs instances
              │ CAPI core                  │
              │ Rancher Turtles            │
              │   └── CAPIProvider (CAAPF) │  ← reconciles Fleet
              │ Fleet controller           │
              └──────┬─────────────────────┘
                     │ GitRepo (Fleet CR)
                     │ + clusterSelector (labels)
                     ▼
                  ┌────────────────────────────┐
                  │ External Git repository    │
                  │  capiovh-fleet-addons/     │
                  │    fleet/                  │
                  │      calico-config/        │
                  │      cilium-config/        │
                  │      harvester-csi/  (e.g.)│
                  └────────────────────────────┘
                     │
                     │ Fleet materialises bundle
                     ▼
                  ┌────────────────────────────┐
                  │ Workload cluster           │
                  │   kube-system/rke2-canal   │ ← overridden
                  │   kube-system/rke2-cilium  │ ← configured
                  └────────────────────────────┘
```

## Why not install the CNI via Fleet?

RKE2 installs the CNI (Canal by default) as a system Helm chart during
node bootstrap. Fleet needs a running agent on the workload cluster to
apply bundles — which needs pod networking — which needs a CNI.
Disabling the default CNI and relying on Fleet would create a deadlock.

The pattern we (and CAPHV) use instead: RKE2 ships the CNI with default
values, and Fleet delivers a `HelmChartConfig` that **overrides** those
values. RKE2's own HelmChart controller picks up the config and
re-applies the CNI chart with the new values. The cluster never loses
networking.

## Prerequisites

### Management cluster

- Rancher Manager with [Rancher Turtles](https://turtles.docs.rancher.com/) installed
- CAPIOVH installed (as infrastructure provider — see
  [operations.md](operations.md))
- CAAPF (installed below)

### CAAPF install

CAAPF is itself a CAPI provider (type `addon`). Install it via Turtles:

```bash
kubectl create namespace caapf-system
kubectl apply -f manifests/caapf-provider.yaml
```

Verify:

```bash
kubectl get capiprovider -A
# NAMESPACE        NAME       TYPE             VERSION   PHASE   READY
# caapf-system     fleet      addon            v0.12.0   Ready   True
# capiovh-system   ovhcloud   infrastructure   v0.2.0    Ready   True
```

Version compatibility: CAAPF v0.12.0 pairs with CAPI v1.10.x (contract
v1beta1) — which is what CAPIOVH v0.2.0 ships.

## Repository layout

Create an external Git repository (public or authenticated) dedicated
to your addon bundles. The canonical name is `capiovh-fleet-addons/`
but anything works.

```
capiovh-fleet-addons/
  fleet/
    calico-config/
      fleet.yaml
      manifests/
        helmchartconfig.yaml
    cilium-config/
      fleet.yaml
      manifests/
        helmchartconfig.yaml
    my-app/
      fleet.yaml
      manifests/
        deployment.yaml
        ...
```

Example `fleet/calico-config/fleet.yaml`:

```yaml
namespace: fleet-default
targetCustomizations:
  - name: calico
    clusterSelector:
      matchLabels:
        cni: calico
```

Example `manifests/helmchartconfig.yaml`: see
[templates/addons/calico-helmchartconfig.yaml](../templates/addons/calico-helmchartconfig.yaml).

## GitRepo

On the management cluster, create a Fleet `GitRepo` CR pointing at your
addon repo:

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: capiovh-addons
  namespace: fleet-default
spec:
  repo: https://github.com/<you>/capiovh-fleet-addons.git
  branch: main
  paths:
    - fleet
```

Private repo: create a Secret of type `kubernetes.io/ssh-auth` or
`kubernetes.io/basic-auth` and reference it via `spec.clientSecretName`.

## Targeting a cluster

Label your CAPIOVH workload `Cluster` with the keys used by the
`clusterSelector` in `fleet.yaml`:

```bash
kubectl -n demo label cluster demo-cluster cni=calico
```

Within ~30 seconds Fleet should materialise the bundle on the workload
cluster. Check on the mgmt cluster:

```bash
kubectl -n fleet-default get bundledeployments -l fleet.cattle.io/cluster=demo-cluster
```

On the workload cluster:

```bash
kubectl -n kube-system get helmchartconfig rke2-canal -o yaml
```

## Example addons shipped in this repo

- [`templates/addons/calico-helmchartconfig.yaml`](../templates/addons/calico-helmchartconfig.yaml) — tune the default Canal CNI (MTU for OVH vRack, IP pool)
- [`templates/addons/cilium-helmchartconfig.yaml`](../templates/addons/cilium-helmchartconfig.yaml) — switch to Cilium (requires `cni: cilium` at cluster bootstrap)

See [`templates/addons/README.md`](../templates/addons/README.md) for
the full flow.

## Alternative: ClusterResourceSet

If you don't want to run Fleet/CAAPF, CAPI's built-in
`ClusterResourceSet` (CRS) is a lighter alternative:

```yaml
apiVersion: addons.cluster.x-k8s.io/v1beta1
kind: ClusterResourceSet
metadata:
  name: cni-calico-overrides
  namespace: demo
spec:
  clusterSelector:
    matchLabels:
      cni: calico
  resources:
    - kind: ConfigMap
      name: cni-calico-overrides
```

Pros: no extra controllers, fewer moving parts.
Cons: no templating, no drift detection, no selective roll-out across
environments, no Git history.

Use CRS for a single cluster or a small fleet where the addon set is
static; use Fleet for production fleets with per-cluster or
per-environment divergence.

## Troubleshooting

**Symptom**: `BundleDeployment` stuck `NotReady`.
→ Check `kubectl -n <namespace> describe bundledeployment <name>`. Most
common cause: the workload cluster is not yet imported into Fleet
(Turtles auto-imports CAPIOVH clusters — give it ~2 min after the
cluster becomes Ready).

**Symptom**: HelmChartConfig applied but the CNI pods do not reload.
→ RKE2 reconciles HelmChart values on each node boot, but not on every
config change. Force a reconcile: `kubectl -n kube-system delete pod -l
app.kubernetes.io/name=helm-controller`. Next reconcile window picks up
the new config.

**Symptom**: Labels change on the `Cluster` CR but Fleet does not roll
out.
→ Fleet `GitRepo` polls on a schedule (default 15 min). Force a sync:
`kubectl -n fleet-default annotate gitrepo <name> fleet.cattle.io/force-sync=$(date +%s)`.

## References

- Fleet: <https://fleet.rancher.io/>
- CAAPF: <https://github.com/rancher/cluster-api-addon-provider-fleet>
- Rancher Turtles: <https://turtles.docs.rancher.com/>
- RKE2 HelmChartConfig: <https://docs.rke2.io/helm>
