# vpn monorepo

This repository is organized as a monorepo so multiple networking projects can live side-by-side.

## Layout

- `bpf/`: Rust libpcap/BPF packet capture and TCP tunnel (macOS-focused).
- `coordinator/`: Elixir Phoenix rendezvous server (UDP 3478 + WebSocket API + Presence).
- `clients/rendezvous-client/`: Rust client used for Docker-based rendezvous tests.
- `docs/`: repository-level documentation.

## Project model

Rust project files stay inside `./bpf`.
Zed discovers the Rust project from repository root via `.zed/settings.json` with `rust-analyzer` `linkedProjects`.

- Project: `bpf/Cargo.toml`
- Project: `bpf/Cargo.lock`
- Editor config: `.zed/settings.json`
- ElixirLS wrapper: `tools/zed-elixir-ls.sh` (runs ElixirLS from `coordinator/` so go-to-definition works in a monorepo)

## Running the BPF project

```bash
cd bpf
cargo build
cargo test
sudo -E cargo run
```

## Running Rendezvous (Docker)

```bash
docker compose up --build --abort-on-container-exit --exit-code-from client_a
```

## NAT Lab (Privileged Docker, Linux Only)

```bash
docker build -t vpn-natlab -f natlab/Dockerfile .
docker run --rm --privileged vpn-natlab
```

Keep NAT bindings alive for a while after punching:

```bash
docker run --rm --privileged -e STAY_SECS=30 -e KEEPALIVE_SECS=15 vpn-natlab
```
