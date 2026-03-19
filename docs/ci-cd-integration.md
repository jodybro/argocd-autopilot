# CI/CD Integration Guide

This document describes how to integrate GitHub Actions with this ArgoCD Autopilot repository for a full GitOps CI/CD pipeline.

## Architecture

```
App Source Repo (CI)          This GitOps Repo (CD)           Kubernetes Cluster
┌─────────────────┐          ┌────────────────────┐          ┌──────────────────┐
│ Code change      │          │ values-dev.yaml    │          │                  │
│ → Build image    │──────▶   │ image.tag: "v1.2"  │──────▶   │ ArgoCD detects   │
│ → Push to        │ update   │                    │ auto-    │ change and syncs  │
│   registry       │ tag      │ Commit & push      │ sync     │ new manifests     │
└─────────────────┘          └────────────────────┘          └──────────────────┘
```

- **CI** (in the app's source repo): Builds and pushes container images
- **CD** (in this repo): Updates image tags in values files; ArgoCD handles the rest

## Workflow 1: Image Tag Update

Triggered by the app's CI pipeline after a new image is pushed. Updates the image tag in the target environment's values file.

```yaml
# .github/workflows/update-image-tag.yaml
name: Update Image Tag

on:
  workflow_dispatch:
    inputs:
      app:
        description: "Application name (chart directory name)"
        required: true
        type: string
      environment:
        description: "Target environment"
        required: true
        type: choice
        options: [dev, staging, prod]
      tag:
        description: "New image tag"
        required: true
        type: string

  # Also accept repository_dispatch from external CI
  repository_dispatch:
    types: [update-image]

jobs:
  update-tag:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set variables
        id: vars
        run: |
          if [ "${{ github.event_name }}" = "repository_dispatch" ]; then
            echo "app=${{ github.event.client_payload.app }}" >> "$GITHUB_OUTPUT"
            echo "env=${{ github.event.client_payload.environment }}" >> "$GITHUB_OUTPUT"
            echo "tag=${{ github.event.client_payload.tag }}" >> "$GITHUB_OUTPUT"
          else
            echo "app=${{ inputs.app }}" >> "$GITHUB_OUTPUT"
            echo "env=${{ inputs.environment }}" >> "$GITHUB_OUTPUT"
            echo "tag=${{ inputs.tag }}" >> "$GITHUB_OUTPUT"
          fi

      - name: Update image tag
        uses: mikefarah/yq@master
        with:
          cmd: |
            yq -i '.image.tag = "${{ steps.vars.outputs.tag }}"' \
              charts/${{ steps.vars.outputs.app }}/values-${{ steps.vars.outputs.env }}.yaml

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add charts/${{ steps.vars.outputs.app }}/values-${{ steps.vars.outputs.env }}.yaml
          git commit -m "chore(${{ steps.vars.outputs.app }}): update image tag to ${{ steps.vars.outputs.tag }} in ${{ steps.vars.outputs.env }}"
          git push
```

## Workflow 2: PR Validation

Runs on every pull request to validate Helm charts and manifests.

```yaml
# .github/workflows/validate.yaml
name: Validate

on:
  pull_request:
    branches: [main]

jobs:
  lint-and-validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v4

      - name: Lint demo-app chart (all environments)
        run: |
          for env in dev staging prod; do
            echo "--- Linting values-${env}.yaml ---"
            helm lint charts/demo-app/ \
              -f charts/demo-app/values.yaml \
              -f charts/demo-app/values-${env}.yaml
          done

      - name: Template demo-app chart (all environments)
        run: |
          for env in dev staging prod; do
            echo "--- Rendering values-${env}.yaml ---"
            helm template demo-app charts/demo-app/ \
              -f charts/demo-app/values.yaml \
              -f charts/demo-app/values-${env}.yaml \
              --output-dir /tmp/rendered-${env}
          done

      - name: Install kubeconform
        run: |
          curl -sL https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz \
            | tar xz -C /usr/local/bin

      - name: Validate rendered manifests
        run: |
          for env in dev staging prod; do
            echo "--- Validating ${env} manifests ---"
            kubeconform -strict -summary /tmp/rendered-${env}/demo-app/templates/*.yaml
          done

      - name: Lint bootstrap chart
        run: |
          helm dependency update bootstrap/
          helm lint bootstrap/

      - name: Validate ArgoCD Application YAMLs
        run: |
          for dir in apps/dev apps/staging apps/prod; do
            echo "--- Validating ${dir} ---"
            kubeconform -strict -summary \
              -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
              ${dir}/*.yaml
          done
```

## Workflow 3: Environment Promotion

Promotes an application from one environment to the next by copying the image tag.

```yaml
# .github/workflows/promote.yaml
name: Promote

on:
  workflow_dispatch:
    inputs:
      app:
        description: "Application name"
        required: true
        type: string
      from:
        description: "Source environment"
        required: true
        type: choice
        options: [dev, staging]
      to:
        description: "Target environment"
        required: true
        type: choice
        options: [staging, prod]

jobs:
  promote:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Read source image tag
        id: source
        uses: mikefarah/yq@master
        with:
          cmd: yq '.image.tag' charts/${{ inputs.app }}/values-${{ inputs.from }}.yaml

      - name: Update target image tag
        uses: mikefarah/yq@master
        with:
          cmd: |
            yq -i '.image.tag = "${{ steps.source.outputs.result }}"' \
              charts/${{ inputs.app }}/values-${{ inputs.to }}.yaml

      - name: Create PR for production / direct commit for staging
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

          TAG="${{ steps.source.outputs.result }}"
          APP="${{ inputs.app }}"
          FROM="${{ inputs.from }}"
          TO="${{ inputs.to }}"

          git add "charts/${APP}/values-${TO}.yaml"
          git commit -m "chore(${APP}): promote ${TAG} from ${FROM} to ${TO}"

          if [ "${TO}" = "prod" ]; then
            BRANCH="promote/${APP}-${TAG}-to-prod"
            git checkout -b "${BRANCH}"
            git push -u origin "${BRANCH}"
            gh pr create \
              --title "Promote ${APP} ${TAG} to production" \
              --body "Promotes image tag \`${TAG}\` from **${FROM}** to **${TO}**." \
              --base main
          else
            git push
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Required GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `GITHUB_TOKEN` | Built-in, used for creating PRs and pushing commits |

For optional ArgoCD diff in PR validation:

| Secret | Purpose |
|--------|---------|
| `ARGOCD_SERVER` | ArgoCD server URL |
| `ARGOCD_AUTH_TOKEN` | ArgoCD API token for `argocd app diff` |

## Branch Strategy

- `main` is the single source of truth; ArgoCD watches this branch (`targetRevision: main`)
- All changes to production go through pull requests
- Dev/staging changes can be direct commits (via CI automation) or PRs
- Enable branch protection on `main` with required PR reviews for production safety
