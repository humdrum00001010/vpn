use anyhow::{bail, Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::collections::HashMap;
use std::net::{SocketAddr, ToSocketAddrs, UdpSocket};
use std::time::{Duration, Instant};
use tokio::time::sleep;
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

#[tokio::main]
async fn main() -> Result<()> {
    let coordinator_host = env("COORDINATOR_HOST", "coordinator");
    let coordinator_http_port: u16 = env("COORDINATOR_HTTP_PORT", "4000").parse()?;
    let coordinator_udp_port: u16 = env("COORDINATOR_UDP_PORT", "3478").parse()?;

    let room = env("ROOM", "demo");
    let client_id = env_required("CLIENT_ID")?;
    let peer_id = env_required("PEER_ID")?;
    let timeout_secs: u64 = env("TIMEOUT_SECS", "15").parse()?;

    let udp_target: SocketAddr = (coordinator_host.as_str(), coordinator_udp_port)
        .to_socket_addrs()
        .context("failed to resolve coordinator UDP address")?
        .next()
        .context("coordinator UDP address resolution returned no results")?;
    let ws_url = Url::parse(&format!(
        "ws://{}:{}/socket/websocket?vsn=2.0.0",
        coordinator_host, coordinator_http_port
    ))?;
    let ws_url_s = ws_url.to_string();
    let topic = format!("rendezvous:{room}");

    // UDP registration: send before and after websocket join to avoid race with broadcasts.
    let udp = UdpSocket::bind("0.0.0.0:0").context("failed to bind UDP socket")?;
    udp.set_read_timeout(Some(Duration::from_millis(500)))?;
    let reg = json!({ "room": room, "client_id": client_id });
    udp.send_to(reg.to_string().as_bytes(), udp_target)
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
        .context("failed to send UDP registration (post-join)")?;

    let mut peers: HashMap<String, Option<String>> = HashMap::new();
    let deadline = Instant::now() + Duration::from_secs(timeout_secs);

    while Instant::now() < deadline {
        if let Some(Some(udp)) = peers.get(&peer_id) {
            println!("{client_id} discovered peer {peer_id} at {udp}");
            return Ok(());
        }

        let msg = tokio::time::timeout(Duration::from_millis(500), ws.next()).await;
        let Ok(Some(Ok(Message::Text(txt)))) = msg else {
            continue;
        };

        let Some((_topic, event, payload)) = parse_phoenix_v2_message(&txt) else {
            continue;
        };

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

    bail!("{client_id} timed out waiting to discover peer {peer_id}");
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
