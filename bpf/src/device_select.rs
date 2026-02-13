use std::net::Ipv4Addr;

pub fn choose_pcap_device_name<'a>(
    devices: &'a [pcap::Device],
    preferred_name: &'a str,
    ip_fallback: Ipv4Addr,
) -> Option<&'a str> {
    if devices.iter().any(|d| d.name == preferred_name) {
        return Some(preferred_name);
    }
    select_pcap_device_name_by_ipv4(devices, ip_fallback)
}

pub fn select_pcap_device_name_by_ipv4(devices: &[pcap::Device], ip: Ipv4Addr) -> Option<&str> {
    devices
        .iter()
        .find(|dev| dev.addresses.iter().any(|a| a.addr == std::net::IpAddr::V4(ip)))
        .map(|dev| dev.name.as_str())
}

#[cfg(test)]
mod tests {
    use super::{choose_pcap_device_name, select_pcap_device_name_by_ipv4};
    use std::net::{IpAddr, Ipv4Addr};

    #[test]
    fn selects_device_which_has_the_configured_ipv4() {
        let devices = vec![
            pcap::Device {
                name: "en0".to_string(),
                desc: None,
                addresses: vec![pcap::Address {
                    addr: IpAddr::V4(Ipv4Addr::new(192, 168, 1, 2)),
                    netmask: None,
                    broadcast_addr: None,
                    dst_addr: None,
                }],
                flags: pcap::DeviceFlags::empty(),
            },
            pcap::Device {
                name: "utun5".to_string(),
                desc: None,
                addresses: vec![pcap::Address {
                    addr: IpAddr::V4(Ipv4Addr::new(10, 99, 0, 1)),
                    netmask: None,
                    broadcast_addr: None,
                    dst_addr: None,
                }],
                flags: pcap::DeviceFlags::empty(),
            },
        ];

        let selected = select_pcap_device_name_by_ipv4(&devices, Ipv4Addr::new(10, 99, 0, 1))
            .expect("device should be selected");
        assert_eq!(selected, "utun5");
    }

    #[test]
    fn prefers_named_interface_when_present() {
        let devices = vec![pcap::Device {
            name: "veth0".to_string(),
            desc: None,
            addresses: vec![pcap::Address {
                addr: IpAddr::V4(Ipv4Addr::new(172, 16, 0, 2)),
                netmask: None,
                broadcast_addr: None,
                dst_addr: None,
            }],
            flags: pcap::DeviceFlags::empty(),
        }];

        let selected = choose_pcap_device_name(&devices, "veth0", Ipv4Addr::new(10, 99, 0, 1))
            .expect("device should be selected");
        assert_eq!(selected, "veth0");
    }

    #[test]
    fn falls_back_to_ip_selection_when_preferred_name_missing() {
        let devices = vec![pcap::Device {
            name: "utun5".to_string(),
            desc: None,
            addresses: vec![pcap::Address {
                addr: IpAddr::V4(Ipv4Addr::new(10, 99, 0, 1)),
                netmask: None,
                broadcast_addr: None,
                dst_addr: None,
            }],
            flags: pcap::DeviceFlags::empty(),
        }];

        let selected = choose_pcap_device_name(&devices, "veth0", Ipv4Addr::new(10, 99, 0, 1))
            .expect("device should be selected");
        assert_eq!(selected, "utun5");
    }
}
