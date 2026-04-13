# Development

Developer setup for hacking on cluster-api-provider-ovhcloud.

## Prerequisites

- Go 1.24 or newer
- Docker or Podman
- kubectl 1.31+
- A Kubernetes cluster you can deploy to (kind, k3d, minikube, or any RKE2/K8s)
- Optional: OVH Public Cloud project for end-to-end testing

## Cloning

```bash
git clone https://github.com/rancher-sandbox/cluster-api-provider-ovhcloud
cd cluster-api-provider-ovhcloud
```

## Build

```bash
make build           # local manager binary -> bin/manager
make docker-build    # container image
```

The container image base is `registry.suse.com/bci/bci-micro:15.7` and the
build uses the SUSE BCI golang image. CGO is disabled.

## Running tests

```bash
make test            # unit + envtest (auto-downloads kubebuilder assets)
make lint            # golangci-lint v2.11.1
make verify          # all checks: modules, generated code, manifests, lint
```

The first `make test` will download envtest binaries (etcd, kube-apiserver)
to `bin/k8s/`. Subsequent runs reuse them.

## Running the controller against a remote cluster

```bash
export KUBECONFIG=~/.kube/my-mgmt-cluster
make install         # install CRDs into the cluster
make run             # runs the controller from your machine, using the
                     # cluster's API server. Useful for fast iteration with
                     # delve or print-debugging.
```

This bypasses the in-cluster deployment. The controller's process binds to
the manager flags (port 9440 for healthz, 8080 for metrics).

## Testing webhook locally

The webhooks need TLS. The simplest way to test them is to deploy the
controller to a real cluster with cert-manager:

```bash
helm install capiovh chart/cluster-api-provider-ovhcloud \
  --namespace capiovh-system --create-namespace \
  --set image.repository=ghcr.io/yourorg/capiovh \
  --set image.tag=dev \
  --set webhooks.enabled=true \
  --set webhooks.certManager.enabled=true
```

For pure unit testing of webhook logic, use `go test ./api/v1alpha1/...`
(no cluster needed).

## Code generation

CRDs and DeepCopy methods are generated from Go types via `controller-gen`:

```bash
make generate     # writes api/v1alpha1/zz_generated.deepcopy.go
make manifests    # writes config/crd/bases/*.yaml + RBAC
```

Run both after editing any `api/v1alpha1/*_types.go` file.

## Adding a new OVH API method

When extending `pkg/ovh/client.go` for a new API call:

1. Add the request/response types to `pkg/ovh/types.go` (with `json:"..."`
   tags matching the OVH API exactly — see ARCHITECTURE.md for casing rules)
2. Add a method to `pkg/ovh/client.go` that wraps `c.api.Get/Post/Delete`
3. Wrap the call in `c.retryWithBackoff(...)` so transient 429/5xx are
   retried automatically
4. Treat 404 as success in DELETE (use `IsNotFound` helper)
5. Add a unit test in `pkg/ovh/client_test.go` using the `newTestServer`
   mock helper

## Adding a new condition type

1. Define a constant in `api/v1alpha1/<resource>_types.go` (use the
   `clusterv1.ConditionType` type)
2. Define matching reason constants
3. Use `conditions.MarkTrue/MarkFalse` in the reconciler
4. Document the meaning in [ARCHITECTURE.md](ARCHITECTURE.md#conditions)

## Releasing

See [RELEASE.md](RELEASE.md).

## Linting policy

The `.golangci.yml` config disables a few linters that are too noisy or
subjective for this project (`wsl_v5`, `nlreturn`, `mnd`, `funcorder`,
`revive`, `unparam`). All other linters in golangci-lint v2 default set
are enabled.

If you need to disable a check on a specific line:

```go
//nolint:errcheck // intentional, we don't care about the close error here
```

Be sparing with `//nolint` — most rules are there for a reason.
