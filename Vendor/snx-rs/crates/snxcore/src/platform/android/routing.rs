use async_trait::async_trait;
use tracing::debug;

use crate::{
    model::params::TunnelType,
    platform::{RoutingConfig, RoutingConfigurator},
};

pub struct AndroidRoutingConfigurator {
    device: String,
    _tunnel_type: TunnelType,
}

impl AndroidRoutingConfigurator {
    pub fn new<S: AsRef<str>>(device: S, tunnel_type: TunnelType) -> Self {
        Self {
            device: device.as_ref().to_owned(),
            _tunnel_type: tunnel_type,
        }
    }
}

#[async_trait]
impl RoutingConfigurator for AndroidRoutingConfigurator {
    async fn configure(&self, config: &RoutingConfig) -> anyhow::Result<()> {
        // Routes are installed by VpnService.Builder in Kotlin before the TUN fd is handed over.
        debug!("Android routing is managed by VpnService (device={}, config={:?})", self.device, config);
        Ok(())
    }
}
