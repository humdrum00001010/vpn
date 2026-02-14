# Monorepo Structure

This repository is a monorepo containing multiple standalone projects.

## Rules

1. Each project owns its own toolchain files.
2. Rust package files for the packet project live in `bpf/` (`Cargo.toml`, `Cargo.lock`).
3. Zed Rust discovery from repo root uses `.zed/settings.json` with rust-analyzer `linkedProjects`.

## Current projects

1. `bpf`: macOS packet capture and local tunneling utility written in Rust.
2. `coordinator`: Phoenix rendezvous server (UDP 3478 + WebSocket API + Presence).
3. `clients/rendezvous-client`: Rust client used by Docker tests.
4. `natlab`: privileged Linux Docker harness that emulates NAT using `ip netns` + `iptables`.

## Zed Language Servers

- Rust: root Zed config points rust-analyzer at `bpf/Cargo.toml` via `.zed/settings.json`.
- Elixir: Zed runs language servers from the worktree root. In this repo, the Mix project lives in `coordinator/`,
  so `.zed/settings.json` points ElixirLS at `tools/zed-elixir-ls.sh` which `cd`s into `coordinator/` before launching.
