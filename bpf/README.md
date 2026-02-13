# macos-bpf-tunnel

Captures packets from a hard-coded macOS interface/IP and tunnels matching packets to local UDP port `4002`.

## Hard-coded config

- Interface: `en0`
- Monitored IP: `192.168.1.10`
- Tunnel target: `127.0.0.1:4002`

Edit `src/config.rs` to change these values.

## Prerequisites

1. macOS host.
2. Rust toolchain (`rustup`, `cargo`).
3. Elevated permissions for packet capture (run with `sudo`).

## Build and test

```bash
cd bpf
cargo test
cargo build
```

## Run

Start your local receiver first (UDP port `4002`), then:

```bash
cd bpf
sudo cargo run
```

The program applies the BPF filter `ip and host <MONITORED_IP>` and forwards matching raw packet bytes.
