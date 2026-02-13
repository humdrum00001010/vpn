use std::net::Ipv4Addr;

pub const PREFERRED_INTERFACE: &str = "veth0";
pub const MONITORED_IP: &str = "192.168.1.10";
pub const TUNNEL_TARGET: &str = "127.0.0.1:4002";

pub fn build_bpf_filter(ip: Ipv4Addr) -> String {
    format!("ip and host {ip}")
}

#[cfg(test)]
mod tests {
    use super::build_bpf_filter;
    use std::net::Ipv4Addr;

    #[test]
    fn builds_host_filter_for_monitored_ip() {
        let filter = build_bpf_filter(Ipv4Addr::new(10, 0, 0, 42));
        assert_eq!(filter, "ip and host 10.0.0.42");
    }
}
