# CAPIOVH addon examples (Fleet / CAAPF)

These manifests are **example overrides** intended to be committed to an
external Fleet repository (GitRepo) that targets CAPIOVH workload
clusters. They are **not** applied directly on the management cluster.

## Flow

```
+-------------------+         +-------------------------+
| Management cluster|         | External Git repository |
|                   |         | (capiovh-fleet-addons/) |
|  CAAPF            |  reads  |   fleet/                |
|  Fleet controller | -------->   calico-config/        |
|  Cluster Turtles  |         |     fleet.yaml          |
|                   |         |     manifests/          |
|                   |         |       helmchartconfig   |
+-------------------+         +-------------------------+
          |
          | GitRepo CR + clusterSelector (labels)
          v
+---------------------------+
| Workload clusters         |
| (labelled cni=calico      |
|  / cni=cilium / ...)      |
|                           |
|   RKE2 HelmChart system   |
|   picks up the config     |
+---------------------------+
```

## Files in this directory

| File | Purpose |
|------|---------|
| `calico-helmchartconfig.yaml` | Tune the bundled Canal (Calico+Flannel) CNI that RKE2 installs by default — MTU for OVH vRack, IP pool block size |
| `cilium-helmchartconfig.yaml` | Configure Cilium (when the workload cluster bootstraps with `cni: cilium` and `disable: [rke2-canal]`) |

## How to use them

1. Deploy CAAPF on your management cluster (see
   [`manifests/caapf-provider.yaml`](../../manifests/caapf-provider.yaml)).
2. Create a Git repo, e.g. `capiovh-fleet-addons`, with this structure:
   ```
   capiovh-fleet-addons/
     fleet/
       calico-config/
         fleet.yaml
         manifests/
           helmchartconfig.yaml    # from calico-helmchartconfig.yaml
       cilium-config/
         fleet.yaml
         manifests/
           helmchartconfig.yaml    # from cilium-helmchartconfig.yaml
   ```
3. In each `fleet.yaml`, add a `clusterSelector`:
   ```yaml
   namespace: fleet-default
   targetCustomizations:
     - name: calico
       clusterSelector:
         matchLabels:
           cni: calico
   ```
4. Create a Fleet `GitRepo` on the management cluster pointing to this
   repo.
5. Label your CAPIOVH workload clusters:
   ```bash
   kubectl -n <namespace> label cluster <name> cni=calico
   ```

Fleet will materialise the HelmChartConfig on the workload cluster; RKE2
applies it on its next reconcile.

## Why not ClusterResourceSet?

`ClusterResourceSet` (CRS) is the other CAPI delivery mechanism. It is
simpler but less flexible:
- No selective targeting beyond a `ClusterResourceSetBinding`
- No templating of values across environments
- No drift detection once applied

Fleet is preferred for production fleets of clusters where the addon
set diverges per cluster, environment, or tenant. For single-cluster or
uniform-fleet setups, CRS may be sufficient — see
[docs/fleet-addons.md](../../docs/fleet-addons.md) for a comparison.

## Reference

- [Fleet documentation](https://fleet.rancher.io/)
- [CAAPF upstream](https://github.com/rancher/cluster-api-addon-provider-fleet)
- [RKE2 HelmChartConfig](https://docs.rke2.io/helm)
