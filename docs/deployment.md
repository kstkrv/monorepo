# Deployment

## Docker Build

The root `Dockerfile` is a multi-stage build:

1. **Builder stage** — compiles shared and client (Gleam → JS), bundles client with esbuild, then compiles the server (Gleam → Erlang)
2. **Runtime stage** — copies compiled artifacts and runs the server with `gleam run`

The bundled client JS is placed at `/app/client.mjs` and referenced via the `CLIENT_JS_PATH` env var.

Base image: `ghcr.io/gleam-lang/gleam:v1.14.0-erlang-alpine`

## Helm Chart

Located in `infra/helm/monorepo/`. Deploys the following resources:

- **Namespace** — `monorepo`
- **Deployment** — single replica, port 8080, with liveness and readiness probes
- **Service** — ClusterIP on port 8080
- **Ingress** — disabled by default, configurable via `values.yaml`
- **E2E test Job** — Helm hook (`post-install`, `post-upgrade`) that runs integration tests

### Configuration

Key values in `values.yaml`:

```yaml
replicaCount: 1
namespace: monorepo
image:
  repository: ghcr.io/kstkrv/monorepo
  tag: latest
service:
  type: ClusterIP
  port: 8080
ingress:
  enabled: false
e2e:
  image:
    repository: ghcr.io/kstkrv/monorepo-e2e
    tag: latest
```

### E2E Test Job

The e2e app has its own Dockerfile (`apps/e2e/Dockerfile`) and runs as a Kubernetes Job after each deployment. It:

1. Waits for the app to become ready (10 retries, 3s interval)
2. Sends `GET /` and validates the response contains expected content
3. Exits with code 0 (success) or 1 (failure)

## ArgoCD

Config in `infra/argocd/application.yaml`. ArgoCD watches the `main` branch and auto-syncs the Helm chart to the cluster.

- **Source**: `infra/helm/monorepo` on `main` branch
- **Destination**: `monorepo` namespace on the current cluster
- **Sync policy**: automated with self-heal and prune enabled
- **Namespace creation**: automatic via `CreateNamespace=true`

### Deployment Flow

```
Push to main → ArgoCD detects change → Helm sync → Deployment updated → E2E Job runs
```
