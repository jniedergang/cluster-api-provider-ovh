# Cluster templates

Pre-built cluster manifests for use with `clusterctl generate cluster` or
direct `kubectl apply` after `envsubst`.

## Templates

| File | Bootstrap | Endpoint | Notes |
|------|-----------|----------|-------|
| [`cluster-template-rke2.yaml`](cluster-template-rke2.yaml) | RKE2 | private vRack VIP | Default. Smallest YAML. |
| [`cluster-template-rke2-floatingip.yaml`](cluster-template-rke2-floatingip.yaml) | RKE2 | public floating IP | Internet-reachable API server. |
| [`cluster-template-kubeadm.yaml`](cluster-template-kubeadm.yaml) | kubeadm | private vRack VIP | Standard CAPI bootstrap. |
| [`clusterclass/rke2/clusterclass-ovhcloud-rke2.yaml`](clusterclass/rke2/clusterclass-ovhcloud-rke2.yaml) | RKE2 (ClusterClass) | both | Install once, then create clusters with ~30 lines. |
| [`clusterclass/rke2/cluster-template-rke2-clusterclass.yaml`](clusterclass/rke2/cluster-template-rke2-clusterclass.yaml) | uses ClusterClass | both | Topology-based Cluster example. |

## Variables (common)

| Name | Required | Default | Description |
|------|:---:|---------|-------------|
| `NAMESPACE` | Y | — | Namespace to create resources in |
| `CLUSTER_NAME` | Y | — | CAPI Cluster resource name |
| `KUBERNETES_VERSION` | Y | — | e.g. `v1.31.0` |
| `CONTROL_PLANE_MACHINE_COUNT` | N | `3` | Number of control plane nodes |
| `WORKER_MACHINE_COUNT` | N | `2` | Number of worker nodes |
| `OVH_SERVICE_NAME` | Y | — | OVH Public Cloud project ID |
| `OVH_REGION` | Y | `EU-WEST-PAR` | OVH region |
| `OVH_SSH_KEY` | Y | — | Name of the SSH key registered in OVH |
| `OVH_FLAVOR_CP` | N | `b3-16` | OVH instance flavor for control plane |
| `OVH_FLAVOR_WORKER` | N | `b3-8` | OVH instance flavor for workers |
| `OVH_IMAGE` | N | `Ubuntu 22.04` | OS image (use any name from OVH catalog or BYOI) |
| `OVH_SUBNET_CIDR` | N | `10.42.0.0/24` | Private vRack subnet CIDR |
| `OVH_LB_FLAVOR` | N | `small` | Octavia LB flavor (small/medium/large/xl) |

## Variables (floating IP variant)

| Name | Required | Description |
|------|:---:|-------------|
| `OVH_FLOATING_NETWORK_ID` | Y | UUID of the OVH external network for the floating IP |

## Variables (RKE2 templates with embedded credentials)

| Name | Required | Description |
|------|:---:|-------------|
| `OVH_ENDPOINT_B64` | Y | base64 of `ovh-eu` or `ovh-ca` |
| `OVH_APPLICATION_KEY_B64` | Y | base64 of OVH AK |
| `OVH_APPLICATION_SECRET_B64` | Y | base64 of OVH AS |
| `OVH_CONSUMER_KEY_B64` | Y | base64 of OVH CK |

## Quick examples

### kubeadm template

```bash
export NAMESPACE=demo CLUSTER_NAME=demo KUBERNETES_VERSION=v1.31.0
export OVH_SERVICE_NAME=xxxxxxxx OVH_REGION=EU-WEST-PAR
export OVH_SSH_KEY=my-key

# Create the OVH credentials secret manually:
kubectl create ns "${NAMESPACE}"
kubectl -n "${NAMESPACE}" create secret generic ovh-credentials \
  --from-literal=endpoint=ovh-eu \
  --from-literal=applicationKey=... \
  --from-literal=applicationSecret=... \
  --from-literal=consumerKey=...

clusterctl generate cluster ${CLUSTER_NAME} \
  --from templates/cluster-template-kubeadm.yaml \
  --kubernetes-version ${KUBERNETES_VERSION} | kubectl apply -f -
```

### ClusterClass-based topology Cluster

```bash
# 1. Install the ClusterClass once per management cluster
kubectl apply -f templates/clusterclass/rke2/clusterclass-ovhcloud-rke2.yaml

# 2. Create a Cluster from the topology template
clusterctl generate cluster mycluster \
  --from templates/clusterclass/rke2/cluster-template-rke2-clusterclass.yaml \
  --kubernetes-version v1.31.0 | kubectl apply -f -
```
