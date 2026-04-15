#!/usr/bin/env bash
# CSI test: deploy a cluster in a region WITH block storage (GRA9, SBG5,
# etc.), install the Cinder CSI driver, create a PVC, mount it in a pod,
# write + read, then verify persistence across pod delete/recreate.
#
# OVH EU-WEST-PAR does NOT have block storage — use GRA9 or SBG5.
#
# Required env:
#   KUBECONFIG                Path to management cluster kubeconfig
#   OVH_SERVICE_NAME          OVH project ID
#   OVH_REGION                Region with block storage (default: GRA9)
#   OVH_FLOATING_NETWORK_ID   External network UUID
#   OVH_SSH_KEY               Registered SSH key name
#   OVH_OS_USERNAME           OpenStack username (admin role required)
#   OVH_OS_PASSWORD           OpenStack password
#
# Usage:
#   ./test/e2e/run-csi-test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="csi-test-$(date +%s | tail -c 6)"
NAMESPACE="fleet-default"
OVH_REGION="${OVH_REGION:-GRA9}"
TIMEOUT_CLUSTER=600
TIMEOUT_CSI=300

: "${OVH_SERVICE_NAME:?required}"
: "${OVH_FLOATING_NETWORK_ID:?required}"
: "${OVH_SSH_KEY:?required}"
: "${OVH_OS_USERNAME:?required}"
: "${OVH_OS_PASSWORD:?required}"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; FAILED=1; }
FAILED=0

cleanup() {
  echo "[cleanup] Deleting cluster $CLUSTER_NAME..."
  kubectl delete cluster.cluster.x-k8s.io -n "$NAMESPACE" "$CLUSTER_NAME" --wait=false 2>/dev/null || true
  for i in $(seq 1 20); do
    if ! kubectl get cluster.cluster.x-k8s.io -n "$NAMESPACE" "$CLUSTER_NAME" >/dev/null 2>&1; then
      break
    fi
    sleep 15
  done
  echo "[cleanup] Done"
}
trap cleanup EXIT

echo "=== CSI E2E Test ==="
echo "Region: $OVH_REGION (must have block storage)"
echo "Cluster: $CLUSTER_NAME"

# --- Step 1: Create cluster ---
echo "[1/6] Creating cluster in $OVH_REGION..."
cat <<EOF | kubectl apply -f -
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: $CLUSTER_NAME
  namespace: $NAMESPACE
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["10.244.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/16"]
  topology:
    class: ovhcloud-rke2
    classNamespace: $NAMESPACE
    version: v1.32.4+rke2r1
    controlPlane:
      replicas: 1
    workers:
      machineDeployments:
        - class: default-worker
          name: worker
          replicas: 1
    variables:
      - name: serviceName
        value: "$OVH_SERVICE_NAME"
      - name: region
        value: "$OVH_REGION"
      - name: identitySecretName
        value: "ovh-credentials"
      - name: subnetCIDR
        value: "10.42.0.0/24"
      - name: vlanID
        value: 600
      - name: lbFlavor
        value: "small"
      - name: floatingNetworkID
        value: "$OVH_FLOATING_NETWORK_ID"
      - name: cpFlavor
        value: "b3-8"
      - name: workerFlavor
        value: "b3-8"
      - name: image
        value: "Ubuntu 22.04"
      - name: sshKeyName
        value: "$OVH_SSH_KEY"
EOF

# --- Step 2: Wait for cluster Ready ---
echo "[2/6] Waiting for cluster (timeout ${TIMEOUT_CLUSTER}s)..."
start=$(date +%s)
while true; do
  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -gt "$TIMEOUT_CLUSTER" ]; then
    fail "Cluster not ready after ${TIMEOUT_CLUSTER}s"
    exit 1
  fi
  MACHINES=$(kubectl get machine -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c Running || true)
  if [ "$MACHINES" = "2" ]; then
    pass "Cluster ready with 2 machines in ${elapsed}s"
    break
  fi
  sleep 30
done

# --- Step 3: Get workload kubeconfig ---
echo "[3/6] Getting workload kubeconfig..."
WL_KUBECONFIG="/tmp/${CLUSTER_NAME}.kubeconfig"
kubectl get secret -n "$NAMESPACE" "${CLUSTER_NAME}-kubeconfig" \
  -o jsonpath='{.data.value}' | base64 -d > "$WL_KUBECONFIG"
KUBECONFIG="$WL_KUBECONFIG" kubectl get nodes

# --- Step 4: Deploy Cinder CSI ---
echo "[4/6] Deploying Cinder CSI..."

