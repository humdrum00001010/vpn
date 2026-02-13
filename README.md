# vpn monorepo

This repository is organized as a monorepo so multiple networking projects can live side-by-side.

## Layout

- `bpf/`: macOS Rust packet sniffer/tunnel project.
- `docs/`: repository-level documentation.

## Project model

Rust project files stay inside `./bpf`.
Zed discovers the Rust project from repository root via `.zed/settings.json` with `rust-analyzer` `linkedProjects`.

- Project: `bpf/Cargo.toml`
- Project: `bpf/Cargo.lock`
- Editor config: `.zed/settings.json`

## Running the BPF project

```bash
cd bpf
cargo build
cargo test
cargo run
```
