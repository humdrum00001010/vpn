# NAT Lab (Linux Only)

This builds a single Docker image that:

- Starts the Phoenix coordinator (HTTP/WebSocket on `4000`, UDP on `3478`)
- Creates two separate client network namespaces behind two NAT namespaces (iptables MASQUERADE)
- Runs two Rust rendezvous clients from behind those NATs
- Verifies each client learns the other client's observed UDP endpoint
- Verifies the clients can exchange a direct UDP ping/pong (data plane)

This requires a privileged container so it can run `ip netns` and `iptables`.

Note: this NAT setup is intentionally permissive (single-host NAT with a DNAT rule that forwards inbound UDP to that host).
It is closer to a full-cone NAT than a symmetric NAT, so it makes UDP hole punching feasible for this first test.

## Commands

```bash
cd /Users/phihu/Desktop/vpn
docker build -t vpn-natlab -f natlab/Dockerfile .
docker run --rm --privileged vpn-natlab
```

## Heartbeats

To keep NAT bindings alive for a bit after the initial punch succeeds:

```bash
docker run --rm --privileged -e STAY_SECS=30 -e KEEPALIVE_SECS=15 vpn-natlab
```
