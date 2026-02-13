#[cfg(target_os = "macos")]
mod macos_only {
    use macos_bpf_tunnel::config::{MONITORED_IP, TUNNEL_TARGET, build_bpf_filter};
    use macos_bpf_tunnel::runner::{RunnerConfig, forward_captured_packets_with_ready};
    use std::net::{Ipv4Addr, SocketAddr};
    use std::sync::mpsc;
    use std::time::Duration;

    mod tcp_server {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/support/tcp_server.rs"
        ));
    }

    mod ifconfig {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/support/ifconfig.rs"
        ));
    }

    mod packet_builder {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/support/packet_builder.rs"
        ));
    }

    #[test]
    #[ignore]
    fn creates_feth_applies_filter_and_tunnels_captured_packet_to_tcp_server() -> anyhow::Result<()> {
        // Requires root for ifconfig + packet capture.
        // Run:
        //   cd /Users/phihu/Desktop/vpn/bpf
        //   sudo -E cargo test --test macos_feth_smoke -- --ignored --nocapture
        //
        // If you're already in the `bpf/` directory, just run the `sudo cargo test ...` line.
        let pair = ifconfig::FethPair::create_pair()?;
        let pair_a = pair.a.clone();
        eprintln!("created feth pair: {} <-> {}", pair.a, pair.b);

        // Align to current config constants to avoid surprises.
        let monitored_ip: Ipv4Addr = MONITORED_IP.parse()?;
        let peer_ip = Ipv4Addr::new(monitored_ip.octets()[0], monitored_ip.octets()[1], monitored_ip.octets()[2], monitored_ip.octets()[3].wrapping_add(1));

        pair.set_ipv4(&pair.a, &format!("{}/24", monitored_ip))?;
        pair.set_ipv4(&pair.b, &format!("{}/24", peer_ip))?;

        let filter = build_bpf_filter(monitored_ip);

        let _configured_tunnel_target: SocketAddr = TUNNEL_TARGET.parse()?;
        let server = tcp_server::TcpTestServer::spawn(Duration::from_secs(2))?;

        // We tunnel to our test server (not the configured constant).
        let tunnel_target = server.address();

        let (ready_tx, ready_rx) = mpsc::channel();
        let handle = std::thread::spawn(move || {
            let cfg = RunnerConfig {
                device_name: &pair_a,
                filter: &filter,
                tunnel_target,
                read_timeout_ms: 250,
            };
            forward_captured_packets_with_ready(cfg, Some(1), Some(Duration::from_secs(2)), Some(ready_tx))
        });

        // Generate traffic that is guaranteed to hit the interface by injecting a raw frame on feth1.
        ready_rx
            .recv_timeout(Duration::from_secs(2))
            .map_err(|_| anyhow::anyhow!("timed out waiting for capture to be ready"))?;

        let payload: [u8; 6] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02];
        let frame = packet_builder::build_eth_ipv4_udp_frame(peer_ip, monitored_ip, 44444, 5555, &payload);
        let mut inject = pcap::Capture::from_device(pair.b.as_str())?
            .immediate_mode(true)
            .timeout(250)
            .open()?;
        inject.sendpacket(frame)?;

        let got = server.recv(Duration::from_secs(2))?;
        assert!(
            got.windows(payload.len()).any(|w| w == payload),
            "expected forwarded raw packet bytes to contain UDP payload (got {} bytes)",
            got.len()
        );

        let forwarded = handle
            .join()
            .map_err(|_| anyhow::anyhow!("capture thread panicked"))??;
        assert_eq!(forwarded, 1);

        drop(pair);
        Ok(())
    }
}

#[cfg(not(target_os = "macos"))]
#[test]
#[ignore]
fn macos_feth_smoke_test_is_macos_only() {
    eprintln!("macos feth smoke test is only supported on macOS");
}
