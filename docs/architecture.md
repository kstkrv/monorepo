# Architecture

## Overview

This is a Gleam fullstack monorepo. Gleam compiles to either Erlang (backend) or JavaScript (frontend) — a single package cannot target both, so the app is split into separate packages under `apps/`.

## Package Dependency Graph

```
server  ──→  shared  ←──  client
  ↓                         ↓
mist                      lustre
(HTTP server)           (UI framework)

orchestrator (standalone)    e2e (standalone)
  ↓                           ↓
OTP actors + httpc          httpc
```

- **shared** is a local path dependency of both server and client
- **orchestrator** and **e2e** are independent packages with no cross-dependencies

## Compilation Targets

| Package | Target | Runtime | Output |
|---------|--------|---------|--------|
| server | Erlang | BEAM VM | OTP release |
| client | JavaScript | Browser | ESM bundle |
| shared | Erlang (dual-use) | Both | Used by server (Erlang) and client (JS) |
| orchestrator | Erlang | BEAM VM | OTP actors |
| e2e | Erlang | BEAM VM | Test runner binary |

## Packages

### server (`apps/server/`)

HTTP server built on [mist](https://hexdocs.pm/mist/). Serves two routes:

- `GET /` — HTML shell with app mount point (from `shared.html_template`)
- `GET /client.mjs` — Bundled client JavaScript

Reads the client JS bundle from the filesystem at the path specified by `CLIENT_JS_PATH` env var. Uses Erlang FFI (`server_ffi.erl`) for file I/O.

### client (`apps/client/`)

Frontend SPA built on [lustre](https://hexdocs.pm/lustre/). Compiles to JavaScript ESM, then bundled with esbuild during Docker build. Mounts to `#app` in the HTML shell served by the server.

### shared (`apps/shared/`)

Shared types and logic consumed by both server and client:

- `Route` type — routing enum (`ClientJs | Html`)
- `route/1` — path segment matching
- `content_type/1` — MIME type mapping
- `html_template/0` — HTML shell template

### orchestrator (`apps/orchestrator/`)

LLM agent orchestrator framework. BEAM-native, uses OTP actors for concurrent agent execution.

- **Provider pattern** — record-of-functions abstraction for LLM backends. Ships with an OpenAI-compatible provider supporting OpenRouter and Ollama.
- **Agent loop** — call LLM → check stop reason → execute tools if requested → repeat. Respects `max_iterations` to prevent runaway loops.
- **Tool system** — tools defined as records with name, description, JSON schema parameters, and an execute function.

### e2e (`apps/e2e/`)

Post-deployment integration test runner. Sends HTTP requests to the deployed app and validates responses. Has its own Dockerfile and runs as a Kubernetes Job via Helm hook.

## Environment Variables

| Variable | Default | Used By | Purpose |
|----------|---------|---------|---------|
| `CLIENT_JS_PATH` | `../client/build/dev/javascript/client/client.mjs` | server | Path to bundled client JS |
| `E2E_BASE_URL` | `http://monorepo:8080` | e2e | Target URL for integration tests |
