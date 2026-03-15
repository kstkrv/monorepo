# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Gleam fullstack monorepo with infrastructure code. Gleam compiles to Erlang (backend) or JavaScript (frontend) — a single package cannot target both, so the app is split into three packages.

## Structure

- `apps/server/` — Backend (Gleam → Erlang, target: erlang)
- `apps/client/` — Frontend (Gleam → JavaScript, target: javascript)
- `apps/shared/` — Shared types and logic, used as a local dependency by both server and client
- `infra/` — Infrastructure code (Terraform, YAML)

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

## Architecture

- `shared` is a local path dependency of both `server` and `client` (configured in their `gleam.toml` files)
- Gleam uses the Hex package manager; dependencies are declared in `gleam.toml` and locked in `manifest.toml`
- Tests live in `test/` within each package and use `gleeunit`
