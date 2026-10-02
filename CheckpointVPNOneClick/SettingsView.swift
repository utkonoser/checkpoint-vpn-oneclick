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
            Section {
                stacked("Gateway") {
                    HStack(spacing: 8) {
                        TextField("vpn.example.com", text: $model.site)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .onSubmit { commitSiteFromField() }
                            .onChange(of: model.site) { _, _ in
                                model.refreshSecrets()
                            }

                        if !model.siteChoices.isEmpty {
                            Menu {
                                ForEach(model.siteChoices, id: \.self) { site in
                                    Button(site) {
                                        model.selectSite(site)
                                        password = ""
                                        totp = ""
                                        saveMessage = nil
                                    }
                                }
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .frame(width: 28, height: 28)
                            }
                            .help("Saved gateways")
                        }

                        Button {
                            commitSiteFromField()
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 28, height: 28)
                        }
                        .disabled(trimmedSite.isEmpty)
                        .help("Save gateway")

                        Button {
                            model.forgetSite(model.site)
                            password = ""
                            totp = ""
                            saveMessage = nil
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 28, height: 28)
                        }
                        .disabled(!model.siteChoices.contains(trimmedSite))
                        .help("Remove gateway")
                    }
                }

                stacked("Username") {
                    TextField("user.name", text: $model.username)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }

                stacked("Login type") {
                    TextField("vpn_VPN_RA", text: $model.snxLoginType)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                }
            } header: {
                Text("Account")
            }

            Section {
                TOTPLiveView(hasSecret: model.hasTOTP, site: model.site)

                secretEditor(title: "Password", text: $password, isSaved: model.hasPassword)
                secretEditor(title: "TOTP secret", text: $totp, isSaved: model.hasTOTP)

                HStack(spacing: 12) {
                    Button("Save") { saveSecrets() }
                        .disabled(password.isEmpty && totp.isEmpty)
                    Button("Import QR…") { importingQR = true }
                    Button("Paste QR") { importClipboardQR() }
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Authentication")
            }

            Section {
                stacked("CIDRs, IPs, hostnames") {
                    TextEditor(text: $model.splitDestinations)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 72, maxHeight: 120)
                }
            } header: {
                Text("Split tunnel")
            } footer: {
                Text("Optional. When set, only these destinations use the VPN. Leave empty to use gateway routes.")
            }

            Section {
                HStack {
                    Text(model.isBusy ? "Working…" : model.vpnState.title)
                        .font(.body.weight(.medium))
                    Spacer()
                    if model.vpnState == .connected {
                        Text(model.snxStatus.serverName ?? model.site)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let error = model.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Toggle("Ignore server certificate", isOn: $model.snxIgnoreServerCert)

                HStack(spacing: 12) {
                    Button("Connect") { model.connect() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canConnect)
                    Button("Disconnect") { model.disconnect() }
                        .disabled(!model.canDisconnect)
                    Spacer()
                    Button("Repair helper…") { model.installHelperManually() }
                        .disabled(model.isBusy || SnxClient.bundledHelperPayloadURL() == nil)
                }
            } header: {
                Text("Session")
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 560)
        .onAppear {
            model.refreshStatus()
            model.refreshSecrets()
            AppWindows.bringSettingsForward()
        }
        .fileImporter(isPresented: $importingQR, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            importQRFile(result)
        }
    }

    private var trimmedSite: String {
        model.site.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitSiteFromField() {
        guard !trimmedSite.isEmpty else { return }
        model.rememberSite(trimmedSite)
        model.refreshSecrets()
        password = ""
        totp = ""
        saveMessage = nil
    }

    private func saveSecrets() {
        do {
            let site = trimmedSite
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
                ? "Saved for \(site)"
                : "Saved for \(site) — add the other secret to enable Connect"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func importClipboardQR() {
        do {
            let secret = try QRCodeImporter.decodeClipboard()
            try model.importTOTP(secret)
            totp = ""
            saveMessage = model.hasTOTP ? "TOTP saved for \(model.site)" : "Import failed to persist"
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
            saveMessage = model.hasTOTP ? "TOTP saved for \(model.site)" : "Import failed to persist"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func stacked<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func secretEditor(title: String, text: Binding<String>, isSaved: Bool) -> some View {
        stacked(title) {
            HStack(spacing: 8) {
                SecureField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                Text(isSaved ? "Saved" : "Not set")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSaved ? Color.green : Color.orange)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

private struct TOTPLiveView: View {
    var hasSecret: Bool
    var site: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tick = Self.read(site: site, at: context.date)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Code")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(tick.code)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(hasSecret ? .primary : .secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(tick.secondsLeft)s")
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(tick.secondsLeft), total: Double(max(tick.period, 1)))
                        .frame(width: 88)
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
