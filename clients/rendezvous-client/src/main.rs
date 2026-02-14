use anyhow::{bail, Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::{Duration, Instant};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::time::{interval, sleep};
use tokio_tungstenite::tungstenite::Message;
use url::Url;

fn parse_phoenix_v2_message(txt: &str) -> Option<(String, String, serde_json::Value)> {
    // Phoenix.Socket.V2.JSONSerializer text format:
    // [join_ref, ref, topic, event, payload]
    let v: serde_json::Value = serde_json::from_str(txt).ok()?;
    let arr = v.as_array()?;
    if arr.len() < 5 {
        return None;
    }
    let topic = arr[2].as_str()?.to_string();
    let event = arr[3].as_str()?.to_string();
    let payload = arr[4].clone();
    Some((topic, event, payload))
}

fn env(name: &str, default: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| default.to_string())
}

fn env_required(name: &str) -> Result<String> {
    std::env::var(name).with_context(|| format!("missing required env var {name}"))
}

fn parse_presence_state(v: &serde_json::Value) -> HashMap<String, Option<String>> {
    let mut out = HashMap::new();
    let Some(map) = v.as_object() else {
        return out;
    };
    for (key, val) in map.iter() {
        let udp = val
            .get("metas")
            .and_then(|m| m.as_array())
            .and_then(|arr| arr.first())
            .and_then(|m0| m0.get("udp"))
            .and_then(|u| u.as_str())
            .map(|s| s.to_string());
        out.insert(key.clone(), udp);
    }
    out
}

async fn resolve_udp_target(host: &str, port: u16) -> Result<SocketAddr> {
    let mut addrs = tokio::net::lookup_host((host, port))
        .await
        .context("failed to resolve coordinator UDP address")?;
    addrs
        .next()
        .context("coordinator UDP address resolution returned no results")
}

async fn ws_send_heartbeat<S>(ws: &mut tokio_tungstenite::WebSocketStream<S>, hb_ref: &mut u64) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    // Phoenix protocol: heartbeat on topic "phoenix" with event "heartbeat".
    // Use a monotonically increasing ref to keep the socket alive.
    *hb_ref += 1;
    let msg = json!(["0", hb_ref.to_string(), "phoenix", "heartbeat", {}]);
    ws.send(Message::Text(msg.to_string()))
        .await
        .context("failed to send websocket heartbeat")
}

fn parse_udp_message(s: &str) -> Option<(&str, &str, &str)> {
    // "vpn-ping <room> <client_id>"
    // "vpn-pong <room> <client_id>"
    let mut it = s.split_whitespace();
    let kind = it.next()?;
    let room = it.next()?;
    let client_id = it.next()?;
    Some((kind, room, client_id))
}

