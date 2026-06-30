#!/usr/bin/env bash
# cleanup.sh
#
# Removes all resources created by bootstrap.sh.
# Deletes the Argo CD namespace and all managed application namespaces.
#
# Usage:
#   bash scripts/cleanup.sh
#
# WARNING: This is destructive. All application workloads will be deleted.
#          Do not run against a production cluster.

set -euo pipefail

ARGOCD_NAMESPACE="argocd"
APP_NAMESPACES=(
  "sample-app-dev"
  "sample-app-staging"
  "sample-app-prod"
)

log() { echo "[cleanup] $*"; }

confirm() {
  read -r -p "[cleanup] This will delete all ArgoCD resources and application namespaces. Continue? [y/N] " reply
  case "${reply}" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) log "Aborted."; exit 0 ;;
  esac
}

delete_argocd_applications() {
  log "Deleting all Argo CD Applications (this triggers resource cascading deletion)..."
  kubectl delete applications --all -n "${ARGOCD_NAMESPACE}" --ignore-not-found || true
  kubectl delete applicationsets --all -n "${ARGOCD_NAMESPACE}" --ignore-not-found || true
  kubectl delete appprojects --all -n "${ARGOCD_NAMESPACE}" --ignore-not-found || true
}

delete_argocd() {
  log "Deleting Argo CD installation..."
  kubectl delete namespace "${ARGOCD_NAMESPACE}" --ignore-not-found
}

delete_app_namespaces() {
  for ns in "${APP_NAMESPACES[@]}"; do
    log "Deleting namespace: ${ns}"
    kubectl delete namespace "${ns}" --ignore-not-found || true
  done
}

main() {
  confirm
  delete_argocd_applications
  delete_argocd
  delete_app_namespaces
  log "Cleanup complete."
}

main "$@"
