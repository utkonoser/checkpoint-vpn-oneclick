import Foundation

/// Install / control the embedded sing-box personal proxy LaunchDaemon.
enum ProxyClient {
    static let launchdLabel = "local.checkpointvpn.proxy"
    static let systemSupportDir = "/Library/Application Support/CheckpointVPNProxy"
    static let systemBinaryPath = systemSupportDir + "/sing-box"
    static let systemCtlPath = systemSupportDir + "/checkpoint-vpn-proxyctl"
    static let controlSocket = "/var/run/checkpoint-vpn-proxy.sock"

    enum Error: Swift.Error, LocalizedError {
        case notBundled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "Proxy helper is missing from the app. Rebuild with Scripts/build-sing-box.sh."
            case .failed(let m):
                return m
            }
        }
    }

    static func isHelperInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: systemBinaryPath)
            && FileManager.default.isExecutableFile(atPath: systemCtlPath)
    }

    static func bundledPayloadURL() -> URL? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("ProxyHelper", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/ProxyHelper", isDirectory: true),
        ]
        for case let url? in candidates {
            let bin = url.appendingPathComponent("sing-box")
            let ctl = url.appendingPathComponent("checkpoint-vpn-proxyctl")
            let plist = url.appendingPathComponent("local.checkpointvpn.proxy.plist")
            if FileManager.default.isExecutableFile(atPath: bin.path),
               FileManager.default.isExecutableFile(atPath: ctl.path),
               FileManager.default.fileExists(atPath: plist.path) {
                return url
            }
        }
        return nil
    }

    private static func installScriptURL() -> URL? {
        if let url = Bundle.main.url(forResource: "install-proxy-helper", withExtension: "sh") {
            return url
        }
        let inResources = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/install-proxy-helper.sh")
        if FileManager.default.isReadableFile(atPath: inResources.path) {
            return inResources
        }
        return nil
    }

    static func installHelper() throws {
        guard let payload = bundledPayloadURL() else { throw Error.notBundled }
        guard let installer = installScriptURL() else {
            throw Error.failed("install-proxy-helper.sh is missing from the app bundle.")
        }
        let escapedInstaller = installer.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedPayload = payload.path.replacingOccurrences(of: "'", with: "'\\''")
        try runAdminShell("'/bin/bash' '\(escapedInstaller)' '\(escapedPayload)'")
    }

    /// Admin password only when the root controller is not installed yet.
    static func ensureController() throws {
        if FileManager.default.fileExists(atPath: controlSocket) { return }
        try installHelper()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: controlSocket) { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw Error.failed("Proxy controller did not start.")
    }

    /// Apply config, start sing-box, install include routes. No admin prompt if the controller is up.
    static func start(configURL: URL, includeCIDRs: [String]) throws {
        try ensureController()
        try control("apply-config \(configURL.path)")
        try control("start")
        if !includeCIDRs.isEmpty {
            try control("set-routes \(includeCIDRs.joined(separator: " "))")
        }
    }

    static func stop() throws {
        if FileManager.default.fileExists(atPath: controlSocket) {
            try control("stop")
            if !isRunning() { return }
        }
        // Still up: the LaunchDaemon is sing-box itself (no controller). One admin
        // install replaces it with the socket controller and does not leave sing-box running.
        try installHelper()
        if FileManager.default.fileExists(atPath: controlSocket) {
            try? control("stop")
        }
        if isRunning() {
            throw Error.failed("Personal proxy is still running.")
        }
    }

    private static func control(_ line: String) throws {
        let reply = try socketCommand(line)
        guard reply == "ok" || reply.hasPrefix("ok ") else {
            throw Error.failed(reply.isEmpty ? "Proxy controller failed" : reply)
        }
    }

    private static func socketCommand(_ line: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Error.failed("socket() failed") }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = controlSocket.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw Error.failed("socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!, count: pathBytes.count)
                }
            }
        }
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw Error.failed("Proxy controller is not reachable")
        }

        var payload = Data((line + "\n").utf8)
        let wrote = payload.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return Darwin.write(fd, base, payload.count)
        }
        guard wrote == payload.count else { throw Error.failed("write to proxy controller failed") }

        var buf = [UInt8](repeating: 0, count: 512)
        let n = Darwin.read(fd, &buf, buf.count)
        guard n > 0 else { throw Error.failed("empty proxy controller reply") }
        return String(bytes: buf.prefix(n), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func selectNode(tag: String) throws {
        let name = (tag == "auto" || tag.isEmpty) ? ProxySubscription.autoTag : tag
        var req = URLRequest(
            url: URL(string: "http://127.0.0.1:\(ProxySubscription.clashAPIPort)/proxies/\(ProxySubscription.selectorTag)")!
        )
        req.httpMethod = "PUT"
        req.setValue("Bearer \(ProxySubscription.clashAPISecret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        let sem = DispatchSemaphore(value: 0)
        var status = 0
        var body = ""
        URLSession.shared.dataTask(with: req) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 5)
        guard (200..<300).contains(status) else {
            throw Error.failed("Clash API select failed (\(status)): \(body)")
        }
    }

    /// Now / delay for the selector or a named proxy.
    static func proxyStatus() -> (now: String?, delay: Int?) {
        var req = URLRequest(
            url: URL(string: "http://127.0.0.1:\(ProxySubscription.clashAPIPort)/proxies/\(ProxySubscription.selectorTag)")!
        )
        req.setValue("Bearer \(ProxySubscription.clashAPISecret)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 2
        let sem = DispatchSemaphore(value: 0)
        var now: String?
        var delay: Int?
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sem.signal() }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            now = obj["now"] as? String
            if let hist = obj["history"] as? [[String: Any]], let last = hist.last {
                delay = last["delay"] as? Int
            }
        }.resume()
        _ = sem.wait(timeout: .now() + 2)
        return (now, delay)
    }

    static func isRunning() -> Bool {
        let byName = run(executable: "/usr/bin/pgrep", arguments: ["-x", "sing-box"], timeout: 2)
        return byName.status == 0
    }

    private static func runAdminShell(_ shell: String) throws {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let result = run(executable: "/usr/bin/osascript", arguments: ["-e", script], timeout: 180)
        if result.status != 0 {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("User canceled")
                || message.localizedCaseInsensitiveContains("(-128)") {
                throw Error.failed("Admin password canceled — proxy helper was not updated.")
            }
            throw Error.failed(message.isEmpty ? "Proxy helper command failed" : message)
        }
    }

    private static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (1, error.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return (124, "Timed out")
        }
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, (out + "\n" + err).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
