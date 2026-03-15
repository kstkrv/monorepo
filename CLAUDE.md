trigger

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Gleam fullstack monorepo with infrastructure code. Gleam compiles to Erlang (backend) or JavaScript (frontend) — a single package cannot target both, so the app is split into separate packages.

## Structure

- `apps/server/` — Backend HTTP server (Gleam → Erlang, uses mist on port 8080)
- `apps/client/` — Frontend SPA (Gleam → JavaScript, uses lustre)
- `apps/shared/` — Shared types and logic, local dependency of server and client
- `apps/orchestrator/` — LLM agent orchestrator framework (Gleam → Erlang, OTP actors)
- `apps/e2e/` — End-to-end integration test runner (Gleam → Erlang)
- `infra/helm/` — Helm chart for Kubernetes deployment
- `infra/argocd/` — ArgoCD GitOps application config
- `docs/` — Project documentation

## Build & Test

All Gleam commands run from within a package directory (e.g. `cd apps/server`):

```sh
gleam build          # compile
gleam test           # run tests
gleam run            # run the app (server)
gleam add <package>  # add a hex dependency
gleam clean          # remove build artifacts
```

There is no root-level build command — each package builds independently.

CI runs `gleam build && gleam test` for shared, server, client, and orchestrator on every push/PR to main.

## Architecture

- `shared` is a local path dependency of both `server` and `client` (configured in their `gleam.toml` files)
- `orchestrator` is a standalone package — uses OTP actors for concurrent agent execution, supports OpenAI-compatible providers (OpenRouter, Ollama) via a record-of-functions provider pattern
- `e2e` is a standalone test runner — runs as a Kubernetes Job post-deployment via Helm hook
- Gleam uses the Hex package manager; dependencies are declared in `gleam.toml` and locked in `manifest.toml`
- Tests live in `test/` within each package and use `gleeunit`

## Deployment

- Multi-stage Dockerfile builds shared → client (with esbuild) → server into a single container
- Helm chart in `infra/helm/monorepo/` with templates for namespace, deployment, service, ingress, and e2e test job
- ArgoCD watches main branch and auto-syncs with self-heal and prune enabled
- `docker compose up` for local development (builds and runs on port 8080)
