# Upstream proposal — rancher-sandbox/cluster-api-provider-ovhcloud

This document is the dossier for proposing **cluster-api-provider-ovhcloud**
for adoption under the [rancher-sandbox](https://github.com/rancher-sandbox)
GitHub organization, alongside CAPHV (cluster-api-provider-harvester).

## Summary

| | |
|---|---|
| **Project** | `cluster-api-provider-ovhcloud` |
| **Current home** | `github.com/jniedergang/cluster-api-provider-ovhcloud` |
| **Proposed home** | `github.com/rancher-sandbox/cluster-api-provider-ovhcloud` |
| **License** | Apache 2.0 |
| **Initial maintainer** | Julien Niedergang (SUSE) |
| **CAPI contract** | v1beta1 (controller-runtime v0.21, CAPI v1.10.3) |
| **Status** | v0.1.0 ready for review |

## Why a new provider?

OVH Public Cloud is OpenStack-based, but a native OVH provider rather
than [CAPO](https://github.com/kubernetes-sigs/cluster-api-provider-openstack)
is justified by:

1. **Scoped credentials**: OVH supports per-project Application/Consumer
   Keys with fine-grained access rules. Safer than full Keystone project
   credentials (which give Cinder, Glance, Heat by default).
2. **OVH-specific quirks**: async LB POST, status casing, snapshot-as-BYOI,
   nested network schema with OpenStack UUID resolution. Easier to handle
   in a focused provider than as workarounds in CAPO.
3. **OVH-only features**: vRack private networks, OVH-managed LB flavors,
   future OVH-DNS integration are first-class.

## Maturity checklist

| | |
|---|---|
| Architecture & code design | done |
| 4 CRDs (Cluster, Machine, Templates) with CAPI v1beta1 contract | done |
| Validating webhooks (CustomValidator) | done |
| Idempotent reconciliation | done |
| Floating IP support | done |
| Orphan LB cleanup | done |
| Workload node init (providerID + taint removal) | done |
| etcd member removal on CP deletion | done |
| Webhook + cert-manager deployment | done, validated live |
| Helm chart with webhook + cert-manager | done, validated live |
| Multi-arch images (amd64+arm64) | done (workflow) |
| GitHub Actions: lint, test, build, release | done |
| Multi-flavor templates (RKE2, RKE2 + floating IP, kubeadm) | done |
| ClusterClass for topology-based clusters | done |
| E2E test script (webhook, lifecycle, idempotency) | done |
| Documentation (architecture, ops, dev, troubleshooting, release) | done |
| LICENSE, CONTRIBUTING, OWNERS, CODEOWNERS, SECURITY, MAINTAINERS | done |
| Live validation on real OVH project | done (commit e72aebc, +Phase 4 webhook) |

## What's tested live

- ✅ OVHCluster reconciliation creates network + subnet + Octavia LB
  with VIP set as controlPlaneEndpoint
- ✅ OVHMachine reconciliation resolves flavor + image (incl. BYOI from
  /snapshot), creates instance, polls BUILD → ACTIVE, sets providerID
- ✅ Webhook deployed via cert-manager, rejects invalid OVHCluster with
  expected admission error message, accepts valid spec
- ✅ Helm install with `webhooks.enabled=true,certManager.enabled=true`
  on RKE2 management cluster: pod Ready, Certificate True, Issuer True,
  webhook functional
- ✅ Cleanup: deletion removes all OVH resources (instance, network, LB);
  orphan-LB cleanup defends against duplicates from earlier runs

## Test coverage

| Layer | Count | Tooling |
|-------|-------|---------|
| Unit (pure Go) | ~50 tests | `go test` |
| envtest (real apiserver) | ~20 tests | controller-runtime envtest |
| Webhook validation | 18 tests | `admission.CustomValidator` table tests |
| End-to-end (live OVH) | 3 suites (webhook, lifecycle, idempotency) | bash + curl |

Running `make verify test` is clean. Lint is golangci-lint v2.11.1 with
0 issues.

## Compatibility

- Go 1.24 (matches CAPHV)
- Kubernetes 1.31+ (envtest tested with 1.31.0)
- CAPI core v1.10.3 (contract v1beta1)
- controller-runtime v0.21.0
- cert-manager (only for webhook deployment)

## Asks

To finalize adoption under rancher-sandbox, we would request:

1. Creation of `github.com/rancher-sandbox/cluster-api-provider-ovhcloud`
   (mirror or transfer of the current jniedergang/cluster-api-provider-ovhcloud)
2. ghcr.io publish access for `rancher-sandbox` org (image and Helm chart)
3. Inclusion in the
   [`clusterctl-provider-list`](https://cluster-api.sigs.k8s.io/clusterctl/configuration.html#provider-list)
   as `ovhcloud`
4. Code review by SUSE Solution Engineering / Rancher CAPI team

## Roadmap (post v0.1.0)

| Version | Highlights |
|---------|------------|
| v0.2.0 | Fleet/CAAPF addon management (Calico, Cilium HelmChartConfigs) |
| v0.2.x | OVH-DNS integration for cluster API names; CSI bundle decoupling |
| v0.3.0 | OVH baremetal support (in addition to Public Cloud) |
| v0.x | MachineHealthCheck-driven auto-remediation tested in CI |

## References

- Repo: https://github.com/jniedergang/cluster-api-provider-ovhcloud
- CAPHV (sibling project, same code style): https://github.com/rancher-sandbox/cluster-api-provider-harvester
- Architecture: [docs/ARCHITECTURE.md](ARCHITECTURE.md)
- Operations: [docs/operations.md](operations.md)
- Release process: [docs/RELEASE.md](RELEASE.md)
