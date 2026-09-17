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
                .accessibilityLabel(model.menuBarConnected ? "Connected" : model.snapshot.overall.title)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
                .frame(width: 500, height: 680)
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
            Button("Connect") { model.connect() }
                .disabled(!model.canConnect)
            Button("Disconnect") { model.disconnect() }
                .disabled(!model.canDisconnect)
            Button(model.redShieldConnected ? "Switch to Check Point" : "Switch to Red Shield") {
                model.swapVPNs(wantRedShield: !model.redShieldConnected)
            }
            .disabled(model.isBusy || !model.redShieldInstalled)
            Divider()
            Button("Settings…") {
                openSettings()
                AppWindows.bringSettingsForward()
            }
            Button("Refresh status") { model.refreshStatus() }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .onAppear { model.refreshStatus() }
    }

    private var statusLine: String {
        if model.isBusy {
            if model.redShieldConnected { return "Working… Red Shield" }
            let site = model.snapshot.active?.name ?? model.site
            return "Working… \(site)"
        }
        if model.snapshot.overall == .connected {
            let site = model.snapshot.active?.name ?? model.site
            return "Connected — \(site)"
        }
        if model.redShieldConnected {
            return "Connected — Red Shield"
        }
        let site = model.snapshot.active?.name ?? model.site
        return "\(model.snapshot.overall.title) — \(site)"
    }
}
