#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Teardown Everything
#
# Removes all Applications, AppProjects, the ArgoCD Helm release, CRDs, and
# the argocd namespace. This is a full reset.
###############################################################################

NAMESPACE="argocd"
RELEASE_NAME="argocd"
LABEL="app.kubernetes.io/managed-by=argocd-autopilot"

echo "==> Full teardown: removing all apps, ArgoCD, and CRDs."
echo ""

# ---- Step 1: Strip finalizers from ALL Applications -------------------------
echo "==> Stripping finalizers from all Applications..."
apps=$(kubectl get applications.argoproj.io -n "${NAMESPACE}" -o name 2>/dev/null || true)
for app in ${apps}; do
  echo "    ${app}"
  kubectl patch "${app}" -n "${NAMESPACE}" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
done

# ---- Step 2: Delete all Applications ----------------------------------------
echo ""
echo "==> Deleting all Applications..."
if [[ -n "${apps}" ]]; then
  kubectl delete applications.argoproj.io -n "${NAMESPACE}" --all --wait=false
else
  echo "    No Applications found."
fi

# ---- Step 3: Delete all AppProjects (except 'default') ----------------------
echo ""
echo "==> Deleting all AppProjects..."
kubectl delete appprojects.argoproj.io -n "${NAMESPACE}" -l "${LABEL}" --wait=false 2>/dev/null || true

# ---- Step 4: Uninstall the Helm release -------------------------------------
echo ""
echo "==> Uninstalling Helm release '${RELEASE_NAME}'..."
if helm status "${RELEASE_NAME}" -n "${NAMESPACE}" &>/dev/null; then
  helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}" --wait=false
else
  echo "    Helm release '${RELEASE_NAME}' not found, skipping."
fi

# ---- Step 5: Delete ArgoCD CRDs ---------------------------------------------
echo ""
echo "==> Deleting ArgoCD CRDs..."
for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
  if kubectl get crd "${crd}" &>/dev/null; then
    echo "    Deleting ${crd}"
    kubectl delete crd "${crd}" --wait=false
  fi
done

# ---- Step 6: Delete namespaces ----------------------------------------------
echo ""
echo "==> Deleting namespaces..."
for ns in "${NAMESPACE}" dev staging prod; do
  if kubectl get namespace "${ns}" &>/dev/null; then
    echo "    Deleting namespace: ${ns}"
    kubectl delete namespace "${ns}" --wait=false
  fi
done

echo ""
echo "==> Full teardown complete."
