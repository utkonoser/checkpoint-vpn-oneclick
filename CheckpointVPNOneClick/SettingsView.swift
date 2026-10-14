import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var password = ""
    @State private var totp = ""
    @State private var saveMessage: String?
    @State private var importingQR = false
    @State private var workExpanded = true
    @State private var proxyExpanded = false
    @State private var showAddSheet = false
    @State private var addKind: AddConnectionKind = .checkpoint
    @State private var newGateway = ""
    @State private var newProxyName = "Personal proxy"
    @State private var newProxyURL = ProxySubscription.defaultURL
    @State private var proxyConfigured = true

    private enum AddConnectionKind: String, CaseIterable, Identifiable {
        case checkpoint = "Check Point"
        case other = "Other (subscription)"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section {
                if model.siteChoices.isEmpty && !proxyConfigured {
                    Text("No connections yet. Add a Check Point gateway or a subscription proxy.")
                        .foregroundStyle(.secondary)
                }

                if !model.siteChoices.isEmpty || !trimmedSite.isEmpty {
                    expandableConnection(
                        expanded: $workExpanded,
                        title: model.displayWorkName,
                        subtitle: trimmedSite.isEmpty ? "No gateway" : trimmedSite,
                        connected: model.vpnState == .connected
                    ) {
                        workVPNBody
                    }
                }

                if proxyConfigured {
                    expandableConnection(
                        expanded: $proxyExpanded,
                        title: model.displayProxyName,
                        subtitle: proxySubtitle,
                        connected: model.proxyRunning
                    ) {
                        proxyVPNBody
                    }
                }
            } header: {
                HStack {
                    Text("Connections")
                    Spacer()
                    Button {
                        addKind = .checkpoint
                        newGateway = ""
                        newProxyName = model.displayProxyName
                        newProxyURL = ProxySubscription.defaultURL
                        showAddSheet = true
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let error = model.lastError, !error.isEmpty {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section {
                HStack {
                    if model.activeTunnels.count > 1 {
                        Button("Disconnect All") { model.disconnectAll() }
                            .disabled(model.isBusy)
                    }
                    Spacer()
                    Button("Repair tunnel helper…") {
                        if SnxClient.isHelperInstalled() {
                            model.restartDaemonManually()
                        } else {
                            model.installHelperManually()
                        }
                    }
                    .disabled(
                        model.isBusy
                            || (SnxClient.bundledHelperPayloadURL() == nil && !SnxClient.isHelperInstalled())
                    )
                }
            } footer: {
                Text(model.isBusy ? "Working…" : "Each connection starts and stops on its own.")
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 440, idealWidth: 500, minHeight: 640)
        .onAppear {
            model.refreshStatus()
            model.refreshSecrets()
            proxyConfigured = !model.proxySubscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            AppWindows.bringSettingsForward()
        }
        .fileImporter(isPresented: $importingQR, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            importQRFile(result)
        }
        .sheet(isPresented: $showAddSheet) {
            addConnectionSheet
        }
    }

    // MARK: - Expandable row (whole header is tappable)

    @ViewBuilder
    private func expandableConnection<Content: View>(
        expanded: Binding<Bool>,
        title: String,
        subtitle: String,
        connected: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                    Circle()
                        .fill(connected ? Color.green : Color.red.opacity(0.85))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(connected ? "Connected · \(subtitle)" : "Disconnected · \(subtitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                content()
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
        }
    }

    private var proxySubtitle: String {
        if model.proxyRunning {
            return model.proxyNow ?? model.proxyNodeTag
        }
        return model.proxyNodes.isEmpty ? "no nodes yet" : "\(model.proxyNodes.count) nodes"
    }

    // MARK: - Check Point body

    @ViewBuilder
    private var workVPNBody: some View {
        stacked("Name") {
            TextField("Check Point", text: $model.workConnectionName)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }

        stacked("Gateway") {
            HStack(spacing: 8) {
                TextField("vpn.example.com", text: $model.site)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit { commitSiteFromField() }
                    .onChange(of: model.site) { _, _ in
                        model.refreshSecrets()
                        password = ""
                        totp = ""
                        saveMessage = nil
                    }

                if model.siteChoices.count > 1 {
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
                    }
                    .help("Saved gateways")
                }

                Button {
                    model.forgetSite(model.site)
                    password = ""
                    totp = ""
                    saveMessage = nil
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(trimmedSite.isEmpty)
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

        Toggle("Ignore server certificate", isOn: $model.snxIgnoreServerCert)

        TOTPLiveView(hasSecret: model.hasTOTP, site: model.site)
        secretEditor(title: "Password", text: $password, isSaved: model.hasPassword)
        secretEditor(title: "TOTP secret", text: $totp, isSaved: model.hasTOTP)

        HStack(spacing: 12) {
            Button("Save secrets") { saveSecrets() }
                .disabled(password.isEmpty && totp.isEmpty)
            Button("Import QR…") { importingQR = true }
            Button("Paste QR") { importClipboardQR() }
        }
        if let saveMessage {
            Text(saveMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        stacked("Split tunnel (include)") {
            TextEditor(text: $model.splitDestinations)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 56, maxHeight: 100)
        }
        Text("Optional. Empty = gateway Office Mode routes.")
            .font(.caption)
            .foregroundStyle(.secondary)

        stacked("Exclude from this VPN") {
            TextEditor(text: $model.excludeDestinations)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 48, maxHeight: 88)
        }

        HStack {
            if model.vpnState == .connected {
                Button("Disconnect") { model.disconnectWork() }
                    .disabled(!model.canDisconnectWork)
            } else {
                Button("Connect") { model.connectWork() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConnectWork)
            }
            Spacer()
            statusPill(connected: model.vpnState == .connected)
        }
    }

    // MARK: - Proxy body

    @ViewBuilder
    private var proxyVPNBody: some View {
        stacked("Name") {
            TextField("Personal proxy", text: $model.proxyConnectionName)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }

        stacked("Subscription URL") {
            TextField("https://…", text: $model.proxySubscriptionURL)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .font(.system(.caption, design: .monospaced))
        }

        stacked("Include (proxy only)") {
            TextEditor(text: $model.proxyInclude)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 56, maxHeight: 100)
        }

        stacked("Exclude from this VPN") {
            TextEditor(text: $model.proxyExclude)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 48, maxHeight: 88)
        }

        stacked("Node") {
            Picker("Node", selection: $model.proxyNodeTag) {
                Text("Auto (urltest)").tag(ProxySubscription.autoTag)
                ForEach(model.sortedProxyNodes) { node in
                    if let ms = model.proxyDelays[node.tag] {
                        Text("\(node.title) · \(ms) ms").tag(node.tag)
                    } else {
                        Text(node.title).tag(node.tag)
                    }
                }
            }
            .labelsHidden()
            .onChange(of: model.proxyNodeTag) { _, _ in
                model.applyProxyNodeSelection()
            }
        }

        HStack(spacing: 12) {
            Button("Refresh subscription") { model.refreshProxySubscription() }
                .disabled(model.isBusy)
            if model.proxyRunning {
                Button("Disconnect") { model.disconnectProxy() }
                    .disabled(!model.canDisconnectProxy)
            } else {
                Button("Connect") { model.connectProxy() }
                    .disabled(!model.canConnectProxy)
            }
            Spacer()
            statusPill(connected: model.proxyRunning)
        }

        Button("Remove connection", role: .destructive) {
            if model.proxyRunning { model.disconnectProxy() }
            model.proxySubscriptionURL = ""
            model.proxyInclude = ""
            model.proxyExclude = ""
            proxyConfigured = false
            proxyExpanded = false
        }
        .disabled(model.isBusy)
    }

    // MARK: - Add sheet

    private var addConnectionSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add connection")
                .font(.title2.weight(.semibold))

            Picker("Type", selection: $addKind) {
                ForEach(AddConnectionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if addKind == .checkpoint {
                Text("Check Point gateway hostname")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("vpn.example.com", text: $newGateway)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text("Display name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Personal proxy", text: $newProxyName)
                    .textFieldStyle(.roundedBorder)
                Text("Subscription URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("https://…", text: $newProxyURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            Spacer()

            HStack {
                Button("Cancel") { showAddSheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { commitAddConnection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCommitAdd)
            }
        }
        .padding(20)
        .frame(width: 420, height: 280)
    }

    private var canCommitAdd: Bool {
        switch addKind {
        case .checkpoint:
            return !newGateway.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .other:
            return !newProxyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func commitAddConnection() {
        switch addKind {
        case .checkpoint:
            let gateway = newGateway.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !gateway.isEmpty else { return }
            model.selectSite(gateway)
            password = ""
            totp = ""
            saveMessage = nil
            workExpanded = true
        case .other:
            let url = newProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return }
            let name = newProxyName.trimmingCharacters(in: .whitespacesAndNewlines)
            model.proxySubscriptionURL = url
            if !name.isEmpty {
                model.proxyConnectionName = name
            }
            proxyConfigured = true
            proxyExpanded = true
            workExpanded = false
        }
        showAddSheet = false
    }

    // MARK: - Helpers

    private var trimmedSite: String {
        model.site.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private func statusPill(connected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.red.opacity(0.85))
                .frame(width: 8, height: 8)
            Text(connected ? "Connected" : "Disconnected")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
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
        .padding(.top, 4)
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
            .padding(.top, 4)
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
