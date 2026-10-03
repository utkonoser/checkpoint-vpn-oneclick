use async_trait::async_trait;

use crate::{model::LiveStats, platform::StatsPoller};

pub struct AndroidStatsPoller;

impl AndroidStatsPoller {
    pub fn new(_device_name: &str) -> anyhow::Result<Self> {
        Ok(Self)
    }
}

#[async_trait]
impl StatsPoller for AndroidStatsPoller {
    async fn poll(&self) -> anyhow::Result<LiveStats> {
        Ok(LiveStats::default())
    }
}
