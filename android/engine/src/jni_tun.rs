use std::net::Ipv4Addr;

use ipnet::Ipv4Net;
use jni::objects::{JObject, JValue};
use jni::{JNIEnv, JavaVM};
use once_cell::sync::OnceCell;
use tracing::{error, info};

static JVM: OnceCell<JavaVM> = OnceCell::new();

pub fn set_vm(vm: JavaVM) {
    let _ = JVM.set(vm);
}

pub fn establish_via_kotlin(
    address: Ipv4Addr,
    prefix: u8,
    mtu: u16,
    dns: &[Ipv4Addr],
    routes: &[Ipv4Net],
) -> anyhow::Result<i32> {
    let vm = JVM.get().ok_or_else(|| anyhow::anyhow!("JNI JavaVM not set"))?;
    let mut env = vm
        .attach_current_thread()
        .map_err(|e| anyhow::anyhow!("attach_current_thread: {e}"))?;

    let dns_csv = dns
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(",");
    let routes_csv = routes
        .iter()
        .map(|r| format!("{}/{}", r.addr(), r.prefix_len()))
        .collect::<Vec<_>>()
        .join(",");

    let address_j = env.new_string(address.to_string())?;
    let dns_j = env.new_string(&dns_csv)?;
    let routes_j = env.new_string(&routes_csv)?;

    let class = env.find_class("com/checkpoint/vpn/oneclick/vpn/TunEstablisher")?;
    let result = env.call_static_method(
        class,
        "establish",
        "(Ljava/lang/String;IILjava/lang/String;Ljava/lang/String;)I",
        &[
            JValue::Object(&JObject::from(address_j)),
            JValue::Int(i32::from(prefix)),
            JValue::Int(i32::from(mtu)),
            JValue::Object(&JObject::from(dns_j)),
            JValue::Object(&JObject::from(routes_j)),
        ],
    )?;

    let fd = result.i()?;
    if fd < 0 {
        error!("TunEstablisher.establish returned {fd}");
        anyhow::bail!("VpnService establish failed (fd={fd})");
    }
    info!("VpnService TUN established via Kotlin, fd={fd}");
    Ok(fd)
}

/// Unused helper kept for symmetry with JNIEnv lifetime debugging.
#[allow(dead_code)]
fn _env_noop(_: &JNIEnv) {}
