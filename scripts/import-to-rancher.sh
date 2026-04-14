#!/usr/bin/env bash
# import-to-rancher.sh — Import a CAPIOVH cluster into Rancher in one step.
#
# Combines:
#   1. kubectl apply of the Rancher import manifest (creates cattle-cluster-agent)
#   2. patch of the agent Deployment to mount the cattle-system/serverca ConfigMap
#      at /etc/kubernetes/ssl/certs (required when Rancher is configured with
#      STRICT_VERIFY=true and a custom or LE-issued cert).
#
# The serverca ConfigMap itself is created automatically by the CAPIOVH
# ClusterClass when the optional `rancherServerCA` topology variable is set.
# Without that variable, this script will only do step 1 (the agent will fail
# to connect if Rancher requires STRICT_VERIFY).
#
# Usage:
#   ./import-to-rancher.sh <cluster-name>
#
# Required env:
#   MGMT_KUBECONFIG  - kubeconfig of the management cluster running Rancher
#   WORKLOAD_KUBECONFIG - kubeconfig of the CAPIOVH workload cluster
#
# Optional:
#   RANCHER_NS - Rancher's management cluster ID (e.g. "c-xv2gv"). If empty,
#                discovered by matching .spec.displayName against <cluster-name>.

set -euo pipefail

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
  echo "Usage: $0 <cluster-name>" >&2
  exit 1
fi
: "${MGMT_KUBECONFIG:?MGMT_KUBECONFIG must be set}"
: "${WORKLOAD_KUBECONFIG:?WORKLOAD_KUBECONFIG must be set}"

KMGMT="kubectl --kubeconfig=$MGMT_KUBECONFIG"
KWL="kubectl --kubeconfig=$WORKLOAD_KUBECONFIG"

echo "[1/4] Discovering Rancher management cluster ID for '$CLUSTER_NAME'..."
RANCHER_NS="${RANCHER_NS:-}"
if [ -z "$RANCHER_NS" ]; then
  RANCHER_NS=$($KMGMT get cluster.management.cattle.io \
    -o jsonpath="{.items[?(@.spec.displayName==\"$CLUSTER_NAME\")].metadata.name}")
  if [ -z "$RANCHER_NS" ]; then
    echo "ERROR: no Rancher cluster.management.cattle.io with displayName=$CLUSTER_NAME" >&2
    echo "Make sure Turtles has imported the CAPI cluster (label" >&2
    echo "  cluster-api.cattle.io/rancher-auto-import=true on the Cluster)" >&2
    exit 2
  fi
fi
echo "    Found: $RANCHER_NS"

echo "[2/4] Fetching import manifest URL..."
URL=$($KMGMT -n "$RANCHER_NS" \
  get clusterregistrationtoken.management.cattle.io default-token \
  -o jsonpath='{.status.manifestUrl}')
if [ -z "$URL" ]; then
  echo "ERROR: no manifestUrl on default-token in $RANCHER_NS" >&2
  exit 3
fi
echo "    URL: $URL"

echo "[3/4] Applying Rancher import manifest on workload cluster..."
$KWL apply -f "$URL"

echo "[4/4] Waiting for cattle-cluster-agent Deployment, then patching serverca mount..."
for i in $(seq 1 30); do
  if $KWL -n cattle-system get deploy cattle-cluster-agent >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! $KWL -n cattle-system get cm serverca >/dev/null 2>&1; then
  echo "WARNING: ConfigMap cattle-system/serverca not found on workload."
  echo "If Rancher uses STRICT_VERIFY=true, the agent will fail to connect."
  echo "Set the 'rancherServerCA' topology variable on the Cluster to auto-create it,"
  echo "OR create it manually:"
  echo "  $KWL -n cattle-system create configmap serverca --from-file=serverca=/path/to/ca-bundle.pem"
fi

# Idempotent patch: only add the mount if not already present.
HAS_MOUNT=$($KWL -n cattle-system get deploy cattle-cluster-agent \
  -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[?(@.name=="serverca")].name}')
if [ "$HAS_MOUNT" = "serverca" ]; then
  echo "    serverca mount already present, nothing to do."
else
  $KWL -n cattle-system patch deploy cattle-cluster-agent --type=json -p '[
    {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"mountPath":"/etc/kubernetes/ssl/certs","name":"serverca","readOnly":true}},
    {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"serverca","configMap":{"name":"serverca"}}}
  ]'
  echo "    serverca mount patched."
fi

echo
echo "Done. The cluster should appear Active in Rancher within ~30 seconds."
echo "Watch with:"
echo "  $KMGMT get cluster.management.cattle.io $RANCHER_NS -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}{\"\\n\"}'"
