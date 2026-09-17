import AppKit
import CoreGraphics
import Foundation

enum RedShieldVPN {
    static let defaultAppPath = "/Applications/Red Shield VPN.app"
    static let bundleID = "org.redshieldvpn.redshieldvpn"

    enum Error: Swift.Error, LocalizedError {
        case notInstalled
        case notTrusted
        case timeout(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Red Shield VPN is not installed."
            case .notTrusted:
                return "Accessibility permission is required to switch Red Shield VPN."
            case .timeout(let step):
                return "Timed out waiting for Red Shield (\(step))."
            }
        }
    }

    static func isInstalled(at path: String = defaultAppPath, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    static func isConnected() -> Bool {
        guard isInstalled() else { return false }
        return tunnelIsUp()
    }

    @discardableResult
    static func ensureRunning() async throws -> NSRunningApplication {
        guard isInstalled() else { throw Error.notInstalled }
        if let running = runningApp() {
            running.activate()
            return running
        }
        let url = URL(fileURLWithPath: defaultAppPath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        for _ in 0..<50 {
            if let running = runningApp() { return running }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return app
    }

    static func setConnected(_ want: Bool, timeout: TimeInterval = 20) async throws {
        guard isInstalled() else { throw Error.notInstalled }
        guard CheckpointAX.isTrusted(prompt: true) else { throw Error.notTrusted }
        _ = try await ensureRunning()
        try await Task.sleep(nanoseconds: 700_000_000)
        if tunnelIsUp() == want { return }

        if !clickConnectSwitch() {
            throw Error.timeout("find connect switch")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            if tunnelIsUp() == want { return }
            try await Task.sleep(nanoseconds: 400_000_000)
        }
        throw Error.timeout(want ? "connect" : "disconnect")
    }

    private static func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            ?? NSWorkspace.shared.runningApplications.first {
                $0.localizedName == "Red Shield VPN"
                    || $0.executableURL?.lastPathComponent == "Red Shield VPN"
            }
    }

    /// ponytail: Qt does not expose the toggle in AX. The tunnel helper is the real status.
    /// Ceiling: another protocol that does not spawn `darwin.bash up` would need a new matcher.
    static func tunnelIsUp() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-f", "/Library/Application Support/RedShieldVPN/.*darwin\\.bash up"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func clickConnectSwitch() -> Bool {
        runningApp()?.activate()
        usleep(250_000)
        guard let frame = windowFrame() else { return false }
        // Screenshot 4.1.40: orange connect pill is centered, ~46% down the window.
        // "Local sites" is ~70% down and right-aligned — do not click that.
        let point = CGPoint(x: frame.midX, y: frame.minY + frame.height * 0.46)
        NSLog("RedShieldVPN click connect at \(point) in \(frame)")
        return postClick(point)
    }

    /// CGWindowList bounds use the same top-left space as CGEvent.mouseLocation.
    private static func windowFrame() -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var best: CGRect?
        var bestArea: CGFloat = 0
        for window in info {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Red Shield VPN" else { continue }
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { continue }
            func num(_ key: String) -> CGFloat? {
                if let n = bounds[key] as? CGFloat { return n }
                if let n = bounds[key] as? Double { return CGFloat(n) }
                if let n = bounds[key] as? NSNumber { return CGFloat(truncating: n) }
                return nil
            }
            guard let x = num("X"), let y = num("Y"), let w = num("Width"), let h = num("Height"), w > 100, h > 200 else {
                continue
            }
            let rect = CGRect(x: x, y: y, width: w, height: h)
            let area = rect.width * rect.height
            if area > bestArea {
                bestArea = area
                best = rect
            }
        }
        return best
    }

    private static func postClick(_ point: CGPoint) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return false }
        move.post(tap: .cghidEventTap)
        usleep(20_000)
        down.post(tap: .cghidEventTap)
        usleep(40_000)
        up.post(tap: .cghidEventTap)
        return true
    }
}
