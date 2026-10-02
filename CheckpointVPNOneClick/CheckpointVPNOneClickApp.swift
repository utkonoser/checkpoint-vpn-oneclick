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
                .frame(width: 500, height: 720)
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
            Text(statusLine)
            if let error = model.lastError, !error.isEmpty {
                Text(error)
                    .lineLimit(3)
            }
            Divider()
            if !model.siteChoices.isEmpty {
                Menu("Check Point site") {
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
                .disabled(model.isBusy)
            }
            Button("Connect") { model.connect() }
                .disabled(!model.canConnect)
            Button("Disconnect") { model.disconnect() }
                .disabled(!model.canDisconnect)
            Divider()
            Button("Settings…") {
                openSettings()
                AppWindows.bringSettingsForward()
            }
            Button("Refresh status") { model.refreshStatus() }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .onAppear {
            model.refreshStatus()
            model.refreshSecrets()
        }
    }

    private var statusLine: String {
        if model.isBusy {
            let site = model.site.isEmpty ? "…" : model.site
            return "Working… \(site)"
        }
        if model.vpnState == .connected {
            let site = model.snxStatus.serverName ?? model.site
            return "Connected — \(site)"
        }
        let site = model.site.isEmpty ? "…" : model.site
        return "\(model.vpnState.title) — \(site)"
    }
}
