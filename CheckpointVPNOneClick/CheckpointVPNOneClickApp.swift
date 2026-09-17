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
            Image(model.snapshot.overall.menuBarImageName)
                .renderingMode(.template)
                .id(model.snapshot.overall.menuBarImageName)
                .accessibilityLabel(model.snapshot.overall.title)
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
        let site = model.snapshot.active?.name ?? model.site
        if model.isBusy { return "Working… \(site)" }
        return "\(model.snapshot.overall.title) — \(site)"
    }
}
