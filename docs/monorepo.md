# Monorepo Structure

This repository is a monorepo containing multiple standalone projects.

## Rules

1. Each project owns its own toolchain files.
2. For Rust projects, `Cargo.toml` and `Cargo.lock` must live in the project directory.
3. The repository root should not contain language-specific manifests unless intentionally introducing a shared root-level project.

## Current projects

1. `bpf`: macOS packet capture and local tunneling utility written in Rust.
