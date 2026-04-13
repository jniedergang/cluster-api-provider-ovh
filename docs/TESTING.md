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
