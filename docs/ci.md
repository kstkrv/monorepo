# CI/CD

## GitHub Actions

The CI pipeline is defined in `.github/workflows/ci.yml`.

### Triggers

- Push to `main`
- Pull request against `main`

### Build & Test Job

Runs on `ubuntu-latest` with:

- OTP 27
- Gleam 1.14.0
- Rebar3 3

Uses a matrix strategy to build and test each package in parallel:

| Package | Directory |
|---------|-----------|
| shared | `apps/shared` |
| server | `apps/server` |
| client | `apps/client` |
| orchestrator | `apps/orchestrator` |

For each package, the pipeline runs:

```sh
gleam build
gleam test
```

### What's Not in CI

- **e2e tests** — these run as a Kubernetes Job post-deployment (via Helm hook), not in the CI pipeline
- **Docker build** — not currently part of the CI pipeline
- **Deployment** — handled by ArgoCD watching the main branch

## Local CI

You can run the CI pipeline locally using [act](https://github.com/nektos/act):

```sh
act push
```
