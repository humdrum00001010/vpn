# Monorepo Structure

This repository is a monorepo containing multiple standalone projects.

## Rules

1. Each project owns its own toolchain files.
2. Rust package files for the packet project live in `bpf/` (`Cargo.toml`, `Cargo.lock`).
3. Zed Rust discovery from repo root uses `.zed/settings.json` with rust-analyzer `linkedProjects`.

## Current projects

1. `bpf`: macOS packet capture and local tunneling utility written in Rust.