KUBECONFIG="$WL_KUBECONFIG" kubectl create secret generic cloud-config \
  --namespace=kube-system \
  --from-literal=cloud.conf="[Global]
auth-url = https://auth.cloud.ovh.net/v3
username = $OVH_OS_USERNAME
password = $OVH_OS_PASSWORD
tenant-id = $OVH_SERVICE_NAME
domain-name = Default
region = $OVH_REGION

[BlockStorage]
bs-version = v3
ignore-volume-az = true
"

KUBECONFIG="$WL_KUBECONFIG" kubectl apply \
  -f "${SCRIPT_DIR}/../../templates/addons/cinder-csi-helmchartconfig.yaml"

echo "  Waiting for CSI pods (timeout ${TIMEOUT_CSI}s)..."
start=$(date +%s)
while true; do
  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -gt "$TIMEOUT_CSI" ]; then
    fail "CSI not ready after ${TIMEOUT_CSI}s"
    break
  fi
  CSI_READY=$(KUBECONFIG="$WL_KUBECONFIG" kubectl get pods -n kube-system \
    -l app.kubernetes.io/name=openstack-cinder-csi 2>/dev/null \
    | grep -c Running || true)
  if [ "$CSI_READY" -ge 2 ]; then
    pass "Cinder CSI running (${CSI_READY} pods) in ${elapsed}s"
    break
  fi
  sleep 15
done

# --- Step 5: Test PVC lifecycle ---
echo "[5/6] Testing PVC lifecycle..."

KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f - <<'PVC_EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: csi-test-pvc
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: csi-test-writer
  namespace: default
spec:
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "echo 'capiovh-csi-ok' > /data/test.txt && sync && sleep 3600"]
    volumeMounts:
    - mountPath: /data
      name: vol
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: csi-test-pvc
PVC_EOF

echo "  Waiting for PVC bound + pod running..."
start=$(date +%s)
while true; do
  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -gt "$TIMEOUT_CSI" ]; then
    fail "PVC/Pod not ready after ${TIMEOUT_CSI}s"
    KUBECONFIG="$WL_KUBECONFIG" kubectl describe pvc csi-test-pvc 2>&1 | tail -5
    break
  fi
  POD_STATUS=$(KUBECONFIG="$WL_KUBECONFIG" kubectl get pod csi-test-writer \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$POD_STATUS" = "Running" ]; then
    CONTENT=$(KUBECONFIG="$WL_KUBECONFIG" kubectl exec csi-test-writer -- cat /data/test.txt 2>/dev/null)
    if [ "$CONTENT" = "capiovh-csi-ok" ]; then
      pass "PVC write/read OK in ${elapsed}s"
    else
      fail "PVC content mismatch: expected 'capiovh-csi-ok', got '$CONTENT'"
    fi
    break
  fi
  sleep 15
done

# --- Step 6: Test persistence ---
echo "[6/6] Testing persistence after pod delete..."
KUBECONFIG="$WL_KUBECONFIG" kubectl delete pod csi-test-writer --force 2>/dev/null
sleep 5
KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f - <<'READER_EOF'
apiVersion: v1
kind: Pod
metadata:
  name: csi-test-reader
  namespace: default
spec:
  containers:
  - name: reader
    image: busybox
    command: ["sh", "-c", "cat /data/test.txt && sleep 3600"]
    volumeMounts:
    - mountPath: /data
      name: vol
  volumes:
  - name: vol
    persistentVolumeClaim:
      claimName: csi-test-pvc
READER_EOF

start=$(date +%s)
while true; do
  elapsed=$(( $(date +%s) - start ))
  if [ "$elapsed" -gt 120 ]; then
    fail "Reader pod not ready after 120s"
    break
  fi
  POD_STATUS=$(KUBECONFIG="$WL_KUBECONFIG" kubectl get pod csi-test-reader \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [ "$POD_STATUS" = "Running" ]; then
    CONTENT=$(KUBECONFIG="$WL_KUBECONFIG" kubectl exec csi-test-reader -- cat /data/test.txt 2>/dev/null)
    if [ "$CONTENT" = "capiovh-csi-ok" ]; then
      pass "Data persisted across pod delete"
    else
      fail "Persistence check failed: expected 'capiovh-csi-ok', got '$CONTENT'"
    fi
    break
  fi
  sleep 10
done

echo ""
if [ "$FAILED" = "0" ]; then
  echo "=== ALL CSI TESTS PASSED ==="
else
  echo "=== SOME CSI TESTS FAILED ==="
  exit 1
fi
