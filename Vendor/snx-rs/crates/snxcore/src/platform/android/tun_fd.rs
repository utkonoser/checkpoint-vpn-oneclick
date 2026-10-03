use std::{
    net::Ipv4Addr,
    os::fd::{BorrowedFd, IntoRawFd, RawFd},
    sync::Mutex,
};

use ipnet::Ipv4Net;

use crate::platform::DeviceConfig;

static VPN_TUN_FD: Mutex<Option<i32>> = Mutex::new(None);

/// Called from the JNI bridge to open VpnService.Builder and return a TUN fd.
pub type VpnEstablishFn = fn(
    address: Ipv4Addr,
    prefix: u8,
    mtu: u16,
    dns: &[Ipv4Addr],
    routes: &[Ipv4Net],
) -> anyhow::Result<i32>;

static ESTABLISH_FN: Mutex<Option<VpnEstablishFn>> = Mutex::new(None);

pub fn set_vpn_tun_fd(fd: i32) {
    *VPN_TUN_FD.lock().unwrap_or_else(|e| e.into_inner()) = Some(fd);
}

pub fn take_vpn_tun_fd() -> Option<i32> {
    VPN_TUN_FD.lock().unwrap_or_else(|e| e.into_inner()).take()
}

pub fn peek_vpn_tun_fd() -> Option<i32> {
    *VPN_TUN_FD.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn clear_vpn_tun_fd() {
    *VPN_TUN_FD.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

pub fn register_vpn_establish_fn(f: VpnEstablishFn) {
    *ESTABLISH_FN.lock().unwrap_or_else(|e| e.into_inner()) = Some(f);
}

/// Ask Kotlin to establish VpnService only after auth/IKE succeeded (so DNS to the gateway
/// still uses the physical network).
pub fn establish_vpn_service(
    device: &DeviceConfig,
    dns: &[Ipv4Addr],
    routes: &[Ipv4Net],
) -> anyhow::Result<()> {
    if peek_vpn_tun_fd().is_some() {
        return Ok(());
    }
    let establish = ESTABLISH_FN
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .ok_or_else(|| anyhow::anyhow!("Android VpnService establish callback is not registered"))?;
    let fd = establish(
        device.address.addr(),
        device.address.prefix_len(),
        device.mtu,
        dns,
        routes,
    )?;
    if fd < 0 {
        anyhow::bail!("VpnService.Builder.establish() failed");
    }
    set_vpn_tun_fd(fd);
    Ok(())
}

/// Duplicate the VpnService TUN fd for the `tun` crate without sharing close ownership.
pub fn dup_vpn_tun_fd() -> anyhow::Result<RawFd> {
    let fd = peek_vpn_tun_fd().ok_or_else(|| anyhow::anyhow!("Android VpnService TUN fd was not set"))?;
    let borrowed = unsafe { BorrowedFd::borrow_raw(fd) };
    Ok(nix::unistd::dup(borrowed)?.into_raw_fd())
}
