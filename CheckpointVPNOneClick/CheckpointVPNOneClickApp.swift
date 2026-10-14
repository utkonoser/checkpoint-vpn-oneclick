import AppKit
import SwiftUI

@main
struct CheckpointVPNOneClickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(model.menuBarImageName)
                .renderingMode(.template)
                .id(model.menuBarImageName)
                .accessibilityLabel(model.menuBarConnected ? "Connected" : model.vpnState.title)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
                .frame(width: 500, height: 780)
                .onAppear { AppWindows.bringSettingsForward() }
        }
    }
}

enum AppWindows {
    static func bringSettingsForward() {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate()
        raiseSettingsWindows()
        DispatchQueue.main.async {
            NSApp.activate()
            raiseSettingsWindows()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.activate()
            raiseSettingsWindows()
        }
    }

    private static func raiseSettingsWindows() {
        let named = NSApp.windows.filter { isSettings($0) }
        let targets = named.isEmpty
            ? NSApp.windows.filter { window in
                window.canBecomeKey
                    && !window.className.contains("StatusBar")
                    && !window.className.contains("MenuBarExtra")
            }
            : named
        for window in targets {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private static func isSettings(_ window: NSWindow) -> Bool {
        let id = window.identifier?.rawValue.lowercased() ?? ""
        let title = window.title.lowercased()
        return id.contains("settings") || title.contains("settings") || title.contains("настрой")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            Text(model.isBusy ? "Working…" : overviewLine)
                .lineLimit(2)

            if let error = model.lastError, !error.isEmpty {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            Text("Active VPNs")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.activeTunnels.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.activeTunnels) { tunnel in
                    Text("• \(tunnel.title): \(tunnel.detail)")
                        .lineLimit(2)
                }
            }

            Divider()

            if !model.siteChoices.isEmpty {
                Menu("Gateway") {
                    ForEach(model.siteChoices, id: \.self) { site in
                        Button {
                            model.selectSite(site)
                        } label: {
                            if site == model.site {
                                Text("✓ \(site)")
                            } else {
                                Text(site)
                            }
                        }
                    }
                }
                .disabled(model.isBusy || model.vpnState == .connected)
            }

            if model.vpnState == .connected {
                Button("Disconnect \(model.displayWorkName)") { model.disconnectWork() }
                    .disabled(!model.canDisconnectWork)
            } else {
                Button("Connect \(model.displayWorkName)") { model.connectWork() }
                    .disabled(!model.canConnectWork)
            }

            if model.proxyRunning {
                Button("Disconnect \(model.displayProxyName)") { model.disconnectProxy() }
                    .disabled(!model.canDisconnectProxy)
            } else {
                Button("Connect \(model.displayProxyName)") { model.connectProxy() }
                    .disabled(!model.canConnectProxy)
            }

            if model.activeTunnels.count > 1 {
                Button("Disconnect All") { model.disconnectAll() }
                    .disabled(model.isBusy)
            }

            Divider()

            Button("Settings…") {
                openSettings()
                AppWindows.bringSettingsForward()
            }

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .onAppear {
            model.refreshStatus()
            model.refreshSecrets()
        }
    }

    private var overviewLine: String {
        let n = model.activeTunnels.count
        if n == 0 {
            let site = model.site.isEmpty ? "…" : model.site
            return "Idle — \(site)"
        }
        if n == 1, let only = model.activeTunnels.first {
            return "\(only.title) — \(only.detail)"
        }
        return "\(n) VPNs active"
    }
}
