use async_trait::async_trait;
use tracing::debug;

use crate::platform::{ResolverConfig, ResolverConfigurator};

pub struct AndroidResolverConfigurator {
    device: String,
}

impl AndroidResolverConfigurator {
    pub fn new<S: AsRef<str>>(device: S) -> Self {
        Self {
            device: device.as_ref().to_owned(),
        }
    }
}

#[async_trait]
impl ResolverConfigurator for AndroidResolverConfigurator {
    async fn configure(&self, config: &ResolverConfig) -> anyhow::Result<()> {
        // DNS servers are applied by VpnService.Builder in Kotlin.
        debug!(
            "Android DNS is managed by VpnService (device={}, servers={:?})",
            self.device, config.dns_servers
        );
        Ok(())
    }

    async fn cleanup(&self, _config: &ResolverConfig) -> anyhow::Result<()> {
        Ok(())
    }
}

