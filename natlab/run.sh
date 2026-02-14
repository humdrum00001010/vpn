#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  set +e
  if [[ -n "${COORD_PID:-}" ]]; then
    kill "${COORD_PID}" >/dev/null 2>&1 || true
    wait "${COORD_PID}" >/dev/null 2>&1 || true
  fi
  for ns in cliA natA cliB natB; do
    ip netns del "${ns}" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

cd /work/coordinator

export PORT="${PORT:-4000}"
export MIX_ENV="${MIX_ENV:-dev}"

# Try to set up a cone-like SNAT for UDP hole punching tests.
snat_postrouting() {
  local ns="$1"
  local wan_if="$2"
  local wan_ip="$3"
  if ip netns exec "${ns}" iptables -t nat -A POSTROUTING -o "${wan_if}" -j SNAT --to-source "${wan_ip}" --persistent 2>/dev/null; then
    return 0
  fi
  ip netns exec "${ns}" iptables -t nat -A POSTROUTING -o "${wan_if}" -j SNAT --to-source "${wan_ip}"
}

# Ensure Hex/Rebar are present even in a fresh runtime image.
mix local.hex --force >/dev/null
mix local.rebar --force >/dev/null

mix phx.server >/tmp/coordinator.log 2>&1 &
COORD_PID=$!

for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
  echo "coordinator failed to start; log:" >&2
  tail -n 200 /tmp/coordinator.log >&2 || true
  exit 1
fi

ip netns add natA
ip netns add cliA
ip netns add natB
ip netns add cliB

# Simulated "internet": a Linux bridge in the root namespace.
ip link add br_wan type bridge
ip addr add 100.64.0.1/24 dev br_wan
ip link set br_wan up

# natA WAN <-> root bridge
ip link add veth_natA_root type veth peer name veth_natA_wan
ip link set veth_natA_wan netns natA
ip link set veth_natA_root master br_wan
ip link set veth_natA_root up

ip netns exec natA ip link set lo up
ip netns exec natA ip addr add 100.64.0.2/24 dev veth_natA_wan
ip netns exec natA ip link set veth_natA_wan up
ip netns exec natA ip route add default via 100.64.0.1

# natA LAN <-> cliA
ip link add veth_natA_lan type veth peer name veth_cliA
ip link set veth_natA_lan netns natA
ip link set veth_cliA netns cliA
ip netns exec natA ip addr add 10.0.1.1/24 dev veth_natA_lan
ip netns exec natA ip link set veth_natA_lan up

ip netns exec cliA ip link set lo up
ip netns exec cliA ip addr add 10.0.1.2/24 dev veth_cliA
ip netns exec cliA ip link set veth_cliA up
ip netns exec cliA ip route add default via 10.0.1.1

# NAT rules for natA.
ip netns exec natA sysctl -w net.ipv4.ip_forward=1 >/dev/null
snat_postrouting natA veth_natA_wan 100.64.0.2
# Full-cone-ish inbound mapping for the single LAN host (cliA).
# Any inbound UDP to the NAT WAN IP is forwarded to 10.0.1.2 preserving the port.
ip netns exec natA iptables -t nat -A PREROUTING -i veth_natA_wan -p udp -j DNAT --to-destination 10.0.1.2
ip netns exec natA iptables -A FORWARD -i veth_natA_lan -o veth_natA_wan -j ACCEPT
ip netns exec natA iptables -A FORWARD -i veth_natA_wan -o veth_natA_lan -p udp -j ACCEPT
ip netns exec natA iptables -A FORWARD -i veth_natA_wan -o veth_natA_lan -m state --state ESTABLISHED,RELATED -j ACCEPT

# natB WAN <-> root bridge
ip link add veth_natB_root type veth peer name veth_natB_wan
ip link set veth_natB_wan netns natB
ip link set veth_natB_root master br_wan
ip link set veth_natB_root up

ip netns exec natB ip link set lo up
ip netns exec natB ip addr add 100.64.0.3/24 dev veth_natB_wan
ip netns exec natB ip link set veth_natB_wan up
ip netns exec natB ip route add default via 100.64.0.1

# natB LAN <-> cliB
ip link add veth_natB_lan type veth peer name veth_cliB
ip link set veth_natB_lan netns natB
ip link set veth_cliB netns cliB
ip netns exec natB ip addr add 10.0.2.1/24 dev veth_natB_lan
ip netns exec natB ip link set veth_natB_lan up

ip netns exec cliB ip link set lo up
ip netns exec cliB ip addr add 10.0.2.2/24 dev veth_cliB
ip netns exec cliB ip link set veth_cliB up
ip netns exec cliB ip route add default via 10.0.2.1

# NAT rules for natB.
ip netns exec natB sysctl -w net.ipv4.ip_forward=1 >/dev/null
snat_postrouting natB veth_natB_wan 100.64.0.3
# Full-cone-ish inbound mapping for the single LAN host (cliB).
ip netns exec natB iptables -t nat -A PREROUTING -i veth_natB_wan -p udp -j DNAT --to-destination 10.0.2.2
ip netns exec natB iptables -A FORWARD -i veth_natB_lan -o veth_natB_wan -j ACCEPT
ip netns exec natB iptables -A FORWARD -i veth_natB_wan -o veth_natB_lan -p udp -j ACCEPT
ip netns exec natB iptables -A FORWARD -i veth_natB_wan -o veth_natB_lan -m state --state ESTABLISHED,RELATED -j ACCEPT

export ROOM="${ROOM:-demo}"
export TIMEOUT_SECS="${TIMEOUT_SECS:-20}"

set +e
ip netns exec cliA env \
  COORDINATOR_HOST="100.64.0.1" \
  COORDINATOR_HTTP_PORT="${PORT}" \
  COORDINATOR_UDP_PORT="3478" \
  ROOM="${ROOM}" \
  CLIENT_ID="a" \
  PEER_ID="b" \
  TIMEOUT_SECS="${TIMEOUT_SECS}" \
  rendezvous-client &
PID_A=$!

ip netns exec cliB env \
  COORDINATOR_HOST="100.64.0.1" \
  COORDINATOR_HTTP_PORT="${PORT}" \
  COORDINATOR_UDP_PORT="3478" \
  ROOM="${ROOM}" \
  CLIENT_ID="b" \
  PEER_ID="a" \
  TIMEOUT_SECS="${TIMEOUT_SECS}" \
  rendezvous-client &
PID_B=$!
set -e

wait "${PID_A}"
wait "${PID_B}"

echo "natlab ok: both clients exchanged direct UDP messages"
