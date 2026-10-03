use std::str::FromStr;
use std::sync::Arc;

use ipnet::Ipv4Net;
use secrecy::{ExposeSecret, SecretString};
use snxcore::model::params::TunnelParams;
use snxcore::model::{MfaType, SessionState};
use snxcore::platform::{NetworkInterface, Platform, PlatformAccess};
use snxcore::tunnel::{
    TunnelCommand, TunnelConnectorFactory, TunnelEvent, connector::CheckPointConnectorFactory,
};
use tokio::sync::mpsc;
use tracing::{info, warn};

static DISCONNECT_TX: parking_lot::Mutex<Option<mpsc::Sender<TunnelCommand>>> = parking_lot::Mutex::new(None);

pub fn request_disconnect() {
    if let Some(tx) = DISCONNECT_TX.lock().clone() {
        let _ = tx.try_send(TunnelCommand::Terminate(true));
    }
}

pub async fn connect(
    server: String,
    username: String,
    password: String,
    mfa_code: String,
    login_type: String,
    ignore_server_cert: bool,
    routes_csv: String,
) -> anyhow::Result<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();

    Platform::get().init();

    let add_routes = routes_csv
        .split(',')
        .filter_map(|s| {
            let s = s.trim();
            if s.is_empty() {
                None
            } else {
                Ipv4Net::from_str(s).ok()
            }
        })
        .collect::<Vec<_>>();

    let mut params = TunnelParams::default();
    params.server_name = server;
    params.user_name = username;
    params.password = SecretString::from(password);
    params.login_type = if login_type.trim().is_empty() {
        "vpn_VPN_RA".into()
    } else {
        login_type
    };
    params.password_factor = 1;
    params.mfa_code = if mfa_code.is_empty() { None } else { Some(mfa_code) };
    params.ignore_server_cert = ignore_server_cert;
    params.default_route = false;
    params.no_routing = !add_routes.is_empty();
    params.add_routes = add_routes;
    params.tunnel_type = snxcore::model::params::TunnelType::IPsec;
    params.keychain = false;

    let params = Arc::new(params);
    let factory = CheckPointConnectorFactory::default();

    let connector = factory.new_gateway_connector(params.clone());
    let info = connector.get_gateway_information().await?;
    if !info.is_supported_login_type(&params.login_type) {
        anyhow::bail!("unsupported login type: {}", params.login_type);
    }

    let mut tunnel_connector = factory.new_tunnel_connector(params.clone()).await?;
    let mut session = tunnel_connector.authenticate().await?;
    let mut mfa_index = 0usize;

    while let SessionState::PendingChallenge(challenge) = session.state.clone() {
        match challenge.mfa_type {
            MfaType::PasswordInput => {
                mfa_index += 1;
                let input = if !params.password.expose_secret().is_empty() && mfa_index == params.password_factor {
                    params.password.expose_secret().to_owned()
                } else if let Some(ref code) = params.mfa_code {
                    code.clone()
                } else {
                    anyhow::bail!("MFA challenge requires interactive input (not supported in v1)")
                };
                session = tunnel_connector.challenge_code(session, &input).await?;
            }
            other => anyhow::bail!("unsupported MFA type on Android v1: {other:?}"),
        }
    }

    let (command_sender, command_receiver) = mpsc::channel(16);
    *DISCONNECT_TX.lock() = Some(command_sender.clone());

    let mut tunnel = tunnel_connector
        .create_tunnel(session.clone(), command_sender.clone())
        .await?;

    if let Err(e) = Platform::get()
        .new_network_interface()
        .start_network_state_monitoring()
        .await
    {
        warn!("network monitoring unavailable: {e}");
    }

    let (event_sender, mut event_receiver) = mpsc::channel::<TunnelEvent>(16);
    let (connected_tx, connected_rx) = tokio::sync::oneshot::channel::<()>();
    let mut connected_tx = Some(connected_tx);

    tokio::spawn(async move {
        while let Some(event) = event_receiver.recv().await {
            let _ = tunnel_connector
                .handle_tunnel_event(event.clone())
                .await
                .inspect_err(|e| warn!("{e}"));
            match event {
                TunnelEvent::Connected(_) => {
                    info!("tunnel connected");
                    if let Some(tx) = connected_tx.take() {
                        let _ = tx.send(());
                    }
                }
                TunnelEvent::Disconnected => break,
                _ => {}
            }
        }
    });

    tokio::spawn(async move {
        if let Err(e) = tunnel.run(command_receiver, event_sender).await {
            warn!("tunnel ended: {e:#}");
        }
        *DISCONNECT_TX.lock() = None;
    });

    tokio::time::timeout(std::time::Duration::from_secs(90), connected_rx)
        .await
        .map_err(|_| anyhow::anyhow!("timed out waiting for tunnel Connected"))?
        .map_err(|_| anyhow::anyhow!("connect aborted before Connected"))?;

    Ok(())
}
