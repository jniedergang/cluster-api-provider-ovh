# Quickstart — from zero to an RKE2 cluster on OVH Public Cloud

This guide walks you through provisioning a real Kubernetes cluster on
OVH Public Cloud using CAPIOVH, step by step. Expect ~15 minutes from
start to `kubectl get nodes` returning Ready.

If anything misbehaves, jump to [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## 1. Prerequisites

### Management cluster

You need a Kubernetes cluster to run CAPI core + CAPIOVH. Any conformant
cluster works (kind, k3d, RKE2, Rancher, cloud-managed). For a quick
local setup:

```bash
kind create cluster --name capi-mgmt
```

Install [clusterctl](https://cluster-api.sigs.k8s.io/user/quick-start.html#install-clusterctl)
and initialize the core CAPI controllers:

```bash
clusterctl init --bootstrap rke2 --control-plane rke2
# Or for kubeadm: clusterctl init
```

### cert-manager (for webhooks)

CAPIOVH's admission webhooks are served with TLS managed by cert-manager.
Install it if you plan to enable webhooks (recommended):

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.yaml
kubectl -n cert-manager wait --for=condition=Available deploy --all --timeout=180s
```

### OVH Public Cloud credentials

You need an OVH Public Cloud project and API keys. Full guide:
[ovh-credentials-guide.md](ovh-credentials-guide.md).

The short version: generate an Application Key / Application Secret /
Consumer Key tuple scoped to your project at
<https://api.ovh.com/createApp/> and
<https://api.ovh.com/createToken/> (`GET`, `POST`, `PUT`, `DELETE` on
`/cloud/project/<PROJECT_ID>/*`).

Export them for the rest of this guide:

```bash
export OVH_ENDPOINT=ovh-eu             # or ovh-ca, ovh-us, ...
export OVH_APP_KEY=...
export OVH_APP_SECRET=...
export OVH_CONSUMER_KEY=...
export OVH_SERVICE_NAME=<project-id>   # 32-char hex
export OVH_REGION=EU-WEST-PAR
export OVH_SSH_KEY=<ssh-key-name>      # pre-registered in OVH
```

## 2. Install CAPIOVH

### Option A: Helm (recommended)

```bash
helm install capiovh \
  oci://ghcr.io/rancher-sandbox/charts/cluster-api-provider-ovhcloud \
  --version 0.2.0 \
  --namespace capiovh-system --create-namespace \
  --set webhooks.enabled=true \
  --set webhooks.certManager.enabled=true

kubectl -n capiovh-system rollout status deploy --timeout=120s
```

### Option B: raw manifest

```bash
kubectl apply -f https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud/releases/download/v0.2.0/infrastructure-components.yaml
```

Verify:

```bash
kubectl -n capiovh-system get pods
# NAME                          READY   STATUS    RESTARTS   AGE
# capiovh-controller-...        1/1     Running   0          1m

kubectl get crd | grep ovh
# ovhclusters.infrastructure.cluster.x-k8s.io
# ovhclustertemplates.infrastructure.cluster.x-k8s.io
# ovhmachines.infrastructure.cluster.x-k8s.io
# ovhmachinetemplates.infrastructure.cluster.x-k8s.io
```

## 3. Store the OVH credentials as a Secret

Each workload cluster reads its OVH credentials from a namespaced
`Secret`. Create a namespace for your cluster and the secret:

```bash
kubectl create namespace demo

kubectl -n demo create secret generic ovh-credentials \
  --from-literal=endpoint=$OVH_ENDPOINT \
  --from-literal=applicationKey=$OVH_APP_KEY \
  --from-literal=applicationSecret=$OVH_APP_SECRET \
  --from-literal=consumerKey=$OVH_CONSUMER_KEY
```

## 4. Generate and apply the Cluster manifests

Download the RKE2 template (replace with `cluster-template-kubeadm.yaml`
or `cluster-template-rke2-floatingip.yaml` if you prefer those flavors):

```bash
export CLUSTER_NAME=demo-cluster
export KUBERNETES_VERSION=v1.31.4+rke2r1
export CONTROL_PLANE_MACHINE_COUNT=1
export WORKER_MACHINE_COUNT=2
export OVH_FLAVOR_CP=b3-8
export OVH_FLAVOR_WORKER=b3-8
export OVH_IMAGE="Ubuntu 24.04"
export OVH_SUBNET_CIDR=10.42.0.0/24

clusterctl generate cluster $CLUSTER_NAME \
  --from https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud/releases/download/v0.2.0/cluster-template-rke2.yaml \
  --target-namespace demo \
  | kubectl apply -f -
```

This applies a `Cluster`, `OVHCluster`, `RKE2ControlPlane`,
`OVHMachineTemplate` (CP + workers), `MachineDeployment`, and a
`MachineHealthCheck`.

## 5. Watch it come up

The `OVHCluster` reconciler provisions the network + subnet + Octavia
LB first. Expect ~3 minutes for the LB to reach ACTIVE.

```bash
kubectl -n demo get ovhcluster $CLUSTER_NAME -w
# NAME           READY   ENDPOINT           AGE
# demo-cluster   true    10.42.0.100:6443   3m
```

Once `InfrastructureReady=True`, the `Machine` controllers kick in and
create the instances. Expect ~5-10 minutes for the full control plane
to come up, and then for workers to join.

```bash
kubectl -n demo get machines
kubectl -n demo get ovhmachines
kubectl -n demo get cluster $CLUSTER_NAME
# PHASE: Provisioning -> Provisioned
```

Watch conditions for any stuck step:

```bash
kubectl -n demo describe ovhcluster $CLUSTER_NAME | tail -30
kubectl -n demo describe ovhmachine -l cluster.x-k8s.io/cluster-name=$CLUSTER_NAME | tail -30
```

## 6. Grab the workload kubeconfig

Once the control plane is up:

```bash
clusterctl get kubeconfig $CLUSTER_NAME -n demo > /tmp/$CLUSTER_NAME.kubeconfig

export KUBECONFIG=/tmp/$CLUSTER_NAME.kubeconfig
kubectl get nodes
# NAME                    STATUS   ROLES                       AGE   VERSION
# demo-cluster-cp-xxxxx   Ready    control-plane,etcd,master   5m    v1.31.4+rke2r1
# demo-cluster-md-xxxxx   Ready    <none>                      3m    v1.31.4+rke2r1
# demo-cluster-md-yyyyy   Ready    <none>                      3m    v1.31.4+rke2r1
```

If the nodes stay `NotReady`, install a CNI (Calico, Cilium…). RKE2
ships Canal by default and should be Ready without manual intervention;
kubeadm templates do not.

## 7. Clean up

```bash
unset KUBECONFIG  # back to the management cluster kubeconfig

kubectl -n demo delete cluster $CLUSTER_NAME
# Wait for the Cluster CR to disappear — the controllers delete
# instances, the LB, and the private network in order.
kubectl -n demo get cluster,ovhcluster,machine,ovhmachine
# No resources found in demo namespace.
```

Verify in the OVH console that no leftover instance / load balancer /
private network exists under your project.

## Next steps

- Different flavors / regions: see the env vars listed in
  [templates/README.md](../templates/README.md)
- Public API endpoint (floating IP): use
  `cluster-template-rke2-floatingip.yaml` and set `OVH_FLOATING_NETWORK_ID`
- Topology-based clusters: see
  [templates/clusterclass/rke2/](../templates/clusterclass/rke2/)
- Bring-your-own-image (BYOI): [byoi-guide.md](byoi-guide.md)
- Production tuning: [operations.md](operations.md)
- Controller troubleshooting: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
