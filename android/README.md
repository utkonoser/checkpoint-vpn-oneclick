# Checkpoint VPN One-Click (Android)

Android twin of the macOS menu-bar client: Kotlin + Jetpack Compose UI, `VpnService` TUN, and the AGPL [snxcore](../Vendor/snx-rs) engine built via `cargo-ndk` / JNI.

## Features (MVP)

- Multi-gateway account (username + login type)
- Password + TOTP (Base32 / `otpauth://`) stored in EncryptedSharedPreferences
- Ignore server certificate toggle
- Split destinations (CIDR / IP / hostname → `VpnService.Builder.addRoute`)
- Connect / Disconnect, foreground notification, Quick Settings tile
- Reconnect on network restore

## License

The native tunnel engine links **snxcore** from `Vendor/snx-rs` (AGPL-3.0). Distributing this APK requires providing corresponding source for the engine and this app’s native bridge (`android/engine`). See [Vendor/snx-rs/COPYING](../Vendor/snx-rs/COPYING) and [docs/THIRD_PARTY.md](../docs/THIRD_PARTY.md).

## Requirements

- JDK 17+
- Android SDK 35 + NDK 27.2.12479018
- Rust stable + `cargo-ndk`
- Targets: `aarch64-linux-android`, `x86_64-linux-android`

```bash
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk
```

## Build

```bash
export ANDROID_HOME=…/Android/sdk   # or android/.sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018
echo "sdk.dir=$ANDROID_HOME" > android/local.properties

cd android
./gradlew :app:assembleRelease
```

`preBuild` runs `cargo ndk … --features snxcore` and installs `libcheckpoint_engine.so` into `app/src/main/jniLibs/`.

Debug APK: `./gradlew :app:assembleDebug` → `app/build/outputs/apk/debug/`.

Release (DMG + APK): **Actions → Release → Run workflow** with a tag. PR CI: **Actions → Android**.

## Sideload

```bash
adb install -r app/build/outputs/apk/release/app-release.apk
```

On first Connect, Android prompts for VPN permission. Add a Quick Settings tile via **Edit tiles** → Checkpoint VPN.

### Gateway smoke test

1. Save gateway / username / login type / password / TOTP.
2. Optional split list (same semantics as macOS).
3. Connect — Session should show engine string `checkpoint-engine snxcore/android`, then Connected or a mapped engine error.
4. Confirm only listed destinations (or Office Mode routes when the list is empty) go through the VPN.

## Architecture

| Layer | Role |
|-------|------|
| Compose UI | Account / Auth / Split / Session |
| `CheckpointVpnService` | VPN consent, Builder routes/DNS, foreground service |
| `NativeEngine` (JNI) | `checkpoint-engine` cdylib |
| snxcore Android platform | Userspace IPsec; TUN fd from VpnService; routes/DNS owned by Kotlin |

## Out of scope (v1)

- Play Store listing / Always-on VPN product packaging
- SAML / browser IdP / PKCS11
- SSL tunnel mode
