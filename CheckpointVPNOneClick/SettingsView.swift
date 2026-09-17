import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var password = ""
    @State private var totp = ""
    @State private var saveMessage: String?
    @State private var importingQR = false

    var body: some View {
        Form {
            Section("VPN") {
                if siteChoices.isEmpty {
                    TextField("Site", text: $model.site)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("Site", selection: $model.site) {
                        ForEach(siteChoices, id: \.self) { site in
                            Text(site).tag(site)
                        }
                    }
                    if !siteChoices.contains(model.site) {
                        TextField("Site", text: $model.site)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                TextField("Username", text: $model.username)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Current TOTP") {
                TOTPLiveView(hasSecret: model.hasTOTP)
            }

            Section("Secrets (Keychain)") {
                LabeledContent("Password") {
                    SecureField(model.hasPassword ? "Saved" : "Required", text: $password)
                }
                LabeledContent("TOTP secret") {
                    SecureField(model.hasTOTP ? "Saved" : "otpauth:// or Base32", text: $totp)
                }
                Text("Paste the Base32 secret, an otpauth:// URL, or import a QR screenshot. Type a new value to replace a saved one.")
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

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    Text(model.accessibilityTrusted ? "Granted" : "Required")
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                if !model.accessibilityTrusted {
                    if model.isRunningFromInstall {
                        Text("Turn on Checkpoint VPN in Accessibility, then Quit from the menu bar and open ~/Applications/CheckpointVPNOneClick.app again. macOS keeps this as Required until that restart.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("This is a throwaway build. Quit it and open ~/Applications/CheckpointVPNOneClick.app, then grant Accessibility to that copy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(model.runningPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                HStack {
                    Button("Request Accessibility") { model.requestAccessibility() }
                    Button("Recheck") { model.refreshPermissions() }
                }
                HStack {
                    Button("Open Accessibility settings") { model.openAccessibilitySettings() }
                    Button("Allow System Events") { model.requestAutomation() }
                }
            }

            Section("Connect") {
                LabeledContent("State") {
                    Text(model.isBusy ? "Working…" : model.snapshot.overall.title)
                }
                if let active = model.snapshot.active {
                    LabeledContent("Active site", value: active.name)
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
                Text("Connect stays disabled until site, username, password, TOTP secret, and Accessibility are set.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            model.refreshStatus()
            model.refreshPermissions()
            AppWindows.bringSettingsForward()
        }
        .fileImporter(isPresented: $importingQR, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            importQRFile(result)
        }
    }

    private var siteChoices: [String] {
        var names = model.snapshot.sites.map(\.name)
        if !model.site.isEmpty, !names.contains(model.site) {
            names.insert(model.site, at: 0)
        }
        return names
    }

    private func saveSecrets() {
        do {
            if !password.isEmpty {
                try KeychainStore.setPassword(password)
                password = ""
            }
            if !totp.isEmpty {
                try model.importTOTP(totp)
                totp = ""
            }
            model.refreshSecrets()
            saveMessage = model.hasPassword && model.hasTOTP
                ? "Saved. Connect is ready."
                : "Saved. Add the missing secret to enable Connect."
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
                ? "TOTP secret saved in Keychain."
                : "Import decoded, but Keychain did not keep it."
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
                ? "TOTP secret saved in Keychain."
                : "Import decoded, but Keychain did not keep it."
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

private struct TOTPLiveView: View {
    var hasSecret: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tick = Self.read(at: context.date)
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
                    Text("Save a TOTP secret to see the live code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func read(at date: Date) -> (code: String, secondsLeft: Int, period: Int) {
        guard let raw = try? KeychainStore.totpSecret(),
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
