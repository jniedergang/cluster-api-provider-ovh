#!/usr/bin/env bash
# rke2-etcd-snapshot.sh — Trigger / list / restore an RKE2 etcd snapshot
# on a CAPIOVH-managed control-plane node.
#
# RKE2 takes scheduled etcd snapshots automatically (default cron 0 */5 * * *,
# 5-snapshot retention, stored at /var/lib/rancher/rke2/server/db/snapshots/).
# This helper exposes the common operations remotely via SSH:
#
#   list      List snapshots
#   create    Trigger an on-demand snapshot
#   restore   Restore a named snapshot (DESTRUCTIVE — see notes)
#
# Usage:
#   ./rke2-etcd-snapshot.sh list                   <ssh-host>
#   ./rke2-etcd-snapshot.sh create <name>          <ssh-host>
#   ./rke2-etcd-snapshot.sh restore <snapshot>     <ssh-host>
#
# <ssh-host> must SSH-resolve to a CONTROL-PLANE node (worker nodes
# don't have etcd). The SSH user needs sudo NOPASSWD; some OVH base
# images don't grant it. If sudo asks for a password, fall back to:
#
#   kubectl --kubeconfig <workload-kc> exec -n default <priv-pod> -- \
#     chroot /host /usr/local/bin/rke2 etcd-snapshot list
#
# (priv-pod = a pod scheduled on a CP with hostPID/hostNetwork/privileged
# + hostPath / mount — see docs/operations.md for the manifest.)
#
# RESTORE PROCEDURE caveats (this is intentionally manual):
#   1. Stop rke2-server on ALL CP nodes EXCEPT the one you restore on.
#   2. On the chosen CP, run `rke2 server --cluster-reset --cluster-reset-restore-path=<path>`.
#   3. Start rke2-server on that node — it becomes a fresh single-CP cluster.
#   4. The OTHER CP nodes must be deleted (via CAPI: `kubectl delete machine`)
#      so CAPI rebuilds them and they re-join the restored cluster as new
#      etcd members. Don't try to start the old etcd members; their data
#      will diverge from the restored snapshot.
#
# This script handles step 2 only — orchestration of steps 1, 3, 4 must
# be done explicitly to avoid accidental data loss.

set -euo pipefail

CMD="${1:-}"
SSH_HOST=""
SNAPSHOT_NAME=""

case "$CMD" in
  list)
    SSH_HOST="${2:-}"
    ;;
  create)
    SNAPSHOT_NAME="${2:-}"
    SSH_HOST="${3:-}"
    ;;
  restore)
    SNAPSHOT_NAME="${2:-}"
    SSH_HOST="${3:-}"
    ;;
  *)
    echo "Usage: $0 {list|create <name>|restore <snapshot>} <ssh-host>" >&2
    exit 1
    ;;
esac

if [ -z "$SSH_HOST" ]; then
  echo "ERROR: <ssh-host> is required" >&2
  exit 1
fi

SSH="ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 $SSH_HOST"

case "$CMD" in
  list)
    echo "Snapshots on $SSH_HOST:"
    $SSH 'sudo /var/lib/rancher/rke2/bin/rke2 etcd-snapshot list 2>&1'
    ;;

  create)
    if [ -z "$SNAPSHOT_NAME" ]; then
      echo "ERROR: snapshot <name> required" >&2
      exit 1
    fi
    echo "Creating snapshot \"$SNAPSHOT_NAME\" on $SSH_HOST..."
    $SSH "sudo /var/lib/rancher/rke2/bin/rke2 etcd-snapshot save --name '$SNAPSHOT_NAME' 2>&1"
    echo
    echo "Snapshot files now on disk:"
    $SSH 'sudo ls -la /var/lib/rancher/rke2/server/db/snapshots/ 2>&1'
    ;;

  restore)
    if [ -z "$SNAPSHOT_NAME" ]; then
      echo "ERROR: snapshot <name-or-path> required" >&2
      exit 1
    fi
    echo "WARNING: restore is destructive."
    echo "  - This stops rke2-server on $SSH_HOST and resets etcd to the snapshot."
    echo "  - You MUST manually delete the other CP machines via CAPI after this so"
    echo "    they can be recreated and rejoin the restored cluster (their old etcd"
    echo "    data will diverge from the snapshot)."
    echo
    read -p "Type RESTORE to proceed: " confirm
    [ "$confirm" = "RESTORE" ] || { echo "Aborted."; exit 1; }

    SNAPSHOT_PATH="$SNAPSHOT_NAME"
    case "$SNAPSHOT_NAME" in
      /*) ;;
      *)  SNAPSHOT_PATH="/var/lib/rancher/rke2/server/db/snapshots/$SNAPSHOT_NAME" ;;
    esac

    echo "Stopping rke2-server on $SSH_HOST..."
    $SSH 'sudo systemctl stop rke2-server'

    echo "Running cluster-reset --cluster-reset-restore-path=$SNAPSHOT_PATH ..."
    # cluster-reset is one-shot: it exits after restoring; restart starts fresh
    $SSH "sudo /var/lib/rancher/rke2/bin/rke2 server --cluster-reset --cluster-reset-restore-path='$SNAPSHOT_PATH' 2>&1 | tail -20"

    echo "Starting rke2-server (single-CP recovery state)..."
    $SSH 'sudo systemctl start rke2-server'
    echo
    echo "Done. Now from the management cluster:"
    echo "  1. kubectl -n fleet-default delete machine <other-cp-machines>"
    echo "  2. CAPI will recreate them and they will join the restored etcd."
    ;;
esac
