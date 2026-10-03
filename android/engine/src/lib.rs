use jni::objects::{JClass, JString};
use jni::sys::{jboolean, jint, jstring, JNI_VERSION_1_6};
use jni::{JNIEnv, JavaVM};
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use std::os::raw::c_void;
use std::sync::atomic::{AtomicBool, Ordering};

static TUN_FD: Mutex<Option<i32>> = Mutex::new(None);
static STATUS: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new(String::from("disconnected")));
static CONNECTED: AtomicBool = AtomicBool::new(false);

#[cfg(feature = "snxcore")]
static RUNTIME: Lazy<tokio::runtime::Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .thread_name("checkpoint-engine")
        .build()
        .expect("tokio runtime")
});

#[cfg(feature = "snxcore")]
mod jni_tun;
#[cfg(feature = "snxcore")]
mod tunnel;

fn set_status(msg: impl Into<String>) {
    *STATUS.lock() = msg.into();
}

#[allow(non_snake_case)]
#[no_mangle]
pub extern "system" fn JNI_OnLoad(vm: JavaVM, _: *mut c_void) -> jint {
    #[cfg(feature = "snxcore")]
    {
        jni_tun::set_vm(vm);
        snxcore::platform::android::register_vpn_establish_fn(jni_tun::establish_via_kotlin);
    }
    #[cfg(not(feature = "snxcore"))]
    {
        let _ = vm;
    }
    JNI_VERSION_1_6
}

#[no_mangle]
pub extern "system" fn Java_com_checkpoint_vpn_oneclick_vpn_NativeEngine_nativeHello(
    env: JNIEnv,
    _class: JClass,
) -> jstring {
    let msg = if cfg!(feature = "snxcore") {
        "checkpoint-engine snxcore/android"
    } else {
        "checkpoint-engine stub (build with --features snxcore)"
    };
    env.new_string(msg)
        .expect("string")
        .into_raw()
}

#[no_mangle]
pub extern "system" fn Java_com_checkpoint_vpn_oneclick_vpn_NativeEngine_nativeSetTunFd(
    _env: JNIEnv,
    _class: JClass,
    fd: jint,
) {
    *TUN_FD.lock() = Some(fd);
    #[cfg(feature = "snxcore")]
    {
        snxcore::platform::android::set_vpn_tun_fd(fd);
    }
}

#[no_mangle]
pub extern "system" fn Java_com_checkpoint_vpn_oneclick_vpn_NativeEngine_nativeStatus(
    env: JNIEnv,
    _class: JClass,
) -> jstring {
    let status = STATUS.lock().clone();
    env.new_string(status).expect("string").into_raw()
}

#[no_mangle]
pub extern "system" fn Java_com_checkpoint_vpn_oneclick_vpn_NativeEngine_nativeDisconnect(
    _env: JNIEnv,
    _class: JClass,
) {
    CONNECTED.store(false, Ordering::SeqCst);
    #[cfg(feature = "snxcore")]
    {
        tunnel::request_disconnect();
        snxcore::platform::android::clear_vpn_tun_fd();
    }
    *TUN_FD.lock() = None;
    set_status("disconnected");
}

#[no_mangle]
pub extern "system" fn Java_com_checkpoint_vpn_oneclick_vpn_NativeEngine_nativeConnect<'local>(
    mut env: JNIEnv<'local>,
    _class: JClass<'local>,
    server: JString<'local>,
    username: JString<'local>,
    password: JString<'local>,
    mfa_code: JString<'local>,
    login_type: JString<'local>,
    ignore_server_cert: jboolean,
    routes_csv: JString<'local>,
) -> jstring {
    let server = env.get_string(&server).map(|s| s.into()).unwrap_or_default();
    let username = env.get_string(&username).map(|s| s.into()).unwrap_or_default();
    let password = env.get_string(&password).map(|s| s.into()).unwrap_or_default();
    let mfa_code = env.get_string(&mfa_code).map(|s| s.into()).unwrap_or_default();
    let login_type = env.get_string(&login_type).map(|s| s.into()).unwrap_or_default();
    let routes_csv = env.get_string(&routes_csv).map(|s| s.into()).unwrap_or_default();
    let ignore = ignore_server_cert != 0;

    let result = connect_inner(server, username, password, mfa_code, login_type, ignore, routes_csv);
    env.new_string(result).expect("string").into_raw()
}

fn connect_inner(
    server: String,
    username: String,
    password: String,
    mfa_code: String,
    login_type: String,
    ignore_server_cert: bool,
    routes_csv: String,
) -> String {
    if server.trim().is_empty() || username.trim().is_empty() {
        return "error: gateway and username are required".into();
    }

    #[cfg(not(feature = "snxcore"))]
    {
        let _ = (password, mfa_code, login_type, ignore_server_cert, routes_csv);
        set_status(format!("connected(stub):{server}"));
        CONNECTED.store(true, Ordering::SeqCst);
        return format!("ok: stub connected to {server} (rebuild with --features snxcore for real IPsec)");
    }

    #[cfg(feature = "snxcore")]
    {
        // Clear any stale TUN from a previous session; a fresh one is opened after auth.
        snxcore::platform::android::clear_vpn_tun_fd();
        *TUN_FD.lock() = None;

        set_status(format!("connecting:{server}"));
        match RUNTIME.block_on(tunnel::connect(
            server.clone(),
            username,
            password,
            mfa_code,
            login_type,
            ignore_server_cert,
            routes_csv,
        )) {
            Ok(()) => {
                CONNECTED.store(true, Ordering::SeqCst);
                set_status(format!("connected:{server}"));
                "ok:connected".into()
            }
            Err(e) => {
                CONNECTED.store(false, Ordering::SeqCst);
                let msg = format!("error: {e:#}");
                set_status(msg.clone());
                msg
            }
        }
    }
}
