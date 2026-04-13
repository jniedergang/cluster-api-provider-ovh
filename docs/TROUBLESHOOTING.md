# Troubleshooting

Common issues and how to diagnose / fix them.

## OVHCluster stuck in `status.ready=false`

Check the conditions:

```bash
kubectl -n <ns> get ovhcluster <name> -o jsonpath='{.status.conditions}' | jq
```

Then look at the controller logs:

```bash
kubectl -n capiovh-system logs deploy/capiovh-controller-manager --tail=50
```

### `OVHConnectionReady=False`

Cause: the OVH API rejected the request.

Most common reasons:

- **`This call has not been granted` (403)**: the Consumer Key access
  rules don't include the path being called. Check the rules with
  `GET /auth/currentCredential`. The Consumer Key MUST cover at minimum
  `GET/POST/PUT/DELETE /cloud/project/{serviceName}/*`. See
  [ovh-credentials-guide.md](ovh-credentials-guide.md).
- **Trailing space in rules**: rules like `/cloud/project/SN/* ` (with a
  trailing space) match nothing. Recreate the Consumer Key with clean
  paths.
- **`This application key is invalid` (403)**: the AK is for a different
  endpoint. Check `OVH_ENDPOINT` matches where the AK was created
  (`ovh-eu`, `ovh-ca`, `ovh-us`).

### `NetworkReady=False`, message "region activation in progress"

Cause: just after `CreatePrivateNetwork`, the network needs ~30-60 seconds
to be activated in the target region before subnet creation succeeds. The
controller will retry automatically; just wait.

### `LoadBalancerReady=False`, status stuck on `creating`

Cause: Octavia LB creation can take 1-3 minutes. If it's been longer,
check directly in OVH:

```bash
curl ... /cloud/project/$SN/region/$REGION/loadbalancing/loadbalancer
```

If the LB is in `error` state, OVH support may need to investigate. The
controller will not auto-recover; manually delete the LB and the
`OVHCluster.status.loadBalancerID` will be cleared on next reconcile.

## OVHMachine stuck in `BUILD`

`status.instanceID` is set, but the instance never reaches ACTIVE.

Check:

```bash
kubectl -n <ns> get ovhmachine <name> -o jsonpath='{.status.instanceID}'
# Then in OVH:
curl ... /cloud/project/$SN/instance/<instanceID>
```

If OVH reports `ERROR`, the controller marks the OVHMachine as failed.
Check the OVH Manager UI for the underlying cause (no quota, image
unavailable in region, ...). Delete the OVHMachine and re-create.

## "no endpoints available for service ... webhook-service"

Cause: webhook is enabled but the controller pod is not yet Ready, or
the cert-manager Certificate is not yet `True`.

Check:

```bash
kubectl -n capiovh-system get pods,certificate
```

Wait until both are Ready. The `cert-manager.io/inject-ca-from`
annotation injects the CA only after the Certificate is signed.

## Image not found: `image "openSUSE-Leap-15.6" not found`

Cause: the image is not in the OVH catalog and not uploaded as a custom
image (BYOI) in your project.

Fix: upload the image via OpenStack Glance (see
[byoi-guide.md](byoi-guide.md)). The provider searches both `/image`
(public catalog) and `/snapshot` (BYOI) automatically; the upload must be
visible under one of these.

## Orphan LBs in OVH after Cluster deletion

Should not happen anymore as of v0.1.0 (cleanup-orphan logic in
ReconcileDelete), but if you have leftovers from earlier versions:

```bash
# List all LBs with the capi prefix
curl ... /cloud/project/$SN/region/$REGION/loadbalancing/loadbalancer \
  | jq '.[] | select(.name | startswith("capi-"))'

# Delete one
curl -X DELETE ... /cloud/project/$SN/region/$REGION/loadbalancing/loadbalancer/<id>
```

LBs in `pending_create` or `pending_update` state cannot be deleted; wait
for them to reach `active` first.

## `cannot find any versions matching contract cluster.x-k8s.io/v1beta1`

Cause: the CAPI Cluster controller cannot resolve the InfraCluster
reference because the CRD is missing the contract version label.

Fix: ensure the `cluster.x-k8s.io/v1beta1: v1alpha1` label is set on
all 4 CRDs:

```bash
kubectl get crd ovhclusters.infrastructure.cluster.x-k8s.io \
  -o jsonpath='{.metadata.labels}' | jq
```

If missing, re-apply with the kustomize / Helm bundle which sets it
automatically.

## Cluster controller not propagating OwnerRef

Restart the CAPI core controller after installing CAPIOVH:

```bash
kubectl -n cattle-capi-system rollout restart deploy/capi-controller-manager
# or, if installed via clusterctl:
kubectl -n capi-system rollout restart deploy/capi-controller-manager
```

The CAPI controller caches the discovered CRDs at startup; after
installing a new infrastructure provider it needs to re-discover.

## Where to ask for help

- GitHub issues: https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud/issues
- For security issues: see [SECURITY.md](../SECURITY.md)
