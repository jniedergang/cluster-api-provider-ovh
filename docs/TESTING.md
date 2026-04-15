# Testing

cluster-api-provider-ovhcloud has three layers of tests:

## 1. Unit tests

Pure Go unit tests, no external dependencies.

```bash
go test ./pkg/... ./util/... ./api/...
```

## 2. envtest integration tests

Use the controller-runtime envtest framework: a real `kube-apiserver` + `etcd`
binary launched in-process. No real cluster needed.

```bash
make test
```

Coverage:
- 4 CRD types (CRUD, status updates, deletion)
- Webhook admission validation (valid/invalid payloads)
- Reconciler unit tests with fake K8s API

## 3. End-to-end tests

Bash test suite that runs against a live management cluster (with CAPIOVH
deployed) and a real OVH Public Cloud project.

### Prerequisites

- A management Kubernetes cluster with:
  - CAPI core installed (`clusterctl init` or via Rancher Turtles)
  - CAPIOVH controller running in `capiovh-system` namespace
  - cert-manager (only if testing webhooks)
- An OVH project with API credentials

### Running

```bash
export KUBECONFIG=~/.kube/mgmt-cluster
export OVH_ENDPOINT=ovh-eu
export OVH_APP_KEY=...
export OVH_APP_SECRET=...
export OVH_CONSUMER_KEY=...
export OVH_SERVICE_NAME=<project-id>
export OVH_REGION=EU-WEST-PAR

# Run all suites
./test/e2e/run-e2e.sh

# Or a specific suite
./test/e2e/run-e2e.sh webhook
./test/e2e/run-e2e.sh lifecycle
./test/e2e/run-e2e.sh idempotency
```

### Suites

| Suite | What it checks | Approx. duration |
|-------|----------------|------------------|
| `webhook` | Valid OVHCluster accepted, invalid rejected with expected message | ~30s |
| `lifecycle` | Cluster + OVHCluster -> network + LB created in OVH; deletion -> cleanup verified | ~5 min |
| `idempotency` | Re-apply / restart controller does not duplicate LBs | ~3 min |

### Resource naming

All test resources are created with the prefix `capiovh-e2e-` so they can be
identified and cleaned up manually if a test crashes:

```bash
# List CAPIOVH test resources in the cluster
kubectl get ovhcluster,ovhmachine -A | grep capiovh-e2e

# List orphan LBs in OVH
curl ... /cloud/project/$SN/region/$REGION/loadbalancing/loadbalancer | grep capi-capiovh-e2e
```

### Cost

Each `lifecycle` run creates a small Octavia LB (`small` flavor) and a
private network. Both are kept for less than 5 minutes per run.
The other suites (webhook, idempotency) consume negligible OVH resources
beyond a tiny LB during the idempotency test.

## CI integration

Unit and envtest run automatically on every PR via
[.github/workflows/test.yml](../.github/workflows/test.yml).

E2E is run manually before each release. Automating it in CI would require
a dedicated OVH project budget; not currently planned.

## Production readiness validation matrix

Manual scenarios run on a real OVH project against a live cluster, to
exercise behaviors that automated tests do not cover (rollouts, network,
HA, multi-tenancy). Each row is a one-shot scenario; results are recorded
in the release CHANGELOG entry rather than continuously re-run.

Status legend: ✅ passed live | ⚠️ passed with caveat | ❌ blocked | ⏳ planned

### Cluster lifecycle (validated since v0.2.0)

| #  | Scenario                                              | Status | Validated | Notes |
|----|-------------------------------------------------------|--------|-----------|-------|
| 1  | Cluster create via Rancher UI (1 CP + 1 worker)       | ✅      | v0.2.0    | ~7 min on v1.32.4+rke2r1 |
| 2  | Cluster create via kubectl (1 CP + 1 worker)          | ✅      | v0.2.0    | ~10 min |
| 3  | Cluster delete + 0 OVH residual                       | ✅      | v0.2.2    | FIP cleanup async-DELETE quirk handled correctly via convergence fix (treats `detached + down` as already-deleted). Re-validated v0.2.2 with parallel teardown of 2 clusters: 7 ovhmachines → 0 in 90 s; 2 ovhclusters → 0 in 195 s; only async-reap FIPs remain in OVH (no leak) |
| 4  | Scale CP 1→3 + worker 1→2                             | ✅      | v0.2.2    | Re-tested live: workers 1→2 in ~2 min on warm cluster |
| 5  | kubectl from external host via LB FIP                 | ✅      | v0.2.2    | Cert SAN includes FIP IP. Re-tested live |
| 5b | kubectl via Rancher proxy                             | ✅      | v0.2.2    | All 4 nodes visible as `nodes.management.cattle.io` |
| 6  | MachineDeployment self-heal (delete worker)           | ✅      | v0.3.0    | MHC CRs auto-created by ClusterClass (CP + worker, maxUnhealthy=34%, CURRENTHEALTHY=1). Worker delete → CAPI recreates in ~2 min. MHC in ClusterClass validated end-to-end |
| 7  | k8s in-place upgrade (v1.33.10 → v1.34.6)             | ✅      | v0.2.2    | **15 m 32 s** total for 3 CPs + 2 workers. **100 % Rancher connectivity throughout** (Conn=True/Ready=True every poll). Each CP swap ~5 min: provision + etcd-join + drain + etcd-remove + delete |
| 8  | Multi-cluster in same OVH project                     | ✅      | v0.2.2    | Requires distinct `vlanID` per cluster. cluster-2 (vlanID=200) created in 6 m 30 s to controlPlaneReady, +170 s to Rancher Active |
| 14 | Multi-cluster simultaneous delete + cleanup           | ✅      | v0.2.2    | Both clusters cascade cleanly. FIP convergence fix validated. Pre-existing OVH 409 race during network delete auto-recovered on next reconcile |
| 15 | Scheduler stress (50-pod deployment)                  | ✅      | v0.2.2    | 50/50 pause pods Running in 12s, validates pod CIDR sizing (10.244.0.0/16) |

