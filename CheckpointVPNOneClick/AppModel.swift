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
    /// One domain/suffix per line — used to export Karing Direct diversion rules.
    @AppStorage("workDomains") var workDomains: String = ""

    @Published var snxStatus = SnxStatus.disconnected
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var hasPassword = false
    @Published var hasTOTP = false
    @Published var snxInstalled = false
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

    /// Normalized domain suffixes for Karing / docs (lowercase, no leading dots).
    var workDomainList: [String] {
        Self.parseWorkDomains(workDomains)
    }

    static nonisolated func parseWorkDomains(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
    }

    /// Clipboard text for Karing custom diversion (Domain Suffix → Direct).
    func karingDirectRulesText() -> String {
        Self.karingDirectRulesText(domains: workDomainList)
    }

    static nonisolated func karingDirectRulesText(domains: [String]) -> String {
        guard !domains.isEmpty else {
            return """
            # Add work domains in Settings first (one per line), then Copy again.
            # In Karing: Diversion → Custom diversion group → Domain Suffix = each line below → action Direct.
            """
        }
        var lines: [String] = [
            "# Paste into Karing → Diversion → Custom diversion group (e.g. work-vpn).",
            "# For each Domain Suffix below, set action to Direct.",
            "# Also set Diversion → Country/Region so geoip for Russia (RF) uses Direct.",
            "# Domain suffixes:",
        ]
        lines.append(contentsOf: domains)
        return lines.joined(separator: "\n")
    }

    init() {
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
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.restartStaleDaemonIfNeeded(reason: "launch")
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
                        NSLog("snx-rs daemon restarted (\(reason))")
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
        guard snxInstalled, !isBusy else { return }
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

    var canConnect: Bool {
        !isBusy
            && snxInstalled
            && hasPassword
            && hasTOTP
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && vpnState != .connected
    }

    var canDisconnect: Bool {
        !isBusy && snxInstalled
    }

    var menuBarConnected: Bool {
        vpnState == .connected
    }

    var menuBarImageName: String {
        menuBarConnected ? "MenuBarConnected" : "MenuBarDisconnected"
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
        if !names.contains(trimmed) {
            names.insert(trimmed, at: 0)
            knownSitesRaw = names.joined(separator: "\n")
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

    @discardableResult
    func copyKaringRulesToClipboard() -> Bool {
        let text = karingDirectRulesText()
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
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
            await MainActor.run {
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

    func connect() {
        guard canConnect else { return }
        isBusy = true
        lastError = nil
        let site = self.site
        let username = self.username
        let loginType = self.snxLoginType
        let ignoreCert = self.snxIgnoreServerCert
        rememberSite(site)
        Task {
            do {
                try await ConnectEngine.connect(
                    site: site,
                    username: username,
                    loginType: loginType,
                    ignoreServerCert: ignoreCert
                )
                refreshStatus()
            } catch {
                lastError = Self.friendlyConnectError(error)
                refreshStatus()
            }
            isBusy = false
        }
    }

    func disconnect() {
        guard !isBusy, snxInstalled else { return }
        isBusy = true
        lastError = nil
        Task.detached {
            do {
                try ConnectEngine.disconnect()
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

    static func friendlyConnectError(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("Internal IPSec certificate") {
            return """
            \(message) — often after sleep with a half-dead snx-rs tunnel. \
            Tap Disconnect, then Connect again. If it persists: \
            sudo launchctl kickstart -k system/com.github.snx-rs \
            (or Restart snx-rs daemon in Settings).
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
