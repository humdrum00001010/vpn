#[cfg(target_os = "linux")]
#[test]
#[ignore]
fn nat_emulation_requires_linux_netns_and_privileges() {
    eprintln!(
        "NAT translation cannot be validated on a single local UDP socket.\n\
Run a Linux netns+iptables based integration test in privileged Docker/CI.\n\
Example approach:\n\
- netns: client, nat, server\n\
- veth pairs between them\n\
- ip_forward=1 on nat\n\
- iptables MASQUERADE/SNAT on nat\n\
- client sends to coordinator:3478, coordinator reports observed src ip:port\n\
"
    );
}

#[cfg(not(target_os = "linux"))]
#[test]
#[ignore]
fn nat_emulation_stub_is_linux_only() {
    eprintln!("NAT emulation tests are Linux-only (use Docker/netns).");
}