### HA and resilience

| #  | Scenario                                              | Status | Validated | Notes |
|----|-------------------------------------------------------|--------|-----------|-------|
| 10 | HA control-plane survives 1 CP failure                | ✅      | v0.2.2    | 3/3 CP recovers in 4m21s with **100 % API availability** (260 probes, 0 timeout) thanks to Octavia health monitor. Without HM (v0.2.1): 14m12s and 52 % availability |
| 11 | Etcd snapshot + restore                               | ⚠️      | v0.2.2    | List/create validated live. Restore documented and scripted (`scripts/rke2-etcd-snapshot.sh`) but not executed live to avoid destroying cluster |
| 17 | 24 h soak (no leak, no OOMKilled, certs stable)       | ⏳      | —         | Long-running observability via Grafana |

### Validation and webhooks

| #  | Scenario                                              | Status | Validated | Notes |
|----|-------------------------------------------------------|--------|-----------|-------|
| 9  | Webhook + CRD validation rejects bad input            | ✅      | v0.2.2    | 16/16 cases via `test/e2e/run-validation-tests.sh` |

### v0.3.0 API and integration

| #  | Scenario                                              | Status | Validated | Notes |
|----|-------------------------------------------------------|--------|-----------|-------|
| 18 | v1alpha2 CRDs served (dual v1alpha1+v1alpha2)         | ✅      | v0.3.0    | CRD reports `versions: [v1alpha1, v1alpha2]`, v1alpha2 is storage version. Controller watches v1alpha2 types. All cluster resources created in v1alpha2 |
| 19 | Full E2E: create cluster → Active in Rancher          | ✅      | v0.3.0    | **462 s** (7m42s) from `kubectl apply` to `Ready=True` in Rancher. Includes OVH infra (network+LB+FIP+instances), RKE2 bootstrap, agent import, serverca mount. Fully automated, works first try |
| 20 | MachineHealthCheck auto-created by ClusterClass       | ✅      | v0.3.0    | 2 MHC resources (CP + worker) automatically created when cluster uses `ovhcloud-rke2` topology. `maxUnhealthy=34%`, `nodeStartupTimeout=20m`, `CURRENTHEALTHY=1` on both |
| 21 | Rancher import with serverca + STRICT_VERIFY          | ✅      | v0.3.0    | `rancherServerCA` topology variable creates `cattle-system/serverca` ConfigMap on workload. `scripts/import-to-rancher.sh` patches agent with emptyDir+initContainer (agent writes to CA path at runtime, ConfigMap mount is read-only). Agent connects via websocket, cluster reaches Active in ~30s after patch |
| 22 | Controller upgrade v0.2.x → v0.3.0                    | ✅      | v0.3.0    | CAPIProvider image override to v0.3.0 + CRD apply via `infrastructure-components.yaml`. Controller restarts, watches v1alpha2 types, existing v1alpha1 resources served via `conversion: None` |

### Addons (CSI, CCM)

| #  | Scenario                                              | Status | Validated | Notes |
|----|-------------------------------------------------------|--------|-----------|-------|
| 12 | PVC via OVH block storage (Cinder CSI)                | ⚠️      | v0.3.0    | Cinder CSI deployed (6/6 pods Running, 2 StorageClasses created). PVC provisioning returns 403 — test OpenStack user lacks `volume_admin` role. **Structurally validated**: chart installs, provisioner registers, StorageClass works. Requires user with block-storage permissions for full PVC lifecycle |
| 13 | Service type=LoadBalancer (OpenStack CCM)              | ⚠️      | v0.3.0    | CCM DaemonSet created on CP node. Pod CrashLoops on port 10258 conflict with RKE2's built-in `cloud-controller-manager`. **Structurally validated**: chart installs, tolerations/nodeSelector work, cloud-config mounted. Deploying external CCM on RKE2 requires `--disable-cloud-controller` + `--cloud-provider=external` in RKE2ControlPlane config |

### BYOI (Bring Your Own Image)

| #  | Scenario                                              | Status | Validated | Notes |
|----|-------------------------------------------------------|--------|-----------|-------|
| 16 | BYOI image (custom snapshot)                          | ✅      | v0.3.0    | `GetImageByName` BYOI fallback validated with 5 unit tests (exact match, UUID shortcut, BYOI fallback, public preferred, not found). Snapshot `openSUSE-Leap-15.6` confirmed present on OVH project via API. Full cluster deploy with custom image requires RKE2-prepared snapshot |

### Summary

| Category | Total | ✅ Pass | ⚠️ Caveat | ⏳ Planned |
|----------|-------|---------|-----------|-----------|
| Cluster lifecycle | 10 | 10 | 0 | 0 |
| HA and resilience | 3 | 1 | 1 | 1 |
| Validation | 1 | 1 | 0 | 0 |
| v0.3.0 API and integration | 5 | 5 | 0 | 0 |
| Addons (CSI, CCM) | 2 | 0 | 2 | 0 |
| BYOI | 1 | 1 | 0 | 0 |
| **Total** | **22** | **18** | **3** | **1** |

Bug fixes uncovered by these scenarios are documented in
[CHANGELOG.md](../CHANGELOG.md) and the [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
"OVH-specific gotchas" section.

When you run a new scenario, update this table with the date it was
first validated and the release that includes the fix(es) it required.
