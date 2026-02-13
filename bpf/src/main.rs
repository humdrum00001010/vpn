use anyhow::{Context, Result};
use macos_bpf_tunnel::config::{CAPTURE_INTERFACE, MONITORED_IP, TUNNEL_TARGET, build_bpf_filter};
use macos_bpf_tunnel::forwarder::forward_packet;
use macos_bpf_tunnel::packet::frame_matches_ip;
use std::net::{Ipv4Addr, SocketAddr, UdpSocket};

fn main() -> Result<()> {
    let monitored_ip: Ipv4Addr = MONITORED_IP
        .parse()
        .with_context(|| format!("invalid MONITORED_IP: {MONITORED_IP}"))?;
    let tunnel_target: SocketAddr = TUNNEL_TARGET
        .parse()
        .with_context(|| format!("invalid TUNNEL_TARGET: {TUNNEL_TARGET}"))?;
    let filter = build_bpf_filter(monitored_ip);

    let mut capture = pcap::Capture::from_device(CAPTURE_INTERFACE)
        .with_context(|| format!("failed to open interface {CAPTURE_INTERFACE}"))?
        .promisc(true)
        .immediate_mode(true)
        .open()
        .with_context(|| format!("failed to activate capture on {CAPTURE_INTERFACE}"))?;
    capture
        .filter(&filter, true)
        .with_context(|| format!("failed to apply BPF filter: {filter}"))?;

    let socket = UdpSocket::bind("127.0.0.1:0").context("failed to create UDP tunnel socket")?;
    println!(
        "capturing {} with filter '{}' and tunneling packets to {}",
        CAPTURE_INTERFACE, filter, tunnel_target
    );

    loop {
        match capture.next_packet() {
            Ok(packet) => {
                if frame_matches_ip(packet.data, monitored_ip) {
                    if let Err(err) = forward_packet(&socket, tunnel_target, packet.data) {
                        eprintln!("forwarding error: {err}");
                    }
                }
            }
            Err(pcap::Error::TimeoutExpired) => continue,
            Err(err) => return Err(err).context("packet capture failed"),
        }
    }
}
