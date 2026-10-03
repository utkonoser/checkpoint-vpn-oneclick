#![allow(unsafe_code)]

use std::{
    net::{Ipv4Addr, SocketAddr},
    path::PathBuf,
    time::Duration,
};

use tokio::net::UdpSocket;
use uuid::Uuid;

use crate::{
    model::{IPsecSession, params::TunnelType},
    platform::{
        DeviceConfig, IPsecConfigurator, Keychain, NetworkInterface, PlatformAccess, PlatformFeatures,
        ResolverConfigurator, RoutingConfigurator, SingleInstance, UdpEncapType, UdpSocketExt,
    },
};

mod ipsec_stub;
mod keychain;
mod net;
mod resolver;
mod routing;
mod single_instance;
mod stats;
mod tun_fd;

impl UdpSocketExt for UdpSocket {
    fn set_encapsulation(&self, _encap: UdpEncapType) -> anyhow::Result<()> {
        Ok(())
    }

    fn set_no_check(&self, _flag: bool) -> anyhow::Result<()> {
        Ok(())
    }

    fn bind_to_tunnel(&self, _device: &str) -> anyhow::Result<()> {
        Ok(())
    }

    async fn send_receive(&self, data: &[u8], timeout: Duration, target: SocketAddr) -> anyhow::Result<Vec<u8>> {
        super::udp_send_receive(self, data, timeout, target).await
    }
}

pub struct AndroidPlatformAccess;

impl PlatformAccess for AndroidPlatformAccess {
    async fn get_features(&self) -> PlatformFeatures {
        PlatformFeatures {
            ipsec_native: false,
            ipsec_keepalive: true,
            split_dns: false,
        }
    }

    fn new_resolver_configurator<S: AsRef<str>>(
        &self,
        device: S,
    ) -> anyhow::Result<Box<dyn ResolverConfigurator + Send + Sync>> {
        Ok(Box::new(resolver::AndroidResolverConfigurator::new(device)))
    }

    fn new_keychain(&self) -> impl Keychain + Send + Sync {
        keychain::AndroidKeychain::new()
    }

    fn get_machine_uuid(&self) -> anyhow::Result<Uuid> {
        Ok(Uuid::new_v4())
    }

    fn is_root(&self) -> bool {
        // VpnService runs as the app UID; treat as privileged for tunnel setup.
        true
    }

    fn init(&self) {}

    fn new_ipsec_configurator(
        &self,
        device_config: DeviceConfig,
        ipsec_session: IPsecSession,
        src_ip: Ipv4Addr,
        src_port: u16,
        dest_ip: Ipv4Addr,
        dest_port: u16,
    ) -> impl IPsecConfigurator + use<> + Send + Sync {
        ipsec_stub::AndroidIPsecStub::new(device_config, ipsec_session, src_ip, src_port, dest_ip, dest_port)
    }

    async fn new_routing_configurator<S: AsRef<str> + Send>(
        &self,
        device: S,
        tunnel_type: TunnelType,
    ) -> anyhow::Result<impl RoutingConfigurator + Send + Sync + 'static> {
        Ok(routing::AndroidRoutingConfigurator::new(device, tunnel_type))
    }

    fn new_network_interface(&self) -> impl NetworkInterface + Send + Sync + 'static {
        net::AndroidNetworkInterface::new()
    }

    fn new_single_instance<S: AsRef<str>>(&self, name: S) -> anyhow::Result<impl SingleInstance + 'static> {
        single_instance::AndroidSingleInstance::new(name)
    }

    fn data_dir(&self) -> PathBuf {
        std::env::var("CHECKPOINT_VPN_DATA_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/data/local/tmp/checkpoint-vpn"))
    }
}

pub use tun_fd::{
    clear_vpn_tun_fd, dup_vpn_tun_fd, establish_vpn_service, peek_vpn_tun_fd, register_vpn_establish_fn,
    set_vpn_tun_fd, take_vpn_tun_fd, VpnEstablishFn,
};