#[tokio::main]
async fn main() -> Result<()> {
    let coordinator_host = env("COORDINATOR_HOST", "coordinator");
    let coordinator_http_port: u16 = env("COORDINATOR_HTTP_PORT", "4000").parse()?;
    let coordinator_udp_port: u16 = env("COORDINATOR_UDP_PORT", "3478").parse()?;

    let room = env("ROOM", "demo");
    let client_id = env_required("CLIENT_ID")?;
    let peer_id = env_required("PEER_ID")?;
    let timeout_secs: u64 = env("TIMEOUT_SECS", "15").parse()?;
    let keepalive_secs: u64 = env("KEEPALIVE_SECS", "15").parse()?;
    let stay_secs: u64 = env("STAY_SECS", "0").parse()?;

    let udp_target = resolve_udp_target(coordinator_host.as_str(), coordinator_udp_port).await?;
    let ws_url = Url::parse(&format!(
        "ws://{}:{}/socket/websocket?vsn=2.0.0",
        coordinator_host, coordinator_http_port
    ))?;
    let ws_url_s = ws_url.to_string();
    let topic = format!("rendezvous:{room}");

    // One UDP socket for registration + direct peer traffic.
    // Using a single socket increases the odds that NAT mapping stays stable.
    let udp = tokio::net::UdpSocket::bind("0.0.0.0:0")
        .await
        .context("failed to bind UDP socket")?;
    let reg = json!({ "room": room, "client_id": client_id });
    udp.send_to(reg.to_string().as_bytes(), udp_target)
        .await
        .context("failed to send UDP registration")?;

    // Websocket connect with retry.
    let start = Instant::now();
    let (mut ws, _) = loop {
        match tokio_tungstenite::connect_async(ws_url_s.clone()).await {
            Ok(v) => break v,
            Err(_) if start.elapsed() < Duration::from_secs(timeout_secs) => {
                sleep(Duration::from_millis(200)).await;
                continue;
            }
            Err(e) => return Err(e).context("failed to connect websocket"),
        }
    };

    // Join channel.
    let join = json!(["1", "1", topic, "phx_join", { "client_id": client_id }]);
    ws.send(Message::Text(join.to_string())).await?;

    // Re-register after join so the server can broadcast udp_seen to this socket.
    udp.send_to(reg.to_string().as_bytes(), udp_target)
        .await
        .context("failed to send UDP registration (post-join)")?;

    let mut peers: HashMap<String, Option<String>> = HashMap::new();
    let deadline = Instant::now() + Duration::from_secs(timeout_secs);
    let stay_deadline = if stay_secs == 0 {
        None
    } else {
        Some(Instant::now() + Duration::from_secs(stay_secs))
    };

    let mut peer_udp: Option<SocketAddr> = None;
    let mut punch_tick = interval(Duration::from_millis(200));
    let mut keepalive_tick = interval(Duration::from_secs(keepalive_secs.max(1)));
    let mut coord_keepalive_tick = interval(Duration::from_secs(5));
    let mut ws_heartbeat_tick = interval(Duration::from_secs(25));
    let mut hb_ref: u64 = 10;
    let mut established = false;
    let mut buf = vec![0u8; 2048];

    while Instant::now() < deadline {
        if established {
            if let Some(until) = stay_deadline {
                if Instant::now() >= until {
                    return Ok(());
                }
            }
        }

        if peer_udp.is_none() {
            if let Some(Some(udp_s)) = peers.get(&peer_id) {
                peer_udp = Some(
                    udp_s.parse::<SocketAddr>()
                        .with_context(|| format!("failed to parse peer udp endpoint {udp_s}"))?,
                );
                println!("{client_id} discovered peer {peer_id} at {udp_s}");
            }
        }

        tokio::select! {
            _ = coord_keepalive_tick.tick() => {
                // Keep coordinator observation fresh (and keep the NAT mapping to the coordinator alive).
                let _ = udp.send_to(reg.to_string().as_bytes(), udp_target).await;
            }
            _ = ws_heartbeat_tick.tick() => {
                // Keep websocket alive so Presence doesn't silently drop.
                let _ = ws_send_heartbeat(&mut ws, &mut hb_ref).await;
            }
            _ = punch_tick.tick(), if peer_udp.is_some() && !established => {
                let peer = peer_udp.unwrap();
                let msg = format!("vpn-ping {room} {client_id}");
                let _ = udp.send_to(msg.as_bytes(), peer).await;
            }
            _ = keepalive_tick.tick(), if peer_udp.is_some() && established => {
                let peer = peer_udp.unwrap();
                let msg = format!("vpn-ping {room} {client_id}");
                let _ = udp.send_to(msg.as_bytes(), peer).await;
            }
            recv = udp.recv_from(&mut buf) => {
                let (n, from) = recv.context("udp recv_from failed")?;
                let txt = String::from_utf8_lossy(&buf[..n]);

                if let Some((kind, msg_room, msg_client)) = parse_udp_message(&txt) {
                    if msg_room == room && msg_client == peer_id {
                        // Accept traffic from whatever endpoint actually works, even if it differs
                        // from rendezvous-discovered "ip:port" (symmetric NAT will often break that).
                        if peer_udp.is_none() {
                            peer_udp = Some(from);
                        }

                        if kind == "vpn-ping" {
                            let reply = format!("vpn-pong {room} {client_id}");
                            let _ = udp.send_to(reply.as_bytes(), from).await;
                        }

                        if kind == "vpn-ping" || kind == "vpn-pong" {
                            if !established {
                                println!("{client_id} direct udp ok with {peer_id} (from {from})");
                                established = true;
                                if stay_deadline.is_none() {
                                    return Ok(());
                                }
                            }
                        }
                    }
                }
            }
            msg = tokio::time::timeout(Duration::from_millis(500), ws.next()) => {
                let Ok(Some(Ok(Message::Text(txt)))) = msg else { continue; };
                let Some((_topic, event, payload)) = parse_phoenix_v2_message(&txt) else { continue; };

                match event.as_str() {
                    "presence_state" => {
                        peers.extend(parse_presence_state(&payload));
                    }
                    "udp_seen" => {
                        if let Some(obj) = payload.as_object() {
                            let cid = obj.get("client_id").and_then(|v| v.as_str());
                            let udp = obj.get("udp").and_then(|v| v.as_str());
                            if let (Some(cid), Some(udp)) = (cid, udp) {
                                peers.insert(cid.to_string(), Some(udp.to_string()));
                            }
                        }
                    }
                    "phx_reply" => {}
                    _ => {}
                }
            }
        }
    }

    bail!("{client_id} timed out waiting for direct udp with peer {peer_id}");
}

#[cfg(test)]
mod tests {
    use super::parse_presence_state;
    use serde_json::json;

    #[test]
    fn parses_presence_state_udp_meta() {
        let v = json!({
          "a": { "metas": [ { "udp": "10.0.0.2:1234" } ] },
          "b": { "metas": [ { } ] }
        });
        let got = parse_presence_state(&v);
        assert_eq!(got.get("a").cloned().flatten(), Some("10.0.0.2:1234".to_string()));
        assert_eq!(got.get("b").cloned().flatten(), None);
    }
}
