use std::io::{self, Read};
use std::net::{SocketAddr, TcpListener};
use std::sync::mpsc::{self, Receiver};
use std::thread::{self, JoinHandle};
use std::time::Duration;

pub struct TcpTestServer {
    address: SocketAddr,
    receiver: Receiver<io::Result<Vec<u8>>>,
    handle: JoinHandle<()>,
}

impl TcpTestServer {
    pub fn spawn(timeout: Duration) -> io::Result<Self> {
        let listener = TcpListener::bind("127.0.0.1:0")?;
        let address = listener.local_addr()?;
        let (tx, receiver) = mpsc::channel();

        let handle = thread::spawn(move || {
            let result = (|| -> io::Result<Vec<u8>> {
                let (mut socket, _) = listener.accept()?;
                socket.set_read_timeout(Some(timeout))?;
                let mut payload = Vec::new();
                socket.read_to_end(&mut payload)?;
                Ok(payload)
            })();

            let _ = tx.send(result);
        });

        Ok(Self {
            address,
            receiver,
            handle,
        })
    }

    pub fn address(&self) -> SocketAddr {
        self.address
    }

    pub fn recv(self, timeout: Duration) -> io::Result<Vec<u8>> {
        let receive_result = self.receiver.recv_timeout(timeout).map_err(|err| {
            io::Error::new(
                io::ErrorKind::TimedOut,
                format!("timed out waiting for server payload: {err}"),
            )
        })?;
        self.handle
            .join()
            .map_err(|_| io::Error::other("tcp test server thread panicked"))?;
        receive_result
    }
}
