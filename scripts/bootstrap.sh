#!/usr/bin/env bash
#
# Bring the entire ShopHub platform up on a local kind cluster from nothing.
#
# It creates the kind cluster defined in clusters/local/cluster.yaml (if it
# does not already exist), then installs every Helm release declared under
# clusters/local/<release>/ in dependency order, waiting for each to become
# healthy before moving on. Each release directory holds:
#   helm.yaml   - chart reference (`repo` + `chart`, or an `oci://` chart),
#                 pinned `version`, and target `namespace`
#   values.yaml - value overrides applied on top of the chart defaults
#
# Usage:
#   scripts/bootstrap.sh            # create cluster + install everything
#   SKIP_REDB=1 scripts/bootstrap.sh   # skip the Redis Enterprise operator
#
# Requirements on PATH: kind, kubectl, helm (v3.8+ for OCI support).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_DIR="$ROOT/clusters/local"
CLUSTER_NAME="shophub-local"

# Dependency order: observability first, then the DB-tier operators, then the
# operator that consumes them, then the panel that drives the operator.
RELEASES=(kube-prometheus-stack cnpg redb shop-operator shophub)

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Read a flat `key: value` field from a helm.yaml, stripping inline comments
# and surrounding quotes. Returns empty if the key is absent.
field() {
  sed -n "s/^$2:[[:space:]]*//p" "$1" \
    | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//; s/^"\(.*\)"$/\1/' \
    | head -n1
}

require() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "'$bin' is required but not on PATH"
  done
}

require kind kubectl helm

# 0. GHCR login (best effort). The shop-operator and shophub charts live in
# private GHCR packages, so `helm install` needs to authenticate to pull them.
# Token resolution order: $GHCR_TOKEN, then `gh auth token` if the gh CLI is
# present. If neither is available we continue and let the OCI install fail
# with a clear message rather than guessing credentials.
ghcr_login() {
  local user="${GHCR_USER:-${USER:-x-access-token}}"
  local token="${GHCR_TOKEN:-}"
  if [[ -z "$token" ]] && command -v gh >/dev/null 2>&1; then
    token="$(gh auth token 2>/dev/null || true)"
  fi
  if [[ -z "$token" ]]; then
    warn "no GHCR token found (set GHCR_TOKEN or run 'gh auth login'); OCI chart installs may fail until you 'helm registry login ghcr.io'"
    return 0
  fi
  log "Logging in to ghcr.io"
  echo "$token" | helm registry login ghcr.io --username "$user" --password-stdin \
    || warn "GHCR login failed; OCI chart installs may fail"
}
ghcr_login

# 1. kind cluster
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "kind cluster '$CLUSTER_NAME' already exists, reusing it"
else
  log "Creating kind cluster '$CLUSTER_NAME'"
  kind create cluster --config "$CLUSTER_DIR/cluster.yaml"
fi
kubectl cluster-info --context "kind-$CLUSTER_NAME" >/dev/null

# 2. Ingress controller (prerequisite for the shophub ingress on host :80/:443).
# Not modelled as a release directory yet; promote it to one if it needs values.
if ! kubectl get ns ingress-nginx >/dev/null 2>&1; then
  log "Installing ingress-nginx (kind provider manifest)"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  kubectl -n ingress-nginx wait --for=condition=Available deployment/ingress-nginx-controller --timeout=300s
else
  log "ingress-nginx already present, skipping"
fi

# 3. Helm releases, in order.
for release in "${RELEASES[@]}"; do
  if [[ "$release" == "redb" && "${SKIP_REDB:-0}" == "1" ]]; then
    warn "SKIP_REDB=1 set, skipping the Redis Enterprise operator (light DB tier)"
    continue
  fi

  dir="$CLUSTER_DIR/$release"
  helm_file="$dir/helm.yaml"
  values_file="$dir/values.yaml"
  [[ -f "$helm_file" ]] || die "missing $helm_file"

  repo="$(field "$helm_file" repo)"
  chart="$(field "$helm_file" chart)"
  version="$(field "$helm_file" version)"
  namespace="$(field "$helm_file" namespace)"

  [[ -n "$chart"     ]] || die "$helm_file: missing 'chart'"
  [[ -n "$version"   ]] || die "$helm_file: missing 'version'"
  [[ -n "$namespace" ]] || die "$helm_file: missing 'namespace'"

  # Resolve the install source: an OCI chart is referenced directly, a repo
  # chart needs `helm repo add` and is referenced as <alias>/<chart>.
  if [[ "$chart" == oci://* ]]; then
    chart_ref="$chart"
  else
    [[ -n "$repo" ]] || die "$helm_file: non-OCI chart needs a 'repo' URL"
    helm repo add "$release" "$repo" >/dev/null
    chart_ref="$release/$chart"
  fi
  helm repo update >/dev/null 2>&1 || true

  values_args=()
  [[ -f "$values_file" ]] && values_args=(-f "$values_file")

  log "Installing $release ($chart_ref:$version) into namespace $namespace"
  helm upgrade --install "$release" "$chart_ref" \
    --version "$version" \
    --namespace "$namespace" \
    --create-namespace \
    "${values_args[@]}" \
    --wait --timeout 10m
done

# 4. Summary.
log "Platform is up. Endpoints:"
cat <<'EOF'

  ShopHub panel : http://shophub.local        (add '127.0.0.1 shophub.local' to /etc/hosts)
  Grafana       : kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
                  then open http://localhost:3000 (user: admin)
  Prometheus    : kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

  Create a Shop from the panel and watch shop-operator reconcile it:
    kubectl get shops,deployments -A

EOF
