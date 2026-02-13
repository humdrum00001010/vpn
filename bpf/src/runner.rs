use crate::forwarder::forward_packet;
use anyhow::{Context, Result};
use std::net::{SocketAddr, TcpStream};
use std::sync::mpsc;
use std::time::{Duration, Instant};

pub struct RunnerConfig<'a> {
    pub device_name: &'a str,
    pub filter: &'a str,
    pub tunnel_target: SocketAddr,
    pub read_timeout_ms: i32,
}

pub fn forward_captured_packets(
    cfg: RunnerConfig<'_>,
    max_packets: Option<usize>,
    max_duration: Option<Duration>,
) -> Result<usize> {
    forward_captured_packets_with_ready(cfg, max_packets, max_duration, None)
}

pub fn forward_captured_packets_with_ready(
    cfg: RunnerConfig<'_>,
    max_packets: Option<usize>,
    max_duration: Option<Duration>,
    ready: Option<mpsc::Sender<()>>,
) -> Result<usize> {
    let mut capture = pcap::Capture::from_device(cfg.device_name)
        .with_context(|| format!("failed to open interface {}", cfg.device_name))?
        .promisc(true)
        .immediate_mode(true)
        .timeout(cfg.read_timeout_ms)
        .open()
        .with_context(|| format!("failed to activate capture on {}", cfg.device_name))?;
    capture
        .filter(cfg.filter, true)
        .with_context(|| format!("failed to apply BPF filter: {}", cfg.filter))?;

    let mut stream = TcpStream::connect(cfg.tunnel_target).context("failed to connect TCP tunnel target")?;
    if let Some(tx) = ready {
        let _ = tx.send(());
    }

    let start = Instant::now();
    let mut forwarded = 0_usize;
    loop {
        if let Some(limit) = max_packets {
            if forwarded >= limit {
                return Ok(forwarded);
            }
        }
        if let Some(limit) = max_duration {
            if start.elapsed() >= limit {
                return Ok(forwarded);
            }
        }

        match capture.next_packet() {
            Ok(packet) => {
                // Packets are already filtered by libpcap's compiled BPF.
                if let Ok(_) = forward_packet(&mut stream, packet.data) {
                    forwarded += 1;
                }
            }
            Err(pcap::Error::TimeoutExpired) => continue,
            Err(err) => return Err(err).context("packet capture failed"),
        }
    }
}
