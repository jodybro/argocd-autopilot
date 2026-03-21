#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# ArgoCD Bootstrap Install Script
#
# Pre-installs ArgoCD CRDs from the official GitHub release, then deploys the
# bootstrap Helm umbrella chart. Safe to run multiple times (idempotent).
###############################################################################

# ---- Configuration ----------------------------------------------------------
ARGOCD_VERSION="3.1.12"
NAMESPACE="argocd"
RELEASE_NAME="argocd"
CHART_DIR="bootstrap"

CRD_BASE_URL="https://raw.githubusercontent.com/argoproj/argo-cd/v${ARGOCD_VERSION}/manifests/crds"
CRD_FILES=(
  "application-crd.yaml"
  "applicationset-crd.yaml"
  "appproject-crd.yaml"
)

# ---- Parse arguments --------------------------------------------------------
EXTRA_VALUES_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --values)
    if [[ -z "${2:-}" ]]; then
      echo "ERROR: --values requires a file path argument"
      exit 1
    fi
    EXTRA_VALUES_ARGS+=("-f" "$2")
    shift 2
    ;;
  -h | --help)
    echo "Usage: $0 [--values <values-file>] [--values <another-values-file>]"
    echo ""
    echo "Bootstraps ArgoCD by pre-installing CRDs and deploying the Helm chart."
    echo ""
    echo "Options:"
    echo "  --values <file>   Additional Helm values file (can be specified multiple times)"
    echo "  -h, --help        Show this help message"
    exit 0
    ;;
  *)
    echo "ERROR: Unknown argument: $1"
    echo "Run '$0 --help' for usage information."
    exit 1
    ;;
  esac
done

# ---- Resolve chart directory relative to script location --------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHART_PATH="${REPO_ROOT}/${CHART_DIR}"

if [[ ! -f "${CHART_PATH}/Chart.yaml" ]]; then
  echo "ERROR: Chart.yaml not found at ${CHART_PATH}/Chart.yaml"
  exit 1
fi

# ---- Step 2: Pre-install ArgoCD CRDs ---------------------------------------
echo ""
echo "==> Applying ArgoCD v${ARGOCD_VERSION} CRDs (server-side apply)..."
for crd_file in "${CRD_FILES[@]}"; do
  crd_url="${CRD_BASE_URL}/${crd_file}"
  echo "    Applying ${crd_file}..."
  kubectl apply --server-side --force-conflicts -f "${crd_url}"
done
echo "    CRDs applied successfully."

# ---- Step 3: Update Helm dependencies --------------------------------------
echo ""
echo "==> Updating Helm chart dependencies..."
helm dependency update "${CHART_PATH}"

# ---- Step 4: Install / upgrade the Helm release ----------------------------
echo ""
echo "==> Installing/upgrading Helm release '${RELEASE_NAME}' in namespace '${NAMESPACE}'..."
helm upgrade --install "${RELEASE_NAME}" "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  "${EXTRA_VALUES_ARGS[@]+"${EXTRA_VALUES_ARGS[@]}"}"

echo ""
echo "==> ArgoCD bootstrap complete."
echo "    Release:   ${RELEASE_NAME}"
echo "    Namespace: ${NAMESPACE}"
echo "    Version:   v${ARGOCD_VERSION}"
