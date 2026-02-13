# macos-bpf-tunnel

Captures packets from a hard-coded macOS interface/IP and tunnels matching packets to local TCP port `4002`.

## Hard-coded config

- Preferred interface name: `veth0` (Linux)
- Fallback: if `veth0` is not present, select the interface which has `MONITORED_IP` assigned (useful on macOS)
- Monitored IP: `192.168.1.10`
- Tunnel target: `127.0.0.1:4002`

Edit `src/config.rs` to change these values.

## Prerequisites

1. macOS host.
2. Rust toolchain (`rustup`, `cargo`).
3. Elevated permissions for packet capture (run with `sudo` for live capture). Unit tests do not require root.

## Build and test

```bash
cd bpf
cargo test
cargo build
```

## Run

Start your local receiver first (TCP port `4002`), then:

```bash
cd bpf
sudo cargo run
```

The program applies the BPF filter `ip and host <MONITORED_IP>` and forwards matching raw packet bytes.

## Linux veth smoke test (requires root)

There is an ignored Linux-only integration test that creates `veth0`, assigns IPs, captures packets on it, and verifies a packet is tunneled to a TCP test server:

```bash
cd bpf
sudo -E cargo test --test linux_veth_smoke -- --ignored
```
