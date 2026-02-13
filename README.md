# vpn monorepo

This repository is organized as a monorepo so multiple networking projects can live side-by-side.

## Layout

- `bpf/`: macOS Rust packet sniffer/tunnel project.
- `docs/`: repository-level documentation.

## Project model

Each project is independent and keeps its own manifest and lockfile in its own directory.  
For Rust, `Cargo.toml` and `Cargo.lock` should stay inside `./bpf`.

## Running the BPF project

```bash
cd bpf
cargo build
cargo test
cargo run
```
