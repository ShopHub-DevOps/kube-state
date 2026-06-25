# ShopHub Kube State

Declarative state of all Kubernetes clusters used by the ShopHub platform. This repository is the source of truth for which Helm releases run in which cluster, at which version, and with which value overrides. The structure follows the project specification (section 5.3, IaC organization).

## Repository layout

```
kube-state
├── README.md
├── Makefile                        # make up / down / status
├── scripts/
│   └── bootstrap.sh                # one-shot: create cluster + install all releases
└── clusters/
    └── local/
        ├── cluster.yaml            # kind cluster definition
        ├── kube-prometheus-stack/  # observability (Prometheus, Grafana, Alertmanager)
        │   ├── helm.yaml           # chart reference and pinned version
        │   └── values.yaml         # value overrides
        ├── cnpg/                   # CloudNativePG operator (standard DB tier)
        │   ├── helm.yaml
        │   └── values.yaml
        ├── redb/                   # Redis Enterprise operator (light DB tier)
        │   ├── helm.yaml
        │   └── values.yaml
        ├── shop-operator/          # operator: Shop, DiscordChannel, Wallet CRDs
        │   ├── helm.yaml
        │   └── values.yaml
        └── shophub/                # ShopHub platform panel
            ├── helm.yaml
            └── values.yaml
```

## Clusters

| Cluster | Tool | Purpose |
|---|---|---|
| `local` | kind | Development and demo cluster that runs on each team member's machine. |

## Per-release files

Each Helm release directory contains two files:

- `helm.yaml`: the chart reference and pinned version. Two forms are supported:
  - an OCI chart published to GHCR, referenced directly (for example `chart: oci://ghcr.io/shophub-devops/charts/shop-operator`);
  - a chart from a classic Helm repository, given as a `repo` URL plus a `chart` name (for example the `prometheus-community` repo and the `kube-prometheus-stack` chart).
  Both forms also carry the target `namespace`.
- `values.yaml`: override values applied on top of the chart defaults.

## Bringing the platform up

The whole platform boots from nothing with one command:

```
make up          # or: ./scripts/bootstrap.sh
```

This creates the kind cluster from `clusters/local/cluster.yaml`, installs an
ingress controller, and then installs every release in dependency order,
waiting for each to become healthy before continuing:

1. `kube-prometheus-stack` - shared observability foundation (must be first).
2. `cnpg` - CloudNativePG operator for the `standard` PostgreSQL DB tier.
3. `redb` - Redis Enterprise operator for the `light` Redis DB tier (skip with `SKIP_REDB=1`).
4. `shop-operator` - reconciles Shop / DiscordChannel / Wallet CRDs; needs the DB operators present first.
5. `shophub` - the platform panel that creates Shop CRs against the operator.

Other targets: `make status` (releases, pods, Shop CRs), `make down` (delete
the cluster), `make reinstall` (down then up).

Requirements on `PATH`: `kind`, `kubectl`, `helm` (v3.8+ for OCI support).

Adoption of a GitOps agent (Flux or ArgoCD) to apply this state automatically
is optional per spec section 5.3 and can replace the bootstrap script later.

## Related repositories

| Repository | Purpose |
|---|---|
| [helm-charts](https://github.com/ShopHub-DevOps/helm-charts) | Source of the charts referenced by the `helm.yaml` files in this repository |
| [shophub](https://github.com/ShopHub-DevOps/shophub) | Application referenced by `clusters/local/shophub` |
| [shop-operator](https://github.com/ShopHub-DevOps/shop-operator) | Operator referenced by `clusters/local/shop-operator` |

## License

MIT. See [LICENSE](./LICENSE).
