use std::net::Ipv4Addr;

use ipnet::Ipv4Net;
use tracing::debug;

use crate::platform::{DeviceConfig, NetworkInterface, StatsPoller, android::stats::AndroidStatsPoller};

pub struct AndroidNetworkInterface;

impl AndroidNetworkInterface {
    pub fn new() -> Self {
        Self
    }
}

impl NetworkInterface for AndroidNetworkInterface {
    async fn start_network_state_monitoring(&self) -> anyhow::Result<()> {
        Ok(())
    }

    async fn get_default_ipv4(&self) -> anyhow::Result<Ipv4Addr> {
        // Best-effort; VPN host route is owned by the system when protect() is used.
        Ok(Ipv4Addr::new(0, 0, 0, 0))
    }

    async fn delete_device(&self, _device_name: &str) -> anyhow::Result<()> {
        Ok(())
    }

    async fn configure_device(&self, device_config: &DeviceConfig) -> anyhow::Result<()> {
        // Address/MTU are applied by VpnService.Builder before the fd is passed in.
        debug!(
            "Android TUN already configured by VpnService: name={}, addr={}, mtu={}",
            device_config.name, device_config.address, device_config.mtu
        );
        Ok(())
    }

    async fn replace_ip_address(
        &self,
        _device_name: &str,
        _old_address: Ipv4Net,
        _new_address: Ipv4Net,
    ) -> anyhow::Result<()> {
        Ok(())
    }

    async fn new_stats_poller(&self, device_name: &str) -> anyhow::Result<impl StatsPoller + Send + Sync + 'static> {
        AndroidStatsPoller::new(device_name)
    }

    fn is_online(&self) -> bool {
        true
    }
}
