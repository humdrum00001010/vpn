use std::io;
use std::net::TcpStream;
use std::io::Write;

pub fn forward_packet(stream: &mut TcpStream, packet: &[u8]) -> io::Result<usize> {
    if packet.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "cannot forward empty packet",
        ));
    }

    stream.write_all(packet)?;
    Ok(packet.len())
}

#[cfg(test)]
mod tests {
    use super::forward_packet;
    use std::io;
    use std::net::{Shutdown, TcpStream};
    use std::time::Duration;

    mod tcp_server {
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/support/tcp_server.rs"
        ));
    }

    #[test]
    fn forwards_packet_bytes_to_target_socket() -> io::Result<()> {
        let receiver = tcp_server::TcpTestServer::spawn(Duration::from_secs(1))?;
        let mut sender = TcpStream::connect(receiver.address())?;

        let payload = [0xAA, 0xBB, 0xCC, 0xDD];
        let sent = forward_packet(&mut sender, &payload)?;
        assert_eq!(sent, payload.len());
        sender.shutdown(Shutdown::Write)?;

        let got = receiver.recv(Duration::from_secs(1))?;
        assert_eq!(got, payload);
        Ok(())
    }

    #[test]
    fn rejects_empty_packets() {
        let receiver =
            tcp_server::TcpTestServer::spawn(Duration::from_secs(1)).expect("receiver bind should succeed");
        let mut sender = TcpStream::connect(receiver.address()).expect("sender connect should succeed");

        let err = forward_packet(&mut sender, &[])
            .expect_err("empty packet should be rejected");
        assert_eq!(err.kind(), io::ErrorKind::InvalidInput);
    }
}
