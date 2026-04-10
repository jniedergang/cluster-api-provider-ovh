# Cluster API Provider OVH Cloud (CAPIOVH)

Provider [Cluster API](https://cluster-api.sigs.k8s.io/) pour provisionner
des clusters Kubernetes sur OVH Public Cloud.

## Architecture

```
Management Cluster (CAPI)
  |
  |-- OVHCluster CR -----> OVHCluster Controller
  |     spec:                - Valide credentials OVH (GET /me)
  |       serviceName        - Cree reseau prive + subnet
  |       region             - Cree LB Octavia (listener 6443, pool)
  |       identitySecret     - Set controlPlaneEndpoint = VIP
  |       loadBalancerConfig
  |       networkConfig
  |
  |-- OVHMachine CR -----> OVHMachine Controller
        spec:                - Resolve flavor + image par nom
          flavorName         - Lit bootstrap data (cloud-init)
          imageName          - POST /cloud/project/{sn}/instance
          sshKeyName         - Poll BUILD -> ACTIVE
                             - Set providerID + addresses
                                       |
                                       v
                              OVH Public Cloud
                              (instances, reseaux, LB Octavia)
```

## CRDs

| CRD | Description |
|-----|-------------|
| `OVHCluster` | Infrastructure cluster : credentials, region, reseau, LB |
| `OVHMachine` | Instance compute : flavor, image, SSH key, volumes |
| `OVHMachineTemplate` | Template pour MachineDeployment / ControlPlane |
| `OVHClusterTemplate` | Template pour ClusterClass |

## Pre-requis

- Cluster de management avec CAPI installe
- Projet OVH Public Cloud avec credentials API (voir [guide](docs/ovh-credentials-guide.md))
- Bootstrap provider RKE2 (ou kubeadm)

## Credentials OVH

Le provider utilise l'API native OVH (pas OpenStack). Les credentials sont
stockees dans un Secret Kubernetes :

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ovh-credentials
  namespace: default
type: Opaque
stringData:
  endpoint: "ovh-eu"
  applicationKey: "<votre AK>"
  applicationSecret: "<votre AS>"
  consumerKey: "<votre CK>"
```

Voir [docs/ovh-credentials-guide.md](docs/ovh-credentials-guide.md) pour
le guide complet de creation des credentials avec droits limites.

## Quickstart

```bash
# 1. Installer les CRDs
make install

# 2. Lancer le controller (dev)
make run

# 3. Appliquer un cluster
kubectl apply -f config/samples/
```

## Developpement

```bash
# Build
make build

# Tests unitaires
go test ./pkg/ovh/... -v
go test ./util/... -v

# Tests controllers (envtest)
make test

# Generer CRDs et RBAC
make manifests

# Generer DeepCopy
make generate

# Build image conteneur (Podman)
make docker-build

# Linter
make fmt vet
```

## Structure du projet

```
api/v1alpha1/          Types CRD (OVHCluster, OVHMachine, templates)
cmd/main.go            Entrypoint controller manager
internal/controller/   Reconcilers (OVHMachine, OVHCluster)
internal/metrics/      Metriques Prometheus
pkg/ovh/               Client API OVH (wrapper go-ovh)
util/                  Helpers (cloud-init, providerID, RFC1035)
config/                Kustomize (CRDs, RBAC, manager, samples)
templates/             Cluster templates (RKE2)
docs/                  Documentation (credentials guide)
```

## Metriques Prometheus

| Metrique | Type | Description |
|----------|------|-------------|
| `capiovh_machine_create_total` | Counter | Tentatives de creation d'instances |
| `capiovh_machine_create_errors_total` | Counter | Erreurs de creation |
| `capiovh_machine_creation_duration_seconds` | Histogram | Duree de creation |
| `capiovh_machine_delete_total` | Counter | Tentatives de suppression |
| `capiovh_machine_status` | Gauge | Etat des machines (1=ready) |
| `capiovh_cluster_ready` | Gauge | Etat des clusters (1=ready) |
| `capiovh_*_reconcile_duration_seconds` | Histogram | Duree de reconciliation |

## Licence

Apache License 2.0
