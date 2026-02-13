#[cfg(target_os = "linux")]
mod linux_only {
    use macos_bpf_tunnel::config::{PREFERRED_INTERFACE, build_bpf_filter};
    use macos_bpf_tunnel::runner::{RunnerConfig, forward_captured_packets_with_ready};
    use std::io;
    use std::net::{Ipv4Addr, SocketAddr, UdpSocket};
    use std::process::Command;
    use std::sync::mpsc;
    use std::time::Duration;

    #[path = "support/tcp_server.rs"]
    mod tcp_server;

    struct VethPair;

    impl VethPair {
        fn create() -> io::Result<Self> {
            run_ip(&["link", "add", "veth0", "type", "veth", "peer", "name", "veth1"])?;
            run_ip(&["addr", "add", "192.168.1.10/24", "dev", "veth0"])?;
            run_ip(&["addr", "add", "192.168.1.11/24", "dev", "veth1"])?;
            run_ip(&["link", "set", "veth0", "up"])?;
            run_ip(&["link", "set", "veth1", "up"])?;
            Ok(Self)
        }
    }

    impl Drop for VethPair {
        fn drop(&mut self) {
            let _ = Command::new("ip").args(["link", "del", "veth0"]).status();
        }
    }

    fn run_ip(args: &[&str]) -> io::Result<()> {
        let status = Command::new("ip").args(args).status()?;
        if !status.success() {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("ip command failed: ip {}", args.join(" ")),
            ));
        }
        Ok(())
    }

    #[test]
    #[ignore]
    fn creates_veth0_applies_filter_and_tunnels_captured_packet_to_tcp_server() -> anyhow::Result<()> {
        // Requires:
        // - Linux
        // - root (or equivalent privileges) for veth + packet capture
        // Run: sudo -E cargo test --test linux_veth_smoke -- --ignored
        let _veth = VethPair::create()?;

        let monitored_ip = Ipv4Addr::new(192, 168, 1, 10);
        let filter = build_bpf_filter(monitored_ip);

        let server = tcp_server::TcpTestServer::spawn(Duration::from_secs(2))?;
        let tunnel_target: SocketAddr = server.address();

        let (ready_tx, ready_rx) = mpsc::channel();
        let handle = std::thread::spawn(move || {
            let cfg = RunnerConfig {
                device_name: PREFERRED_INTERFACE,
                filter: &filter,
                tunnel_target,
                read_timeout_ms: 250,
            };
            forward_captured_packets_with_ready(cfg, Some(1), Some(Duration::from_secs(2)), Some(ready_tx))
        });

        ready_rx
            .recv_timeout(Duration::from_secs(2))
            .map_err(|_| anyhow::anyhow!("timed out waiting for capture to be ready"))?;

        // Generate a packet that matches the filter and traverses veth.
        let sender = UdpSocket::bind("192.168.1.11:0")?;
        let payload: [u8; 6] = [0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02];
        sender.send_to(&payload, "192.168.1.10:5555")?;

        let got = server.recv(Duration::from_secs(2))?;
        assert!(
            got.windows(payload.len()).any(|w| w == payload),
            "expected forwarded raw packet bytes to contain UDP payload"
        );

        let forwarded = handle
            .join()
            .map_err(|_| anyhow::anyhow!("capture thread panicked"))??;
        assert_eq!(forwarded, 1);
        Ok(())
    }
}

#[cfg(not(target_os = "linux"))]
#[test]
#[ignore]
fn linux_veth_smoke_test_is_linux_only() {
    // Keep `cargo test -- --ignored` behavior explicit on non-Linux hosts.
    eprintln!("linux veth smoke test is only supported on Linux");
}
