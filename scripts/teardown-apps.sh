#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Teardown Apps Only
#
# Removes all ArgoCD Applications and AppProjects managed by argocd-autopilot,
# leaving the ArgoCD instance itself running. Strips finalizers first to avoid
# cascading deletes hanging on already-removed child resources.
###############################################################################

NAMESPACE="argocd"
LABEL="app.kubernetes.io/managed-by=argocd-autopilot"

echo "==> Removing argocd-autopilot Applications and AppProjects..."
echo "    ArgoCD instance will be left running."
echo ""

# ---- Step 1: Remove finalizers from all managed Applications ----------------
echo "==> Stripping finalizers from managed Applications..."
apps=$(kubectl get applications.argoproj.io -n "${NAMESPACE}" -l "${LABEL}" -o name 2>/dev/null || true)
for app in ${apps}; do
  echo "    ${app}"
  kubectl patch "${app}" -n "${NAMESPACE}" --type merge -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
done

# ---- Step 2: Delete all managed Applications --------------------------------
echo ""
echo "==> Deleting managed Applications..."
if [[ -n "${apps}" ]]; then
  kubectl delete applications.argoproj.io -n "${NAMESPACE}" -l "${LABEL}" --wait=false
else
  echo "    No managed Applications found."
fi

# ---- Step 3: Delete all managed AppProjects ---------------------------------
echo ""
echo "==> Deleting managed AppProjects..."
projects=$(kubectl get appprojects.argoproj.io -n "${NAMESPACE}" -l "${LABEL}" -o name 2>/dev/null || true)
if [[ -n "${projects}" ]]; then
  kubectl delete appprojects.argoproj.io -n "${NAMESPACE}" -l "${LABEL}" --wait=false
else
  echo "    No managed AppProjects found."
fi

# ---- Step 4: Delete workload namespaces -------------------------------------
echo ""
echo "==> Deleting workload namespaces (dev, staging, prod)..."
for ns in dev staging prod; do
  if kubectl get namespace "${ns}" &>/dev/null; then
    echo "    Deleting namespace: ${ns}"
    kubectl delete namespace "${ns}" --wait=false
  fi
done

echo ""
echo "==> App teardown complete. ArgoCD is still running in namespace '${NAMESPACE}'."
