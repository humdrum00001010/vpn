use std::io;
use std::net::{SocketAddr, UdpSocket};

pub fn forward_packet(socket: &UdpSocket, target: SocketAddr, packet: &[u8]) -> io::Result<usize> {
    if packet.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "cannot forward empty packet",
        ));
    }

    socket.send_to(packet, target)
}

#[cfg(test)]
mod tests {
    use super::forward_packet;
    use std::io;
    use std::net::UdpSocket;
    use std::time::Duration;

    #[test]
    fn forwards_packet_bytes_to_target_socket() -> io::Result<()> {
        let receiver = UdpSocket::bind("127.0.0.1:0")?;
        receiver.set_read_timeout(Some(Duration::from_millis(500)))?;
        let sender = UdpSocket::bind("127.0.0.1:0")?;

        let payload = [0xAA, 0xBB, 0xCC, 0xDD];
        let sent = forward_packet(&sender, receiver.local_addr()?, &payload)?;
        assert_eq!(sent, payload.len());

        let mut buf = [0_u8; 1500];
        let (len, _) = receiver.recv_from(&mut buf)?;
        assert_eq!(&buf[..len], &payload);
        Ok(())
    }

    #[test]
    fn rejects_empty_packets() {
        let receiver = UdpSocket::bind("127.0.0.1:0").expect("receiver bind should succeed");
        let sender = UdpSocket::bind("127.0.0.1:0").expect("sender bind should succeed");

        let err = forward_packet(&sender, receiver.local_addr().expect("receiver should have address"), &[])
            .expect_err("empty packet should be rejected");
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
    }
}
