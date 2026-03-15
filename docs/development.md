# Development

## Prerequisites

- [Gleam](https://gleam.run/getting-started/installing/) v1.14.0+
- [Erlang/OTP](https://www.erlang.org/) 27+
- [Docker](https://docs.docker.com/get-docker/) (for containerized builds)

## Building

Each package builds independently from its own directory:

```sh
cd apps/shared && gleam build
cd apps/server && gleam build
cd apps/client && gleam build
cd apps/orchestrator && gleam build
```

There is no root-level build command. Shared is a local dependency of server and client, so building those will also compile shared.

## Testing

```sh
cd apps/shared && gleam test
cd apps/server && gleam test
cd apps/client && gleam test
cd apps/orchestrator && gleam test
```

The orchestrator also has manual e2e tests that require a running Ollama instance:

```sh
cd apps/orchestrator && gleam run -m e2e_test
```

## Running Locally

### Directly with Gleam

```sh
cd apps/server && gleam run
```

The server starts on port 8080. In dev mode, it reads the client JS from the relative build path (`../client/build/dev/javascript/client/client.mjs`), so build the client first.

### With Docker Compose

```sh
docker compose up --build
```

Builds the multi-stage Dockerfile and runs the server on port 8080. This bundles the client JS with esbuild automatically.

## Adding Dependencies

```sh
cd apps/<package> && gleam add <package-name>
```

Dependencies are declared in each package's `gleam.toml` and locked in `manifest.toml`.

## Project Layout

```
apps/
├── server/        # Gleam → Erlang backend
├── client/        # Gleam → JavaScript frontend
├── shared/        # Shared types (local dep of server + client)
├── orchestrator/  # LLM agent framework (standalone)
└── e2e/           # Integration test runner (standalone)
infra/
├── helm/          # Kubernetes Helm chart
└── argocd/        # ArgoCD GitOps config
docs/              # Documentation
```
