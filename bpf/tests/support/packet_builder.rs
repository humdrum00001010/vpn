use std::net::Ipv4Addr;

pub fn build_eth_ipv4_udp_frame(
    src_ip: Ipv4Addr,
    dst_ip: Ipv4Addr,
    src_port: u16,
    dst_port: u16,
    payload: &[u8],
) -> Vec<u8> {
    let eth_len = 14;
    let ip_len = 20;
    let udp_len = 8;
    let total_len = eth_len + ip_len + udp_len + payload.len();

    let mut buf = vec![0_u8; total_len];

    // Ethernet header
    buf[0..6].copy_from_slice(&[0xff; 6]); // dst MAC: broadcast
    buf[6..12].copy_from_slice(&[0x02, 0x00, 0x00, 0x00, 0x00, 0x01]); // src MAC: locally-administered
    buf[12..14].copy_from_slice(&0x0800_u16.to_be_bytes()); // Ethertype: IPv4

    // IPv4 header (minimal, no options)
    let ip_start = eth_len;
    buf[ip_start + 0] = 0x45; // version 4, IHL 5
    buf[ip_start + 1] = 0; // DSCP/ECN
    let ip_total_len = (ip_len + udp_len + payload.len()) as u16;
    buf[ip_start + 2..ip_start + 4].copy_from_slice(&ip_total_len.to_be_bytes());
    buf[ip_start + 4..ip_start + 6].copy_from_slice(&0x1234_u16.to_be_bytes()); // identification
    buf[ip_start + 6..ip_start + 8].copy_from_slice(&0x0000_u16.to_be_bytes()); // flags/fragment
    buf[ip_start + 8] = 64; // TTL
    buf[ip_start + 9] = 17; // protocol UDP
    // checksum filled later
    buf[ip_start + 12..ip_start + 16].copy_from_slice(&src_ip.octets());
    buf[ip_start + 16..ip_start + 20].copy_from_slice(&dst_ip.octets());

    let csum = ipv4_header_checksum(&buf[ip_start..ip_start + ip_len]);
    buf[ip_start + 10..ip_start + 12].copy_from_slice(&csum.to_be_bytes());

    // UDP header
    let udp_start = ip_start + ip_len;
    buf[udp_start + 0..udp_start + 2].copy_from_slice(&src_port.to_be_bytes());
    buf[udp_start + 2..udp_start + 4].copy_from_slice(&dst_port.to_be_bytes());
    let udp_total_len = (udp_len + payload.len()) as u16;
    buf[udp_start + 4..udp_start + 6].copy_from_slice(&udp_total_len.to_be_bytes());
    buf[udp_start + 6..udp_start + 8].copy_from_slice(&0_u16.to_be_bytes()); // checksum = 0 (disabled in IPv4)

    // Payload
    buf[udp_start + udp_len..].copy_from_slice(payload);

    buf
}

fn ipv4_header_checksum(hdr: &[u8]) -> u16 {
    debug_assert!(hdr.len() == 20);
    let mut sum: u32 = 0;
    for i in (0..20).step_by(2) {
        if i == 10 {
            continue; // checksum field
        }
        let word = u16::from_be_bytes([hdr[i], hdr[i + 1]]) as u32;
        sum = sum.wrapping_add(word);
    }
    while (sum >> 16) != 0 {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    !(sum as u16)
}
