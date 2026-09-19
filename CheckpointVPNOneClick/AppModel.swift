import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("site") var site: String = ""
    @AppStorage("username") var username: String = ""

    @Published var snapshot = TracSnapshot(sites: [], active: nil)
    @Published var lastError: String?
    @Published var isBusy = false
    @Published var hasPassword = false
    @Published var hasTOTP = false
    @Published var accessibilityTrusted = false
    @Published var redShieldInstalled = false
    @Published var redShieldConnected = false
    private var timer: Timer?
    private var activeObserver: NSObjectProtocol?

    static var installPath: String {
        NSHomeDirectory() + "/Applications/CheckpointVPNOneClick.app"
    }

    var runningPath: String { Bundle.main.bundlePath }

    var isRunningFromInstall: Bool {
        runningPath == Self.installPath
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
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    var canConnect: Bool {
        !isBusy
            && hasPassword
            && hasTOTP
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && snapshot.overall != .connected
    }

    var canDisconnect: Bool {
        !isBusy && snapshot.overall == .connected
    }

    var menuBarConnected: Bool {
        snapshot.overall == .connected || redShieldConnected
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

    func refreshSecrets() {
        hasPassword = KeychainStore.hasPassword()
        hasTOTP = KeychainStore.hasTOTPSecret()
        refreshPermissions()
    }

    func refreshPermissions() {
        let trusted = CheckpointAX.isTrusted(prompt: false)
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
        }
    }

    func requestAccessibility() {
        _ = CheckpointAX.isTrusted(prompt: true)
        refreshPermissions()
        openAccessibilitySettings()
    }

    func requestAutomation() {
        var error: NSDictionary?
        NSAppleScript(source: #"tell application "System Events" to get name"#)?
            .executeAndReturnError(&error)
        if let message = error?["NSAppleScriptErrorMessage"] as? String {
            lastError = message
        }
        openAutomationSettings()
    }

    func importTOTP(_ raw: String) throws {
        let normalized = try QRCodeImporter.normalizedSecret(raw)
        try KeychainStore.setTOTPSecret(normalized)
        refreshSecrets()
    }

    func refreshStatus() {
        do {
            let new = try TracClient.info()
            if new.overall != snapshot.overall
                || new.active?.name != snapshot.active?.name
                || new.sites != snapshot.sites {
                snapshot = new
            }
        } catch {
            if snapshot.sites.isEmpty == false {
                snapshot = TracSnapshot(sites: [], active: nil)
            }
            if lastError == nil {
                lastError = error.localizedDescription
            }
        }
        let installed = RedShieldVPN.isInstalled()
        if installed != redShieldInstalled {
            redShieldInstalled = installed
        }
        let rs = installed && RedShieldVPN.isConnected()
        if rs != redShieldConnected {
            redShieldConnected = rs
        }
    }

    func connect() {
        guard canConnect else { return }
        isBusy = true
        lastError = nil
        let site = self.site
        let username = self.username
        Task {
            do {
                try await ConnectEngine.connect(site: site, username: username)
                refreshStatus()
            } catch {
                lastError = error.localizedDescription
                refreshStatus()
            }
            isBusy = false
        }
    }

    func disconnect() {
        guard canDisconnect else { return }
        isBusy = true
        lastError = nil
        Task.detached {
            do {
                try ConnectEngine.disconnect()
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

    func swapVPNs(wantRedShield: Bool) {
        guard redShieldInstalled, !isBusy else { return }
        if wantRedShield, redShieldConnected { return }
        if !wantRedShield, !redShieldConnected, snapshot.overall == .connected { return }

        isBusy = true
        lastError = nil
        let site = self.site
        let username = self.username
        Task {
            do {
                if wantRedShield {
                    _ = try await RedShieldVPN.ensureRunning()
                    if snapshot.overall == .connected {
                        try ConnectEngine.disconnect()
                    }
                    try await RedShieldVPN.setConnected(true)
                } else {
                    _ = try await CheckpointAX.ensureGUIRunning()
                    if RedShieldVPN.isConnected() {
                        try await RedShieldVPN.setConnected(false)
                    }
                    try await ConnectEngine.connect(site: site, username: username)
                }
                refreshStatus()
            } catch {
                lastError = error.localizedDescription
                refreshStatus()
            }
            isBusy = false
        }
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func openAutomationSettings() {
        openPrivacyPane("Privacy_Automation")
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
