#!/usr/bin/env bash
# bootstrap.sh
#
# Bootstraps a local Kubernetes cluster with Argo CD and this GitOps repository.
#
# Usage:
#   bash scripts/bootstrap.sh
#
# Prerequisites:
#   - kubectl configured against a running cluster (kind, k3d, or minikube)
#   - argocd CLI installed and available in PATH
#   - This repository cloned locally with your GitHub username updated in all YAML files

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these before running
# ---------------------------------------------------------------------------
ARGOCD_NAMESPACE="argocd"
ARGOCD_VERSION="stable"                     # Or pin to a specific version tag e.g. v2.12.0
ARGOCD_INITIAL_PORT="8080"
WAIT_TIMEOUT="180s"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log()  { echo "[bootstrap] $*"; }
die()  { echo "[bootstrap] ERROR: $*" >&2; exit 1; }

check_prereqs() {
  local missing=()
  for cmd in kubectl argocd; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required tools: ${missing[*]}. Install them before running this script."
  fi
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
install_argocd() {
  log "Creating namespace: ${ARGOCD_NAMESPACE}"
  kubectl apply -f bootstrap/argocd-namespace.yaml

  log "Installing Argo CD (${ARGOCD_VERSION})..."
  kubectl apply -n "${ARGOCD_NAMESPACE}" \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

  log "Waiting for argocd-server Deployment to become available..."
  kubectl wait --for=condition=Available \
    deployment/argocd-server \
    -n "${ARGOCD_NAMESPACE}" \
    --timeout="${WAIT_TIMEOUT}"
}

get_initial_password() {
  local password
  password=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
  echo "${password}"
}

login_argocd() {
  local password
  password=$(get_initial_password)

  log "Logging in to Argo CD CLI..."
  argocd login "localhost:${ARGOCD_INITIAL_PORT}" \
    --username admin \
    --password "${password}" \
    --insecure
}

apply_projects() {
  log "Applying Argo CD Projects..."
  kubectl apply -f bootstrap/projects/ -n "${ARGOCD_NAMESPACE}"
}

apply_config() {
  log "Applying Argo CD configuration..."
  kubectl apply -f config/argocd-cm.yaml        -n "${ARGOCD_NAMESPACE}"
  kubectl apply -f config/argocd-rbac-cm.yaml   -n "${ARGOCD_NAMESPACE}"
}

bootstrap_root_app() {
  log "Applying root App of Apps..."
  kubectl apply -f bootstrap/root-app.yaml -n "${ARGOCD_NAMESPACE}"
  log "Root app applied. Argo CD will now reconcile all child applications."
}

print_summary() {
  local password
  password=$(get_initial_password)
  cat <<EOF

---------------------------------------------------------------
Bootstrap complete.

Argo CD UI:   https://localhost:${ARGOCD_INITIAL_PORT}
Username:     admin
Password:     ${password}

Port-forward command:
  kubectl port-forward svc/argocd-server -n argocd ${ARGOCD_INITIAL_PORT}:443

Next steps:
  1. Open the UI and verify all applications appear.
  2. Change the admin password: argocd account update-password
  3. Register your Git repository if not already auto-discovered.
  4. Watch sync status: argocd app list
---------------------------------------------------------------
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  log "Starting bootstrap..."
  check_prereqs
  install_argocd

  log "Starting port-forward in background for CLI login..."
  kubectl port-forward svc/argocd-server -n "${ARGOCD_NAMESPACE}" \
    "${ARGOCD_INITIAL_PORT}:443" &>/dev/null &
  PORT_FORWARD_PID=$!
  sleep 5

  login_argocd
  apply_projects
  apply_config
  bootstrap_root_app

  kill "${PORT_FORWARD_PID}" 2>/dev/null || true
  print_summary
}

main "$@"
