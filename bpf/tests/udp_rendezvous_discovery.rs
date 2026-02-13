use std::io;
use std::net::{SocketAddr, UdpSocket};
use std::thread;
use std::time::Duration;

#[test]
fn udp_rendezvous_server_can_report_observed_source_addr() -> io::Result<()> {
    // This is the core of "UDP port discovery" without NAT:
    // the server can report the source socket address it observed.
    //
    // NAT translation is an integration problem and must be tested with separate network stacks
    // (e.g. Linux netns + iptables in privileged Docker).
    let server = UdpSocket::bind("127.0.0.1:0")?;
    server.set_read_timeout(Some(Duration::from_secs(1)))?;
    server.set_write_timeout(Some(Duration::from_secs(1)))?;
    let server_addr = server.local_addr()?;

    let handle = thread::spawn(move || -> io::Result<()> {
        let mut buf = [0_u8; 256];
        let (len, peer) = server.recv_from(&mut buf)?;
        assert_eq!(&buf[..len], b"ping");
        server.send_to(peer.to_string().as_bytes(), peer)?;
        Ok(())
    });

    let client = UdpSocket::bind("127.0.0.1:0")?;
    client.set_read_timeout(Some(Duration::from_secs(1)))?;
    let client_addr = client.local_addr()?;

    client.send_to(b"ping", server_addr)?;

    let mut buf = [0_u8; 256];
    let (len, _) = client.recv_from(&mut buf)?;
    let observed: SocketAddr = std::str::from_utf8(&buf[..len])
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?
        .parse()
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    assert_eq!(observed, client_addr);
    handle
        .join()
        .map_err(|_| io::Error::other("server thread panicked"))??;
    Ok(())
}
