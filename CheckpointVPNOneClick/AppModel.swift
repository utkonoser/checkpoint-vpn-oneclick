import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("site") var site: String = ""
    @AppStorage("username") var username: String = ""
    @AppStorage("snxLoginType") var snxLoginType: String = SnxClient.defaultLoginType
    /// Corporate gateways often fail snx-rs internal IPsec CA checks without this.
    @AppStorage("snxIgnoreServerCert") var snxIgnoreServerCert: Bool = true
    @AppStorage("knownSites") private var knownSitesRaw: String = ""
    /// One CIDR/IP/hostname per line — when set, only these go through the tunnel (`add-routes`).
    @AppStorage("workDomains") var splitDestinations: String = ""
    /// One CIDR/IP/hostname per line — stay off the tunnel (`ignore-routes` / filtered from add-routes).
    @AppStorage("excludeDestinations") var excludeDestinations: String = ""
    @AppStorage("workConnectionName") var workConnectionName: String = "Check Point"
    @AppStorage("proxyConnectionName") var proxyConnectionName: String = "Personal proxy"
    @AppStorage("proxySubscriptionURL") var proxySubscriptionURL: String = ProxySubscription.defaultURL
    @AppStorage("proxyInclude") var proxyInclude: String = ""
    /// One CIDR/IP/hostname per line — stay off the personal proxy even if listed in include.
    @AppStorage("proxyExclude") var proxyExclude: String = ""
    @AppStorage("proxyNodeTag") var proxyNodeTag: String = ProxySubscription.autoTag

    var displayWorkName: String {
        let n = workConnectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Check Point" : n
    }

    var displayProxyName: String {
        let n = proxyConnectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Personal proxy" : n
    }

    @Published var snxStatus = SnxStatus.disconnected
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var hasPassword = false
    @Published var hasTOTP = false
    @Published var snxInstalled = false
    @Published var proxyNodes: [ProxySubscription.Node] = []
    @Published var proxyDelays: [String: Int] = [:]
    @Published var proxyRunning = false
    @Published var proxyNow: String?
    @Published var proxyDelayMs: Int?
    private var lastProxyDelayProbeAt: Date?
    private var timer: Timer?
    private var activeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    /// Avoid stacking admin password prompts (launch + wake within a minute).
    private var lastDaemonRestartAt: Date?

    static var installPath: String {
        NSHomeDirectory() + "/Applications/CheckpointVPNOneClick.app"
    }

    var runningPath: String { Bundle.main.bundlePath }

    var isRunningFromInstall: Bool {
        runningPath == Self.installPath
    }

    var vpnState: VPNConnectionState {
        snxStatus.state
    }

    var siteChoices: [String] {
        var names = knownSitesRaw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let current = site.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !names.contains(current) {
            names.insert(current, at: 0)
        }
        return names
    }

    var parsedSplitDestinations: SplitDestinations.Parsed {
        SplitDestinations.parse(splitDestinations)
    }

    /// Node picker order: lowest measured ping first.
    var sortedProxyNodes: [ProxySubscription.Node] {
        ProxySubscription.sortedByDelay(proxyNodes, delays: proxyDelays)
    }

    init() {
        proxyNodes = ProxySubscription.loadCachedNodes()
        refreshStatus()
        refreshSecrets()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }

    private func handleWake() {
        guard snxInstalled, !isBusy else {
            refreshStatus()
            return
        }
        restartStaleDaemonIfNeeded(reason: "wake")
    }

    func restartStaleDaemonIfNeeded(reason: String) {
        guard snxInstalled, !isBusy else { return }
        if vpnState == .connected { return }
        if let last = lastDaemonRestartAt, Date().timeIntervalSince(last) < 60 { return }

        isBusy = true
        Task.detached {
            do {
                let restarted = try SnxClient.refreshStaleDaemonIfNeeded()
                await MainActor.run {
                    if restarted {
                        self.lastDaemonRestartAt = Date()
                        self.lastError = nil
                        NSLog("tunnel helper restarted (\(reason))")
                    }
                    self.snxStatus = .disconnected
                    self.refreshStatus()
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    let message = error.localizedDescription
                    if !message.localizedCaseInsensitiveContains("canceled") {
                        self.lastError = message
                    }
                    self.refreshStatus()
                    self.isBusy = false
                }
            }
        }
    }

    func restartDaemonManually() {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        Task.detached {
            do {
                try SnxClient.restartDaemon()
                await MainActor.run {
                    self.lastDaemonRestartAt = Date()
                    self.snxStatus = .disconnected
                    self.refreshStatus()
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.refreshStatus()
                    self.isBusy = false
                }
            }
        }
    }

    func installHelperManually() {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        Task.detached {
            do {
                try SnxClient.installHelper()
                await MainActor.run {
                    self.lastDaemonRestartAt = Date()
                    self.snxStatus = .disconnected
                    self.refreshStatus()
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.refreshStatus()
                    self.isBusy = false
                }
            }
        }
    }

    var canConnectWork: Bool {
        !isBusy
            && snxInstalled
            && hasPassword
            && hasTOTP
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && vpnState != .connected
    }

    var canDisconnectWork: Bool {
        !isBusy && snxInstalled && vpnState == .connected
    }

    var canConnectProxy: Bool {
        !isBusy && ProxyClient.bundledPayloadURL() != nil && !proxyRunning
    }

    var canDisconnectProxy: Bool {
        !isBusy && proxyRunning
    }

    /// Any tunnel up — for menu bar icon.
    var menuBarConnected: Bool {
        vpnState == .connected || proxyRunning
    }

    var menuBarImageName: String {
        menuBarConnected ? "MenuBarConnected" : "MenuBarDisconnected"
    }

    struct ActiveTunnel: Identifiable, Equatable {
        var id: String
        var title: String
        var detail: String
    }

    var activeTunnels: [ActiveTunnel] {
        var list: [ActiveTunnel] = []
        if vpnState == .connected {
            let name = snxStatus.serverName ?? site
            let ip = snxStatus.ipAddress.map { " · \($0)" } ?? ""
            list.append(ActiveTunnel(id: "work", title: displayWorkName, detail: "\(name)\(ip)"))
        }
        if proxyRunning {
            let now = proxyNow ?? proxyNodeTag
            let latency = proxyDelayMs.map { " · \($0) ms" } ?? ""
            list.append(ActiveTunnel(id: "proxy", title: displayProxyName, detail: "\(now)\(latency)"))
        }
        return list
    }

    func selectSite(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != site else { return }
        site = trimmed
        rememberSite(trimmed)
        refreshSecrets()
    }

    func rememberSite(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var names = knownSitesRaw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let idx = names.firstIndex(of: trimmed) {
            names.remove(at: idx)
        }
        names.insert(trimmed, at: 0)
        knownSitesRaw = names.joined(separator: "\n")
        if site != trimmed {
            site = trimmed
        }
    }

    func forgetSite(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var names = knownSitesRaw
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != trimmed }
        knownSitesRaw = names.joined(separator: "\n")
        if site == trimmed {
            site = names.first ?? ""
            refreshSecrets()
        }
    }

    func refreshSecrets() {
        let current = site.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            try? KeychainStore.migrateLegacySecretsIfNeeded(to: current)
            hasPassword = KeychainStore.hasPassword(site: current)
            hasTOTP = KeychainStore.hasTOTPSecret(site: current)
            rememberSite(current)
        } else {
            hasPassword = false
            hasTOTP = false
        }
    }

    func importTOTP(_ raw: String) throws {
        let current = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { throw KeychainStore.Error.missingSite }
        let normalized = try QRCodeImporter.normalizedSecret(raw)
        try KeychainStore.setTOTPSecret(normalized, site: current)
        refreshSecrets()
    }

    func refreshStatus() {
        let installed = SnxClient.isInstalled()
        if installed != snxInstalled {
            snxInstalled = installed
        }

        Task.detached(priority: .utility) {
            let snx: Result<SnxStatus, Error>
            if installed {
                snx = Result { try SnxClient.status() }
            } else {
                snx = .success(.disconnected)
            }
            let running = ProxyClient.isRunning()
            let proxyInfo = running ? ProxyClient.proxyStatus() : (nil, nil)
            let delays = running ? ProxyClient.allProxyDelays() : [:]
            await MainActor.run {
                let wasRunning = self.proxyRunning
                self.proxyRunning = running
                self.proxyNow = proxyInfo.0
                self.proxyDelayMs = proxyInfo.1
                if running {
                    if !delays.isEmpty {
                        self.proxyDelays = delays
                    }
                    let due = self.lastProxyDelayProbeAt.map { Date().timeIntervalSince($0) > 180 } ?? true
                    if !wasRunning || due {
                        self.lastProxyDelayProbeAt = Date()
                        ProxyClient.probeURLTestDelays()
                    }
                } else if wasRunning {
                    self.lastProxyDelayProbeAt = nil
                }
                switch snx {
                case .success(let new):
                    if new != self.snxStatus {
                        self.snxStatus = new
                    }
                    if self.site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let server = new.serverName, !server.isEmpty {
                        self.site = server
                        self.refreshSecrets()
                    }
                    if let err = self.lastError,
                       err.localizedCaseInsensitiveContains("clients/")
                        || err.localizedCaseInsensitiveContains("daemon")
                        || err.localizedCaseInsensitiveContains("snxctl status") {
                        self.lastError = nil
                    }
                case .failure(let error):
                    if case SnxClient.Error.daemonUnavailable = error {
                        if self.snxStatus.state != .idle {
                            self.snxStatus = .disconnected
                        }
                    }
                    if !self.isBusy {
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    func connectWork() {
        guard canConnectWork else { return }
        isBusy = true
        lastError = nil
        let site = self.site
        let username = self.username
        let loginType = self.snxLoginType
        let ignoreCert = self.snxIgnoreServerCert
        let destinations = self.splitDestinations
        let excludes = self.excludeDestinations
        // If proxy nodes are known (running or cached), keep their egress off the work tunnel.
        let extraHosts = ProxySubscription.serverHosts(in: proxyNodes)
        rememberSite(site)
        Task {
            do {
                try await ConnectEngine.connectWork(
                    site: site,
                    username: username,
                    loginType: loginType,
                    ignoreServerCert: ignoreCert,
                    splitDestinations: destinations,
                    excludeDestinations: excludes,
                    extraIgnoreHosts: extraHosts
                )
                refreshStatus()
            } catch {
                lastError = Self.friendlyConnectError(error)
                refreshStatus()
            }
            isBusy = false
        }
    }

    func disconnectWork() {
        guard canDisconnectWork else { return }
        isBusy = true
        lastError = nil
        Task.detached {
            do {
                try ConnectEngine.disconnectWork()
                await MainActor.run {
                    self.snxStatus = .disconnected
                    self.refreshStatus()
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.refreshStatus()
                    self.isBusy = false
                }
            }
        }
    }

    func connectProxy() {
        guard canConnectProxy else { return }
        isBusy = true
        lastError = nil
        let url = proxySubscriptionURL
        let include = proxyInclude
        let exclude = proxyExclude
        let tag = proxyNodeTag
        Task {
            do {
                let selected = try await ConnectEngine.connectProxy(
                    subscriptionURL: url,
                    includeDestinations: include,
                    excludeDestinations: exclude,
                    nodeTag: tag
                )
                proxyNodes = ProxySubscription.loadCachedNodes()
                proxyNodeTag = selected
                refreshStatus()
            } catch {
                lastError = error.localizedDescription
                refreshStatus()
            }
            isBusy = false
        }
    }

    func disconnectProxy() {
        guard canDisconnectProxy else { return }
        isBusy = true
        lastError = nil
        Task.detached {
            do {
                try ConnectEngine.disconnectProxy()
                await MainActor.run {
                    self.refreshStatus()
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.refreshStatus()
                    self.isBusy = false
                }
            }
        }
    }

    func disconnectAll() {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        Task.detached {
            try? ConnectEngine.disconnectAll()
            await MainActor.run {
                self.snxStatus = .disconnected
                self.refreshStatus()
                self.isBusy = false
            }
        }
    }

    func refreshProxySubscription() {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        let url = proxySubscriptionURL
        let tag = proxyNodeTag
        Task.detached {
            do {
                let text = try ProxySubscription.fetch(urlString: url)
                let parsed = ProxySubscription.parse(text)
                guard !parsed.nodes.isEmpty else { throw ProxySubscription.Error.empty }
                var selected = tag
                if selected != ProxySubscription.autoTag,
                   !parsed.nodes.contains(where: { $0.tag == selected }) {
                    selected = ProxySubscription.autoTag
                }
                _ = try ProxySubscription.save(parsed: parsed, selectedTag: selected)
                await MainActor.run {
                    self.proxyNodes = parsed.nodes
                    self.proxyNodeTag = selected
                    self.isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isBusy = false
                }
            }
        }
    }

    func applyProxyNodeSelection() {
        let tag = proxyNodeTag
        guard proxyRunning else { return }
        Task.detached {
            try? ProxyClient.selectNode(tag: tag)
            await MainActor.run { self.refreshStatus() }
        }
    }

    static func friendlyConnectError(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("Internal IPSec certificate") {
            return """
            \(message) — often after sleep with a half-dead tunnel helper. \
            Tap Disconnect, then Connect again. If it persists: \
            Repair tunnel helper in Settings (or sudo launchctl kickstart -k system/local.checkpointvpn.tunnel).
            """
        }
        if message.localizedCaseInsensitiveContains("503")
            || message.localizedCaseInsensitiveContains("Challenge code") {
            return """
            \(message) — gateway rejected OTP/password (common right after sleep). \
            Wait for a fresh TOTP second, Disconnect, then Connect again.
            """
        }
        return message
    }
}
