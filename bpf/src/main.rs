use anyhow::{Context, Result};
use macos_bpf_tunnel::config::{MONITORED_IP, PREFERRED_INTERFACE, TUNNEL_TARGET, build_bpf_filter};
use macos_bpf_tunnel::device_select::choose_pcap_device_name;
use macos_bpf_tunnel::runner::{RunnerConfig, forward_captured_packets};
use std::net::{Ipv4Addr, SocketAddr};

fn main() -> Result<()> {
    let monitored_ip: Ipv4Addr = MONITORED_IP
        .parse()
        .with_context(|| format!("invalid MONITORED_IP: {MONITORED_IP}"))?;
    let tunnel_target: SocketAddr = TUNNEL_TARGET
        .parse()
        .with_context(|| format!("invalid TUNNEL_TARGET: {TUNNEL_TARGET}"))?;
    let filter = build_bpf_filter(monitored_ip);

    let devices = pcap::Device::list().context("failed to list capture devices")?;
    let device_name = choose_pcap_device_name(&devices, PREFERRED_INTERFACE, monitored_ip)
        .with_context(|| {
            format!(
                "no capture interface found (preferred: {PREFERRED_INTERFACE}, ipv4 fallback: {monitored_ip})"
            )
        })?;

    println!(
        "capturing {} (preferred {}, ipv4 fallback {}) with filter '{}' and tunneling packets to {}",
        device_name, PREFERRED_INTERFACE, monitored_ip, filter, tunnel_target
    );

    let cfg = RunnerConfig {
        device_name,
        filter: &filter,
        tunnel_target,
        read_timeout_ms: 250,
    };
    let _ = forward_captured_packets(cfg, None, None)?;
    Ok(())
}
