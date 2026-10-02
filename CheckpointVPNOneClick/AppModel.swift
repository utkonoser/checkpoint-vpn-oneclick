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

    @Published var snxStatus = SnxStatus.disconnected
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var hasPassword = false
    @Published var hasTOTP = false
    @Published var snxInstalled = false
    @Published var accessibilityTrusted = false
    @Published var redShieldInstalled = false
    @Published var redShieldConnected = false
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

    init() {
        refreshStatus()
        refreshSecrets()
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
                self?.refreshPermissions()
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
                self?.refreshPermissions()
            }
        }
        // After lid-close the snx-rs daemon keeps a dead tunnel; drop it on wake so the next
        // Connect starts clean (avoids stale IPsec / certificate / 503 MFA failures).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
        // Same idea as `sudo pkill snx-rs`: if an idle daemon is already running at launch,
        // restart it once (admin password) so Connect is not stuck on a half-dead process.
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

    /// Restart root snx-rs when we are not Connected. Needs admin (same as sudo pkill).
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
                    // Canceling the password dialog is fine — Connect can still be tried.
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
        // Always offer Disconnect when snx-rs is present — recovers hung tunnels even if
        // status last reported Idle (snxctl gateway probe used to hide Connected).
        !isBusy && snxInstalled
    }

    var menuBarConnected: Bool {
        vpnState == .connected || redShieldConnected
    }

    var menuBarImageName: String {
        menuBarConnected ? "MenuBarConnected" : "MenuBarDisconnected"
    }

    var redShieldToggle: Binding<Bool> {
        Binding(
            get: { self.redShieldConnected },
            set: { self.swapVPNs(wantRedShield: $0) }
        )
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
        refreshPermissions()
    }

    func refreshPermissions() {
        // Accessibility is only needed for Red Shield CGEvent clicks.
        let trusted = RedShieldVPN.isTrusted(prompt: false)
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
        }
    }

    func requestAccessibility() {
        _ = RedShieldVPN.isTrusted(prompt: true)
        refreshPermissions()
        openAccessibilitySettings()
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

        // Socket IPC is fast, but keep it off the main actor so a stuck daemon cannot freeze the menu.
        Task.detached(priority: .utility) {
            let snx: Result<SnxStatus, Error>
            if installed {
                snx = Result { try SnxClient.status() }
            } else {
                snx = .success(.disconnected)
            }
            let rsInstalled = RedShieldVPN.isInstalled()
            let rsConnected = rsInstalled && RedShieldVPN.isConnected()
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
                    // Clear stale daemon/gateway errors once status works again.
                    if let err = self.lastError,
                       err.localizedCaseInsensitiveContains("clients/")
                        || err.localizedCaseInsensitiveContains("daemon")
                        || err.localizedCaseInsensitiveContains("snxctl status") {
                        self.lastError = nil
                    }
                case .failure(let error):
                    // Do not flip Connected → Idle on a transient socket blip; only record idle when sure.
                    if case SnxClient.Error.daemonUnavailable = error {
                        if self.snxStatus.state != .idle {
                            self.snxStatus = .disconnected
                        }
                    }
                    // Avoid spamming the menu every 2s; keep one short note.
                    if !self.isBusy {
                        self.lastError = error.localizedDescription
                    }
                }
                if rsInstalled != self.redShieldInstalled {
                    self.redShieldInstalled = rsInstalled
                }
                if rsConnected != self.redShieldConnected {
                    self.redShieldConnected = rsConnected
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
                // Work VPN and Red Shield fight over routes; after sleep RS often comes back first.
                if RedShieldVPN.isConnected() {
                    try await RedShieldVPN.setConnected(false)
                }
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
        // Always allow an explicit disconnect attempt when not busy — recovers hung tunnels
        // even if the last status poll failed to report Connected.
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

    func swapVPNs(wantRedShield: Bool) {
        guard redShieldInstalled, !isBusy else { return }
        if wantRedShield, redShieldConnected { return }
        if !wantRedShield, !redShieldConnected, vpnState == .connected { return }

        isBusy = true
        lastError = nil
        let site = self.site
        let username = self.username
        let loginType = self.snxLoginType
        let ignoreCert = self.snxIgnoreServerCert
        Task {
            do {
                if wantRedShield {
                    _ = try await RedShieldVPN.ensureRunning()
                    // Always tear down Check Point first (socket disconnect; no gateway needed).
                    try? ConnectEngine.disconnect()
                    self.snxStatus = .disconnected
                    try await RedShieldVPN.setConnected(true)
                } else {
                    if RedShieldVPN.isConnected() {
                        try await RedShieldVPN.setConnected(false)
                    }
                    try await ConnectEngine.connect(
                        site: site,
                        username: username,
                        loginType: loginType,
                        ignoreServerCert: ignoreCert
                    )
                }
                refreshStatus()
            } catch {
                lastError = Self.friendlyConnectError(error)
                refreshStatus()
            }
            isBusy = false
        }
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func friendlyConnectError(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("Internal IPSec certificate") {
            return """
            \(message) — often after sleep with a half-dead snx-rs tunnel or Red Shield still up. \
            Tap Disconnect, turn Red Shield off, then Connect again. If it persists: \
            sudo launchctl kickstart -k system/com.github.snx-rs
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

    private func openPrivacyPane(_ anchor: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }
}
