use std::net::Ipv4Addr;

pub fn extract_ipv4_src_dst(frame: &[u8]) -> Option<(Ipv4Addr, Ipv4Addr)> {
    const ETH_HEADER_LEN: usize = 14;
    const IPV4_MIN_HEADER_LEN: usize = 20;

    if frame.len() < ETH_HEADER_LEN + IPV4_MIN_HEADER_LEN {
        return None;
    }

    let ether_type = u16::from_be_bytes([frame[12], frame[13]]);
    if ether_type != 0x0800 {
        return None;
    }

    let ip_start = ETH_HEADER_LEN;
    let ihl_words = (frame[ip_start] & 0x0F) as usize;
    let ihl_bytes = ihl_words * 4;
    if ihl_bytes < IPV4_MIN_HEADER_LEN || frame.len() < ip_start + ihl_bytes {
        return None;
    }

    let src = Ipv4Addr::new(
        frame[ip_start + 12],
        frame[ip_start + 13],
        frame[ip_start + 14],
        frame[ip_start + 15],
    );
    let dst = Ipv4Addr::new(
        frame[ip_start + 16],
        frame[ip_start + 17],
        frame[ip_start + 18],
        frame[ip_start + 19],
    );
    Some((src, dst))
}

pub fn frame_matches_ip(frame: &[u8], ip: Ipv4Addr) -> bool {
    extract_ipv4_src_dst(frame)
        .map(|(src, dst)| src == ip || dst == ip)
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::{extract_ipv4_src_dst, frame_matches_ip};
    use std::net::Ipv4Addr;

    #[test]
    fn extracts_ipv4_source_and_destination_from_ethernet_frame() {
        let frame = sample_ipv4_frame(Ipv4Addr::new(10, 1, 1, 10), Ipv4Addr::new(8, 8, 8, 8));
        let (src, dst) = extract_ipv4_src_dst(&frame).expect("valid frame should parse");
        assert_eq!(src, Ipv4Addr::new(10, 1, 1, 10));
        assert_eq!(dst, Ipv4Addr::new(8, 8, 8, 8));
    }

    #[test]
    fn returns_none_for_non_ipv4_ether_type() {
        let mut frame = sample_ipv4_frame(Ipv4Addr::new(1, 1, 1, 1), Ipv4Addr::new(2, 2, 2, 2));
        frame[12] = 0x86;
        frame[13] = 0xDD; // IPv6 ethertype
        assert!(extract_ipv4_src_dst(&frame).is_none());
    }

    #[test]
    fn matches_ip_if_source_or_destination_matches() {
        let frame = sample_ipv4_frame(Ipv4Addr::new(192, 168, 1, 50), Ipv4Addr::new(1, 1, 1, 1));
        assert!(frame_matches_ip(&frame, Ipv4Addr::new(192, 168, 1, 50)));
        assert!(frame_matches_ip(&frame, Ipv4Addr::new(1, 1, 1, 1)));
        assert!(!frame_matches_ip(&frame, Ipv4Addr::new(9, 9, 9, 9)));
    }

    fn sample_ipv4_frame(src: Ipv4Addr, dst: Ipv4Addr) -> Vec<u8> {
        let mut frame = vec![0_u8; 14 + 20];
        frame[12] = 0x08;
        frame[13] = 0x00; // IPv4 ethertype
        frame[14] = 0x45; // Version 4, IHL 5
        frame[26..30].copy_from_slice(&src.octets());
        frame[30..34].copy_from_slice(&dst.octets());
        frame
    }
}
