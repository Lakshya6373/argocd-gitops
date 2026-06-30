# ArgoCD GitOps — Industry-Standard Reference Project

A structured reference implementation of GitOps using Argo CD, demonstrating
production-grade patterns for multi-environment Kubernetes application delivery.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Key Concepts](#key-concepts)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Environments](#environments)
- [Patterns Implemented](#patterns-implemented)
- [Configuration Reference](#configuration-reference)
- [Workflows](#workflows)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview

This project is a learning reference for production-grade Argo CD workflows. It
covers the core patterns used in enterprise GitOps pipelines as of 2026, including:

- App of Apps bootstrap pattern
- ApplicationSet for multi-environment automation
- Kustomize overlays for environment-specific configuration
- Helm chart with per-environment value files
- RBAC isolation through Argo CD Projects
- Sync waves for ordered resource deployment
- Sync windows for change-freeze enforcement
- Notification hooks for Slack and email

The repository simulates a real-world GitOps monorepo that a platform or SRE team
would own, managing application delivery across development, staging, and production
Kubernetes clusters.

> This repo contains only the **desired-state manifests** (GitOps side).
> Application source code lives in a separate repository. The image built from that
> repo is referenced here by tag.

---

## Architecture

```
Developer Push
      |
      v
Git Repository  <---  Argo CD Image Updater (optional)
      |
      v
Argo CD Controller  (watches for drift every 3 minutes, or on webhook)
      |
  +---+---+
  |   |   |
 dev  stg prod
  |   |   |
  K8s K8s K8s Clusters
```

**Reconciliation flow:**

1. A developer merges a change (manifest update or image tag bump) to `main`.
2. Argo CD detects drift between the Git desired state and the live cluster state.
3. Argo CD applies the delta using `kubectl apply` (server-side apply).
4. Health checks run; status is reported in the UI and via notifications.
5. If `selfHeal` is enabled, any out-of-band manual edits to the cluster are
   automatically reverted back to the Git state.

---

## Key Concepts

### App of Apps

A root Argo CD `Application` that points to a folder of other `Application`
manifests. Bootstrapping the cluster requires a single `kubectl apply`. All child
applications are subsequently managed by Argo CD itself.

### ApplicationSet

A controller resource (`argoproj.io/v1alpha1/ApplicationSet`) that generates
multiple Argo CD `Application` objects from a single template. Supports generators
such as List, Git Directory, Matrix, and Cluster, which makes scaling to dozens of
services and environments straightforward.

### Kustomize Overlays

A base layer of Kubernetes manifests shared across all environments, combined with
per-environment `kustomization.yaml` patch files. No duplication of the full
manifest; only the fields that differ are patched.

### Argo CD Projects

Logical groupings (`AppProject`) that enforce:
- Allowed source repositories
- Allowed destination clusters and namespaces
- Allowed and denied Kubernetes resource kinds
- RBAC roles scoped to the project

### Sync Waves

The `argocd.argoproj.io/sync-wave` annotation controls the order in which
resources are applied within a single sync operation. Lower wave numbers are applied
first and must reach a healthy state before the next wave begins.

| Wave | Resources Applied                      |
|------|----------------------------------------|
| -1   | Namespaces, CRDs                       |
|  0   | ConfigMaps, Secrets, ServiceAccounts   |
|  1   | Deployments, Services, Ingresses       |
|  2   | Post-deploy Jobs, smoke-test hooks     |

### Sync Windows

Time-based policies attached to Argo CD Projects that define when automated or
manual syncs are allowed. Used to enforce change-freeze periods in staging and
production.

---

## Project Structure

```
argocd-gitops/
|
├── bootstrap/                        # One-time cluster bootstrap resources
│   ├── argocd-namespace.yaml         # Namespace for Argo CD itself
│   ├── root-app.yaml                 # App of Apps root application
│   └── projects/
│       ├── platform-project.yaml     # Project for cluster-level infra
│       └── team-alpha-project.yaml   # Project for application teams
│
├── apps/                             # Per-environment ArgoCD Application manifests
│   ├── dev/
│   │   └── sample-app.yaml
│   ├── staging/
│   │   └── sample-app.yaml
│   └── prod/
│       └── sample-app.yaml
│
├── applicationsets/                  # ApplicationSet manifests (preferred at scale)
│   └── sample-app-appset.yaml
│
├── manifests/                        # Kubernetes manifests managed with Kustomize
│   └── sample-app/
│       ├── base/                     # Shared base resources
│       │   ├── kustomization.yaml
│       │   ├── namespace.yaml
│       │   ├── serviceaccount.yaml
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── hpa.yaml
│       └── overlays/                 # Per-environment patches
│           ├── dev/
│           │   ├── kustomization.yaml
│           │   └── patch-deployment.yaml
│           ├── staging/
│           │   ├── kustomization.yaml
│           │   └── patch-deployment.yaml
│           └── prod/
│               ├── kustomization.yaml
│               ├── patch-deployment.yaml
│               └── patch-hpa.yaml
│
├── charts/                           # Helm charts (alternative to Kustomize)
│   └── sample-app/
│       ├── Chart.yaml
│       ├── values.yaml               # Default values (lowest priority)
│       ├── values-dev.yaml
│       ├── values-staging.yaml
│       ├── values-prod.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── NOTES.txt
│           ├── serviceaccount.yaml
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           └── hpa.yaml
│
├── config/                           # Argo CD server configuration
│   ├── argocd-cm.yaml
│   ├── argocd-rbac-cm.yaml
│   └── notifications/
│       └── argocd-notifications-cm.yaml
│
└── scripts/
    ├── bootstrap.sh                  # Full cluster bootstrap
    └── cleanup.sh                    # Teardown and reset
```

---

## Prerequisites

| Tool         | Minimum Version | Purpose                              |
|--------------|-----------------|--------------------------------------|
| kubectl      | 1.28            | Cluster interaction                  |
| argocd CLI   | 2.12            | Application management from terminal |
| helm         | 3.14            | Helm chart rendering and deployment  |
| kustomize    | 5.4             | Kustomize overlay rendering          |
| git          | 2.40            | Repository operations                |

**Kubernetes cluster options (local):**

- [kind](https://kind.sigs.k8s.io/) — Kubernetes in Docker, fast and lightweight
- [k3d](https://k3d.io/) — k3s in Docker, suitable for multi-node simulations
- [minikube](https://minikube.sigs.k8s.io/) — Full-featured local cluster

---

## Getting Started

### 1. Fork and Clone

```bash
git clone https://github.com/Lakshya6373/argocd-gitops.git
cd argocd-gitops
```

### 2. Install Argo CD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=Available \
  deployment/argocd-server \
  -n argocd \
  --timeout=180s
```

### 3. Access the Argo CD UI

```bash
# Open a port-forward in the background
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Retrieve the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Open `https://localhost:8080` in a browser. Accept the self-signed certificate warning.

### 4. Log In via the CLI

```bash
argocd login localhost:8080 \
  --username admin \
  --password <INITIAL_PASSWORD> \
  --insecure
```

> After first login, change the admin password:
> `argocd account update-password`

### 5. Replace Placeholder Repository URL

Update all YAML files so they reference your fork:

```bash
# Linux / macOS
find . -type f -name "*.yaml" \
  | xargs sed -i 's|Lakshya6373|your-actual-username|g'

# Windows PowerShell
Get-ChildItem -Recurse -Filter "*.yaml" | ForEach-Object {
    (Get-Content $_.FullName) `
      -replace 'Lakshya6373', 'your-actual-username' `
    | Set-Content $_.FullName
}
```

### 6. Bootstrap the Cluster

```bash
bash scripts/bootstrap.sh
```

Or step-by-step:

```bash
# 1. Create Argo CD Projects (defines RBAC and repo restrictions)
kubectl apply -f bootstrap/projects/

# 2. Apply the root App of Apps (Argo CD will reconcile everything else)
kubectl apply -f bootstrap/root-app.yaml
```

Argo CD now manages itself and all child applications. Watch the sync:

```bash
argocd app list
argocd app get root-app
```

---

## Environments

| Environment | Namespace            | Replicas | Auto-Sync | Sync Window           |
|-------------|----------------------|----------|-----------|------------------------|
| dev         | sample-app-dev       | 1        | Yes       | Always                 |
| staging     | sample-app-staging   | 2        | Yes       | Mon-Fri 08:00-18:00 UTC|
| prod        | sample-app-prod      | 3        | No        | Sat 02:00-04:00 UTC    |

Production uses **manual sync** to require an explicit approval step before changes
are applied. Staging auto-syncs within business hours. Dev auto-syncs at any time.

---

## Patterns Implemented

### App of Apps (bootstrap/)

- A single root `Application` (`bootstrap/root-app.yaml`) points to `apps/<env>/`
- Each YAML in `apps/<env>/` defines a child `Application`
- Applying the root app bootstraps the entire environment

### ApplicationSet (applicationsets/)

- `sample-app-appset.yaml` uses a **List generator** to create one Application per
  environment from a shared template
- Demonstrates how to replace three separate Application YAMLs with one manifest
- At scale, use the **Git Directory generator** to auto-discover new services

### Kustomize Base + Overlays (manifests/)

- `base/` contains the canonical Deployment, Service, HPA, and ServiceAccount
- Each overlay applies only the fields that change per environment:
  - Image tag
  - Replica count
  - Resource limits
  - Environment variables

### Helm with Multiple Value Files (charts/)

- `values.yaml` holds production-safe defaults
- `values-dev.yaml`, `values-staging.yaml`, `values-prod.yaml` hold overrides
- ArgoCD Application references chart path + environment-specific valueFile

### Sync Waves

- Namespace annotated with `sync-wave: "-1"`
- ServiceAccount and ConfigMap with `sync-wave: "0"`
- Deployment and Service with `sync-wave: "1"`

### Argo CD Projects for RBAC

- `platform-project.yaml` — used by the root App of Apps; full cluster access
- `team-alpha-project.yaml` — scoped to specific source repos, destination
  namespaces, and resource kinds; safe for developers with limited access

### Sync Windows (production)

Defined inside `team-alpha-project.yaml`:
- **Allow window:** Saturday 02:00–04:00 UTC (maintenance window)
- **Deny window:** Friday 16:00 – Monday 08:00 UTC (weekend freeze)

---

## Configuration Reference

### Application Spec Fields

| Field                                    | Description                                         |
|------------------------------------------|-----------------------------------------------------|
| `spec.source.repoURL`                    | Git repo URL containing desired state               |
| `spec.source.targetRevision`             | Branch, tag, or commit SHA to track                 |
| `spec.source.path`                       | Path inside the repo to the manifests               |
| `spec.source.helm.valueFiles`            | Additional Helm value files to layer                |
| `spec.destination.server`                | Kubernetes API server URL                           |
| `spec.destination.namespace`             | Target namespace                                    |
| `spec.syncPolicy.automated.prune`        | Delete resources removed from Git                   |
| `spec.syncPolicy.automated.selfHeal`     | Revert manual cluster edits back to Git state       |
| `spec.syncPolicy.syncOptions`            | List of sync behavior flags (see below)             |
| `spec.ignoreDifferences`                 | Fields to ignore during drift detection             |

### Common Sync Options

| Option                        | Effect                                                      |
|-------------------------------|-------------------------------------------------------------|
| `CreateNamespace=true`        | Creates destination namespace if it does not exist          |
| `ServerSideApply=true`        | Uses server-side apply (required for CRDs and large objects)|
| `ApplyOutOfSyncOnly=true`     | Only patches resources that differ from Git                 |
| `RespectIgnoreDifferences=true` | Applies `ignoreDifferences` rules at sync time            |
| `PruneLast=true`              | Deletes removed resources after all others are healthy      |
| `Replace=true`                | Uses `kubectl replace` instead of `apply` (use sparingly)  |

---

## Workflows

### Deploying a New Image Version

1. Build and push the new image to your container registry.
2. Update the image tag in:
   - Kustomize: `manifests/sample-app/overlays/<env>/kustomization.yaml`
   - Helm: `charts/sample-app/values-<env>.yaml`
3. Commit and push to `main`.
4. Argo CD detects the change and begins reconciliation.
5. Monitor:
   ```bash
   argocd app get sample-app-dev
   argocd app wait sample-app-dev --health
   ```

### Promoting from Dev to Staging

1. Confirm dev is healthy:
   ```bash
   argocd app wait sample-app-dev --health --timeout 120
   ```
2. Update the image tag in the staging overlay or values file.
3. Push the change and let Argo CD reconcile.

### Manual Sync (Production)

Production auto-sync is disabled. After updating the prod manifest:

```bash
argocd app sync sample-app-prod --prune
argocd app wait sample-app-prod --health --timeout 300
```

### Rolling Back

```bash
# Show sync history
argocd app history sample-app-prod

# Roll back to a previous revision
argocd app rollback sample-app-prod <REVISION_ID>
```

### Inspecting Drift

```bash
# Show diff between Git desired state and live cluster state
argocd app diff sample-app-dev

# Show resource tree
argocd app resources sample-app-dev
```

---

## Troubleshooting

| Symptom                         | Likely Cause                               | Resolution                                                        |
|---------------------------------|--------------------------------------------|-------------------------------------------------------------------|
| App stuck in `OutOfSync`        | Sync policy is manual                      | Run `argocd app sync <name>`                                      |
| `ComparisonError`               | CRD not installed or RBAC too restrictive  | Check `argocd app get <name>` events section                      |
| `SyncFailed`                    | Kubernetes API rejected a manifest         | Run `kubectl apply --dry-run=server -f <file>` to diagnose        |
| `Degraded` health               | Pod crash loop or failing readiness probe  | Run `kubectl logs -n <ns> <pod>` and `kubectl describe pod`       |
| Webhook not triggering sync     | Wrong URL or missing secret in GitHub      | Verify under Argo CD Settings > Repositories                      |
| `PermissionDenied` on sync      | Project RBAC too restrictive               | Review `AppProject` `destinations` and `sourceRepos` fields       |
| Helm chart values not applied   | Wrong `valueFiles` path                    | Paths in `valueFiles` are relative to the chart root              |

---

## Learning Path

If this is your first encounter with Argo CD, work through the concepts in this order:

1. **Install Argo CD locally** on a kind or k3d cluster using `scripts/bootstrap.sh`
2. **Understand the App of Apps** — read `bootstrap/root-app.yaml` and apply it
3. **Deploy the Kustomize path** — apply `apps/dev/sample-app.yaml` manually, then
   observe Argo CD reconcile `manifests/sample-app/overlays/dev/`
4. **Promote to staging** — update the staging image tag and observe the sync
5. **Switch to ApplicationSet** — replace the per-env apps with
   `applicationsets/sample-app-appset.yaml`
6. **Explore the Helm path** — create an Application that references `charts/sample-app`
   with `values-dev.yaml`
7. **Configure RBAC** — apply `config/argocd-rbac-cm.yaml` and verify that
   developer accounts cannot access the prod namespace
8. **Set up Notifications** — configure Slack or email in
   `config/notifications/argocd-notifications-cm.yaml`

---

## References

- [Argo CD Official Documentation](https://argo-cd.readthedocs.io/en/stable/)
- [ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Kustomize Reference](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [Helm Documentation](https://helm.sh/docs/)
- [OpenGitOps Principles](https://opengitops.dev/)
- [Argo CD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Argo CD Security Considerations](https://argo-cd.readthedocs.io/en/stable/operator-manual/security/)
- [Kubernetes SIG App Delivery](https://github.com/kubernetes-sigs/application)
