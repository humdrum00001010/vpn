use std::io;
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

fn run_ifconfig(args: &[&str]) -> io::Result<()> {
    let output = Command::new("/sbin/ifconfig").args(args).output()?;
    if !output.status.success() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!(
                "ifconfig failed: ifconfig {} (status {})\nstdout: {}\nstderr: {}",
                args.join(" "),
                output.status,
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr),
            ),
        ));
    }
    Ok(())
}

fn list_interfaces() -> io::Result<Vec<String>> {
    let out = Command::new("/sbin/ifconfig").arg("-l").output()?;
    if !out.status.success() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!(
                "ifconfig -l failed (status {})\nstdout: {}\nstderr: {}",
                out.status,
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr),
            ),
        ));
    }
    let s = String::from_utf8_lossy(&out.stdout);
    Ok(s.split_whitespace().map(|x| x.to_string()).collect())
}

fn interface_exists(name: &str) -> io::Result<bool> {
    Ok(list_interfaces()?.iter().any(|x| x == name))
}

fn wait_until<F: Fn() -> bool>(timeout: Duration, poll: Duration, f: F) -> io::Result<()> {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if f() {
            return Ok(());
        }
        thread::sleep(poll);
    }
    Err(io::Error::new(io::ErrorKind::TimedOut, "timed out waiting"))
}

fn create_feth() -> io::Result<String> {
    let out = Command::new("/sbin/ifconfig")
        .args(["feth", "create"])
        .output()?;
    if !out.status.success() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!(
                "ifconfig feth create failed (status {})\nstdout: {}\nstderr: {}",
                out.status,
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr),
            ),
        ));
    }
    let name = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if name.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            "ifconfig feth create returned empty interface name",
        ));
    }
    Ok(name)
}

pub struct FethPair {
    pub a: String,
    pub b: String,
    created_a: bool,
    created_b: bool,
}

impl FethPair {
    pub fn create_pair() -> io::Result<Self> {
        let a = create_feth()?;
        let b = create_feth()?;

        wait_until(Duration::from_secs(1), Duration::from_millis(20), || {
            interface_exists(&a).unwrap_or(false)
        })?;
        wait_until(Duration::from_secs(1), Duration::from_millis(20), || {
            interface_exists(&b).unwrap_or(false)
        })?;

        // Pair the devices. If this fails, packets won't traverse between them.
        run_ifconfig(&[a.as_str(), "peer", b.as_str()])?;

        run_ifconfig(&[a.as_str(), "up"])?;
        run_ifconfig(&[b.as_str(), "up"])?;

        Ok(Self {
            a,
            b,
            created_a: true,
            created_b: true,
        })
    }

    pub fn set_ipv4(&self, dev: &str, addr_cidr: &str) -> io::Result<()> {
        run_ifconfig(&[dev, "inet", addr_cidr])
    }
}

impl Drop for FethPair {
    fn drop(&mut self) {
        // Only destroy interfaces we created, to avoid impacting pre-existing system state.
        if self.created_a {
            let _ = Command::new("/sbin/ifconfig")
                .args([self.a.as_str(), "destroy"])
                .output();
            let _ = wait_until(Duration::from_secs(1), Duration::from_millis(20), || {
                !interface_exists(&self.a).unwrap_or(true)
            });
        }
        if self.created_b {
            let _ = Command::new("/sbin/ifconfig")
                .args([self.b.as_str(), "destroy"])
                .output();
            let _ = wait_until(Duration::from_secs(1), Duration::from_millis(20), || {
                !interface_exists(&self.b).unwrap_or(true)
            });
        }
    }
}
