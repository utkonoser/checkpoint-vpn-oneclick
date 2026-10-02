import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var password = ""
    @State private var totp = ""
    @State private var saveMessage: String?
    @State private var karingCopyMessage: String?
    @State private var importingQR = false

    var body: some View {
        Form {
            Section("VPN") {
                if model.siteChoices.isEmpty {
                    TextField("Site (hostname)", text: siteBinding)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Site", selection: siteBinding) {
                        ForEach(model.siteChoices, id: \.self) { site in
                            Text(site).tag(site)
                        }
                    }
                    if !model.siteChoices.contains(model.site) {
                        TextField("Site (hostname)", text: siteBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                TextField("Username", text: $model.username)
                    .textFieldStyle(.roundedBorder)
                TextField("Login type", text: $model.snxLoginType)
                    .textFieldStyle(.roundedBorder)
                Text("Login type: run CheckpointVPNTunnel -m info -s <host> (e.g. vpn_VPN_RA). Password and TOTP are per site. Connect uses split-tunnel (`default-route=false`) so Karing can own the rest of the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Work domains (Karing Direct)") {
                TextEditor(text: $model.workDomains)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 88, maxHeight: 140)
                Text("One domain or suffix per line (e.g. rutube.ru). Used only to export Karing Direct rules — the tunnel helper still uses routes from the Check Point gateway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Copy Karing rules") {
                    if model.copyKaringRulesToClipboard() {
                        karingCopyMessage = model.workDomainList.isEmpty
                            ? "Copied placeholder — add domains and copy again."
                            : "Copied \(model.workDomainList.count) domain(s) for Karing Direct."
                    } else {
                        karingCopyMessage = "Could not write to clipboard."
                    }
                }
                if let karingCopyMessage {
                    Text(karingCopyMessage).font(.caption)
                }
            }

            Section("Tunnel helper") {
                LabeledContent("Payload in app") {
                    Text(SnxClient.bundledHelperPayloadURL() != nil ? "Yes" : "Missing")
                        .foregroundStyle(SnxClient.bundledHelperPayloadURL() != nil ? .green : .orange)
                }
                LabeledContent("System helper") {
                    Text(SnxClient.isHelperInstalled() ? "Installed" : "Not installed")
                        .foregroundStyle(SnxClient.isHelperInstalled() ? .green : .orange)
                }
                Toggle("Ignore server certificate", isOn: $model.snxIgnoreServerCert)
                Text("Needed for many corporate Check Point gateways (`Internal IPSec certificate validation failed`).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Install / repair tunnel helper…") { model.installHelperManually() }
                    .disabled(model.isBusy || SnxClient.bundledHelperPayloadURL() == nil)
                Button("Restart tunnel helper…") { model.restartDaemonManually() }
                    .disabled(model.isBusy || !SnxClient.isHelperInstalled())
                Text("Install copies CheckpointVPNTunnel into /Library and registers LaunchDaemon local.checkpointvpn.tunnel (admin password once). Restart is like kickstart -k after sleep.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.snxInstalled {
                    Text("Build the helper with `make helper` (or Scripts/build-tunnel-helper.sh) so the app bundle includes TunnelHelper/, then Install / repair.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Current TOTP") {
                TOTPLiveView(hasSecret: model.hasTOTP, site: model.site)
            }

            Section("Secrets") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Password")
                            .fontWeight(.medium)
                        Spacer()
                        Text(model.hasPassword ? "Saved" : "Not set")
                            .font(.caption)
                            .foregroundStyle(model.hasPassword ? .green : .orange)
                    }
                    SecureField(
                        model.hasPassword ? "Leave empty to keep, or type a new password" : "Enter VPN password",
                        text: $password
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack {
                        Text("TOTP secret")
                            .fontWeight(.medium)
                        Spacer()
                        Text(model.hasTOTP ? "Saved" : "Not set")
                            .font(.caption)
                            .foregroundStyle(model.hasTOTP ? .green : .orange)
                    }
                    SecureField(
                        model.hasTOTP ? "Leave empty to keep, or paste a new secret" : "otpauth:// URL or Base32 secret",
                        text: $totp
                    )
                    .textFieldStyle(.roundedBorder)

                    Text("Paste into the fields above, or import a QR. Values apply only to the selected site. Empty fields keep the current saved secret.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Save secrets") { saveSecrets() }
                            .disabled(password.isEmpty && totp.isEmpty)
                        Button("Import QR image…") { importingQR = true }
                        Button("Paste QR from clipboard") { importClipboardQR() }
                    }
                    if let saveMessage {
                        Text(saveMessage).font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Connect") {
                LabeledContent("State") {
                    Text(model.isBusy ? "Working…" : model.vpnState.title)
                }
                if model.vpnState == .connected {
                    LabeledContent("Active site", value: model.snxStatus.serverName ?? model.site)
                }
                if let error = model.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Connect") { model.connect() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canConnect)
                    Button("Disconnect") { model.disconnect() }
                        .disabled(!model.canDisconnect)
                }
                Text(model.snxInstalled
                     ? "Connect needs site, username, login type, password, and TOTP. Use Karing for everything else (see README)."
                     : "Install the tunnel helper first (Settings → Install / repair), or rebuild with `make helper` so the payload is in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            model.refreshStatus()
            model.refreshSecrets()
            AppWindows.bringSettingsForward()
        }
        .fileImporter(isPresented: $importingQR, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            importQRFile(result)
        }
    }

    private var siteBinding: Binding<String> {
        Binding(
            get: { model.site },
            set: { newValue in
                model.selectSite(newValue)
                password = ""
                totp = ""
                saveMessage = nil
            }
        )
    }

    private func saveSecrets() {
        do {
            let site = model.site.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !site.isEmpty else { throw KeychainStore.Error.missingSite }
            model.rememberSite(site)
            if !password.isEmpty {
                try KeychainStore.setPassword(password, site: site)
                password = ""
            }
            if !totp.isEmpty {
                try model.importTOTP(totp)
                totp = ""
            }
            model.refreshSecrets()
            saveMessage = model.hasPassword && model.hasTOTP
                ? "Saved for \(site). Connect is ready."
                : "Saved for \(site). Add the missing secret to enable Connect."
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func importClipboardQR() {
        do {
            let secret = try QRCodeImporter.decodeClipboard()
            try model.importTOTP(secret)
            totp = ""
            saveMessage = model.hasTOTP
                ? "TOTP secret saved for \(model.site)."
                : "Import decoded, but store did not keep it."
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func importQRFile(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let secret = try QRCodeImporter.decode(fileURL: url)
            try model.importTOTP(secret)
            totp = ""
            saveMessage = model.hasTOTP
                ? "TOTP secret saved for \(model.site)."
                : "Import decoded, but store did not keep it."
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

private struct TOTPLiveView: View {
    var hasSecret: Bool
    var site: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tick = Self.read(site: site, at: context.date)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(tick.code)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(tick.secondsLeft)s")
                            .font(.title3.monospacedDigit())
                        ProgressView(value: Double(tick.secondsLeft), total: Double(max(tick.period, 1)))
                            .frame(width: 90)
                    }
                }
                if !hasSecret {
                    Text("Save a TOTP secret for this site to see the live code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func read(site: String, at date: Date) -> (code: String, secondsLeft: Int, period: Int) {
        guard let raw = try? KeychainStore.totpSecret(site: site),
              let secret = try? TOTP.parseSecret(raw) else {
            return ("------", 0, 30)
        }
        return (
            TOTP.code(for: secret, at: date),
            max(0, Int(TOTP.secondsRemaining(period: secret.period, at: date).rounded(.down))),
            secret.period
        )
    }
}
