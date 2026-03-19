# argocd-autopilot

GitOps deployment repository managed by ArgoCD using the app-of-apps pattern. All configuration is Helm-based.

## Prerequisites

- Kubernetes cluster (1.27+)
- [Helm](https://helm.sh/) (3.14+)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured for your cluster
- [ArgoCD CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) (optional, for manual operations)

## Quickstart

```bash
# 1. Clone and configure
git clone https://github.com/jodybro/argocd-autopilot.git
cd argocd-autopilot

# 2. Update the repo URL in bootstrap/values.yaml to match your fork
#    repoURL: https://github.com/<your-org>/argocd-autopilot.git

# 3. Fetch ArgoCD Helm chart dependency
helm dependency update bootstrap/

# 4. Install ArgoCD + bootstrap the app-of-apps
helm install argocd bootstrap/ -n argocd --create-namespace

# 5. Wait for ArgoCD to be ready
kubectl wait --for=condition=available deployment/argocd-argo-cd-server -n argocd --timeout=300s

# 6. Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# 7. Port-forward and access the UI
kubectl port-forward svc/argocd-argo-cd-server -n argocd 8080:443
# Open https://localhost:8080, login with admin/<password>
```

## Directory Structure

```
├── bootstrap/              # ArgoCD installation (Helm umbrella chart)
│   ├── Chart.yaml          # Depends on argo-cd Helm chart
│   ├── values.yaml         # ArgoCD config + repo URL
│   └── templates/          # Root app, AppProjects, env watchers
├── apps/                   # Per-environment ArgoCD Application definitions
│   ├── dev/
│   ├── staging/
│   └── prod/
├── charts/                 # Helm charts for workloads
│   └── demo-app/           # Example app with per-env values
└── docs/                   # Documentation
    └── ci-cd-integration.md
```

## How It Works

This repo uses the ArgoCD **app-of-apps** pattern:

1. **Bootstrap** (`helm install`) deploys ArgoCD and creates a root Application + AppProjects + environment watcher Applications
2. **Environment watchers** (`dev-apps`, `staging-apps`, `prod-apps`) each monitor their `apps/<env>/` directory
3. **App definitions** in `apps/<env>/` reference Helm charts in `charts/` with environment-specific values
4. ArgoCD renders each chart and deploys the resulting manifests into the target namespace

```
bootstrap (helm install)
  └── root-app (watches bootstrap/templates/ for AppProjects + env watchers)
        ├── dev-apps    → apps/dev/    → charts/demo-app + values-dev.yaml
        ├── staging-apps → apps/staging/ → charts/demo-app + values-staging.yaml
        └── prod-apps   → apps/prod/   → charts/demo-app + values-prod.yaml
```

## Environments

| Environment | Namespace | Auto-Sync | Replicas |
|-------------|-----------|-----------|----------|
| dev         | dev       | Yes       | 1        |
| staging     | staging   | Yes       | 2        |
| prod        | prod      | **No** (manual) | 3  |

Production requires manual sync via the ArgoCD UI or CLI as a safety gate.

## Adding a New Application

1. Create a Helm chart in `charts/<app-name>/` with `values.yaml` and per-env values files
2. Add an ArgoCD Application YAML to each `apps/<env>/` directory referencing the chart
3. Commit and push — ArgoCD auto-syncs (dev/staging) or shows OutOfSync (prod)

## Adding a New Environment

1. Create a new AppProject in `bootstrap/templates/<env>-appproject.yaml`
2. Create a new watcher Application in `bootstrap/templates/<env>-apps.yaml`
3. Create `apps/<env>/` directory with Application definitions
4. Add `values-<env>.yaml` to each chart in `charts/`
5. Upgrade the bootstrap: `helm upgrade argocd bootstrap/ -n argocd`

## CI/CD Integration

See [docs/ci-cd-integration.md](docs/ci-cd-integration.md) for GitHub Actions workflow examples.
