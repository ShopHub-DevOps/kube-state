# ShopHub Kube State

Declarative state of all Kubernetes clusters used by the ShopHub platform. This repository is the source of truth for which Helm releases run in which cluster, at which version, and with which value overrides. The structure follows the project specification (section 5.3, IaC organization).

## Repository layout

```
kube-state
├── README.md
└── clusters/
    └── local/
        ├── cluster.yaml        # cluster metadata
        ├── shop-operator/
        │   ├── helm.yaml       # OCI chart reference and pinned version
        │   └── values.yaml     # value overrides
        ├── shophub/
        │   ├── helm.yaml
        │   └── values.yaml
        └── shophub-discord/
            ├── helm.yaml
            └── values.yaml
```

## Clusters

| Cluster | Tool | Purpose |
|---|---|---|
| `local` | kind | Development and demo cluster that runs on each team member's machine. |

## Per-release files

Each Helm release directory contains two files:

- `helm.yaml`: OCI reference to the chart (for example `oci://ghcr.io/shophub-devops/charts/shop-operator`) and the pinned chart version.
- `values.yaml`: Override values applied on top of the chart defaults.

## Applying state

For now, state is applied manually with `helm upgrade --install` using the values in this repository. Adoption of a GitOps agent (Flux or ArgoCD) is optional per spec section 5.3 and can be introduced later.

## Related repositories

| Repository | Purpose |
|---|---|
| [helm-charts](https://github.com/ShopHub-DevOps/helm-charts) | Source of the charts referenced by the `helm.yaml` files in this repository |
| [shophub](https://github.com/ShopHub-DevOps/shophub) | Application referenced by `clusters/local/shophub` |
| [shop-operator](https://github.com/ShopHub-DevOps/shop-operator) | Operator referenced by `clusters/local/shop-operator` |

## License

MIT. See [LICENSE](./LICENSE).
