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
                Text("Login type comes from `snx-rs -m info -s <host>` (e.g. vpn_VPN_RA). Password and TOTP are per site. Connect uses split-tunnel (`default-route=false`) so Karing can own the rest of the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Work domains (Karing Direct)") {
                TextEditor(text: $model.workDomains)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 88, maxHeight: 140)
                Text("One domain or suffix per line (e.g. rutube.ru). Used only to export Karing Direct rules — snx-rs still uses routes from the Check Point gateway.")
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

            Section("snx-rs") {
                LabeledContent("Installed") {
                    Text(model.snxInstalled ? "Yes" : "Missing")
                        .foregroundStyle(model.snxInstalled ? .green : .orange)
                }
                Toggle("Ignore server certificate", isOn: $model.snxIgnoreServerCert)
                Text("Needed for many corporate Check Point gateways (`Internal IPSec certificate validation failed`). Same as snx-rs -X.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restart snx-rs daemon…") { model.restartDaemonManually() }
                    .disabled(model.isBusy || !model.snxInstalled)
                Text("Same as `sudo pkill snx-rs` / `launchctl kickstart -k`. Asks for your Mac password. App also does this on launch/wake when Idle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.snxInstalled {
                    Text("Install SNX-RS.pkg from https://github.com/ancwrd1/snx-rs/releases (includes snxctl + LaunchDaemon). If the official Check Point client is also installed, disconnect it manually before connecting here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Current TOTP") {
                TOTPLiveView(hasSecret: model.hasTOTP, site: model.site)
            }

            Section("Secrets") {
                LabeledContent("Password") {
                    SecureField(model.hasPassword ? "Saved for this site" : "Required", text: $password)
                }
                LabeledContent("TOTP secret") {
                    SecureField(model.hasTOTP ? "Saved for this site" : "otpauth:// or Base32", text: $totp)
                }
                Text("Paste the Base32 secret, an otpauth:// URL, or import a QR screenshot. Values apply only to the selected site.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                     : "Install snx-rs first — Connect stays disabled until snxctl is available.")
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
