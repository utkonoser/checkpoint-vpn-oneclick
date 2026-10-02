import Foundation

enum VPNConnectionState: String, Equatable {
    case idle
    case connecting
    case connected
    case unknown

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .unknown: return "Unknown"
        }
    }
}

struct SnxStatus: Equatable {
    var state: VPNConnectionState
    var serverName: String?
    var userName: String?
    var ipAddress: String?
    var raw: String

    static let disconnected = SnxStatus(state: .idle, serverName: nil, userName: nil, ipAddress: nil, raw: "")
}

enum SnxClient {
    static let defaultLoginType = "vpn_VPN_RA"
    /// Own branded daemon socket (vendored snx-rs fork).
    static let socketPath = "/var/run/checkpoint-vpn.sock"
    static let launchdLabel = "local.checkpointvpn.tunnel"
    static let systemSupportDir = "/Library/Application Support/CheckpointVPNTunnel"
    static let systemCtlPath = systemSupportDir + "/checkpoint-vpnctl"
    static let systemDaemonPath = systemSupportDir + "/CheckpointVPNTunnel"

    enum Error: Swift.Error, LocalizedError {
        case notInstalled
        case daemonUnavailable(String)
        case failed(String)
        case notPersisted

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "Tunnel helper is not installed. Use Settings → Install tunnel helper… (admin password once)."
            case .daemonUnavailable(let message):
                return "Tunnel helper is not reachable (\(message)). Try Repair tunnel helper…"
            case .failed(let message):
                return message
            case .notPersisted:
                return "Could not write tunnel connect config."
            }
        }
    }

    /// True when the system helper is present, the socket exists, or the app still has a payload to install.
    static func isInstalled() -> Bool {
        isHelperInstalled() || FileManager.default.fileExists(atPath: socketPath) || bundledHelperPayloadURL() != nil
    }

    static func isHelperInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: systemDaemonPath)
            && FileManager.default.isExecutableFile(atPath: systemCtlPath)
    }

    /// Directory containing CheckpointVPNTunnel, checkpoint-vpnctl, and the launchd plist.
    static func bundledHelperPayloadURL() -> URL? {
        let fm = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("TunnelHelper", isDirectory: true),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/TunnelHelper", isDirectory: true),
            // Dev tree: repo TunnelHelper/dist next to an unpackaged build is not available —
            // install.sh copies dist into the app bundle.
        ]
        for case let url? in candidates {
            let daemon = url.appendingPathComponent("CheckpointVPNTunnel")
            let ctl = url.appendingPathComponent("checkpoint-vpnctl")
            let plist = url.appendingPathComponent("local.checkpointvpn.tunnel.plist")
            if fm.isExecutableFile(atPath: daemon.path),
               fm.isExecutableFile(atPath: ctl.path),
               fm.fileExists(atPath: plist.path) {
                return url
            }
        }
        return nil
    }

    static func ctlPath() -> String? {
        if FileManager.default.isExecutableFile(atPath: systemCtlPath) {
            return systemCtlPath
        }
        if let bundled = bundledHelperPayloadURL()?
            .appendingPathComponent("checkpoint-vpnctl"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        let candidates = [
            "/usr/local/bin/checkpoint-vpnctl",
            "\(NSHomeDirectory())/.local/bin/checkpoint-vpnctl",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return which("checkpoint-vpnctl")
    }

    /// Fast local status via daemon socket — does not contact the VPN gateway.
    static func status() throws -> SnxStatus {
        let response = try daemonRequest("GetStatus")
        return parseDaemonStatus(response)
    }

    static func connect(
        server: String,
        loginType: String,
        username: String,
        password: String,
        mfaCode: String,
        ignoreServerCert: Bool = true
    ) throws {
        if !isHelperInstalled() {
            try installHelper()
        }
        guard let ctl = ctlPath() else { throw Error.notInstalled }
        let configURL = try writeConnectConfig(
            server: server,
            loginType: loginType,
            username: username,
            password: password,
            mfaCode: mfaCode,
            ignoreServerCert: ignoreServerCert
        )
        defer { try? FileManager.default.removeItem(at: configURL) }

        let result = run(executable: ctl, arguments: ["-c", configURL.path, "connect"], timeout: 90)
        if result.status != 0 {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.failed(message.isEmpty ? "checkpoint-vpnctl connect failed (\(result.status))" : message)
        }
    }

    /// Local disconnect via daemon socket — works even when the VPN gateway is unreachable.
    static func disconnect() throws {
        _ = try daemonRequest("Disconnect")
    }

    /// True when our tunnel daemon process is alive.
    static func isDaemonProcessRunning() -> Bool {
        let byName = run(executable: "/usr/bin/pgrep", arguments: ["-x", "CheckpointVPNTunnel"], timeout: 2)
        if byName.status == 0 { return true }
        let byArgs = run(
            executable: "/usr/bin/pgrep",
            arguments: ["-f", "CheckpointVPNTunnel -m command"],
            timeout: 2
        )
        return byArgs.status == 0
    }

    /// Install LaunchDaemon + binaries from the app bundle (admin password once).
    static func installHelper() throws {
        guard let payload = bundledHelperPayloadURL() else {
            throw Error.failed(
                "Tunnel helper payload is missing from the app. Rebuild with Scripts/build-tunnel-helper.sh."
            )
        }
        guard let installer = installTunnelHelperScriptURL() else {
            throw Error.failed("install-tunnel-helper.sh is missing from the app bundle.")
        }
        let escapedInstaller = installer.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedPayload = payload.path.replacingOccurrences(of: "'", with: "'\\''")
        try runAdminShell("'/bin/bash' '\(escapedInstaller)' '\(escapedPayload)'")
        try waitForDaemon(timeout: 12)
    }

    private static func installTunnelHelperScriptURL() -> URL? {
        if let url = Bundle.main.url(forResource: "install-tunnel-helper", withExtension: "sh") {
            return url
        }
        let inResources = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/install-tunnel-helper.sh")
        if FileManager.default.isReadableFile(atPath: inResources.path) {
            return inResources
        }
        let repo = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/install-tunnel-helper.sh")
        return FileManager.default.isReadableFile(atPath: repo.path) ? repo : nil
    }

    /// Kill + respawn our LaunchDaemon. Needs an admin password prompt.
    static func restartDaemon() throws {
        if !isHelperInstalled(), bundledHelperPayloadURL() != nil {
            try installHelper()
            return
        }
        let shell = """
        /bin/launchctl kickstart -k system/\(launchdLabel) 2>/dev/null \
          || (/usr/bin/killall CheckpointVPNTunnel 2>/dev/null; /bin/sleep 1; /bin/launchctl kickstart system/\(launchdLabel))
        """
        try runAdminShell(shell)
        try waitForDaemon(timeout: 8)
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
                throw Error.failed("Admin password canceled — tunnel helper was not updated.")
            }
            throw Error.failed(message.isEmpty ? "Failed to update tunnel helper" : message)
        }
    }

    /// Restart the daemon when idle so a half-dead post-sleep process cannot break Connect.
    @discardableResult
    static func refreshStaleDaemonIfNeeded() throws -> Bool {
        if let status = try? status(), status.state == .connected {
            return false
        }
        guard isDaemonProcessRunning() || FileManager.default.fileExists(atPath: socketPath) else {
            // No daemon yet — try installing from the bundle once.
            if !isHelperInstalled(), bundledHelperPayloadURL() != nil {
                try installHelper()
                return true
            }
            return false
        }
        try? disconnect()
        try restartDaemon()
        return true
    }

    private static func waitForDaemon(timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath),
               (try? daemonRequest("GetStatus", timeout: 1)) != nil {
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw Error.daemonUnavailable("daemon did not come back after restart")
    }

    static func parseStatus(_ raw: String) -> SnxStatus {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .disconnected }

        // Prefer daemon JSON when present.
        if text.hasPrefix("{"), let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            return parseDaemonStatus(obj)
        }

        let lower = text.lowercased()
        let looksConnected =
            lower.contains("connected since")
            || lower.contains("tunnel connected")
            || lower.contains("connection-status-connected")
            || (lower.contains("ip address") && !lower.contains("not connected"))

        var server: String?
        var user: String?
        var ip: String?
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let value = field(trimmed, keys: ["Server name:", "server name:"]) {
                server = value
            } else if let value = field(trimmed, keys: ["User name:", "user name:", "Username:"]) {
                user = value
            } else if let value = field(trimmed, keys: ["IP address:", "ip address:"]) {
                ip = value
            }
        }

        if looksConnected {
            return SnxStatus(state: .connected, serverName: server, userName: user, ipAddress: ip, raw: text)
        }
        if lower.contains("connecting") {
            return SnxStatus(state: .connecting, serverName: server, userName: user, ipAddress: ip, raw: text)
        }
        return SnxStatus(state: .idle, serverName: server, userName: user, ipAddress: ip, raw: text)
    }

    static func parseDaemonStatus(_ object: Any) -> SnxStatus {
        let raw = (try? JSONSerialization.data(withJSONObject: object)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "\(object)"

        guard let root = object as? [String: Any] else {
            return SnxStatus(state: .unknown, serverName: nil, userName: nil, ipAddress: nil, raw: raw)
        }

        if let error = root["Error"] as? String {
            return SnxStatus(state: .idle, serverName: nil, userName: nil, ipAddress: nil, raw: error)
        }

        let status = root["ConnectionStatus"] ?? root
        if let name = status as? String {
            switch name {
            case "Disconnected":
                return SnxStatus(state: .idle, serverName: nil, userName: nil, ipAddress: nil, raw: raw)
            case "Connecting":
                return SnxStatus(state: .connecting, serverName: nil, userName: nil, ipAddress: nil, raw: raw)
            default:
                return SnxStatus(state: .unknown, serverName: nil, userName: nil, ipAddress: nil, raw: raw)
            }
        }

        if let dict = status as? [String: Any] {
            if let connected = dict["Connected"] as? [String: Any] {
                let server = connected["server_name"] as? String
                let user = connected["username"] as? String
                let ip: String?
                if let s = connected["ip_address"] as? String {
                    ip = s
                } else if let n = connected["ip_address"] as? [String: Any] {
                    ip = n["addr"] as? String ?? n["Addr"] as? String
                } else {
                    ip = nil
                }
                return SnxStatus(state: .connected, serverName: server, userName: user, ipAddress: ip, raw: raw)
            }
            if dict["Mfa"] != nil {
                return SnxStatus(state: .connecting, serverName: nil, userName: nil, ipAddress: nil, raw: raw)
            }
        }
        return SnxStatus(state: .unknown, serverName: nil, userName: nil, ipAddress: nil, raw: raw)
    }

    /// Extract login-type id like `vpn_VPN_RA` from `snx-rs -m info` output.
    static func parseLoginTypes(_ raw: String) -> [String] {
        var types: [String] = []
        for line in raw.split(whereSeparator: \.isNewline).map(String.init) {
            guard let open = line.firstIndex(of: "]") else { continue }
            let after = line[line.index(after: open)...]
            guard let colon = after.firstIndex(of: ":") else { continue }
            let id = after[..<colon]
                .trimmingCharacters(in: .whitespaces)
            if id.hasPrefix("vpn_") {
                types.append(id)
            }
        }
        return types
    }

    static func writeConnectConfig(
        server: String,
        loginType: String,
        username: String,
        password: String,
        mfaCode: String,
        ignoreServerCert: Bool = true
    ) throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CheckpointVPNOneClick", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = dir.appendingPathComponent("snx-rs-connect.conf")
        let passwordB64 = Data(password.utf8).base64EncodedString()
        // Corporate Check Point gateways often fail snx-rs internal IPsec CA fingerprint checks
        // unless ignore-server-cert is set (same as `snx-rs -X true`).
        // default-route=false keeps gateway-pushed corp routes without owning all internet (Karing-friendly).
        let body = """
        server-name=\(server)
        login-type=\(loginType)
        user-name=\(username)
        password=\(passwordB64)
        mfa-code=\(mfaCode)
        keychain=false
        tunnel-type=ipsec
        ignore-server-cert=\(ignoreServerCert ? "true" : "false")
        default-route=false
        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    // MARK: - Daemon IPC (length-delimited JSON over Unix socket)

    private static func daemonRequest(_ request: Any, timeout: TimeInterval = 3) throws -> Any {
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw Error.daemonUnavailable("missing \(socketPath)")
        }
        let payload: Data
        if let text = request as? String {
            // NSJSONSerialization rejects top-level strings; snx-rs unit variants are bare JSON strings.
            var escaped = "\""
            for ch in text.unicodeScalars {
                switch ch {
                case "\\": escaped += "\\\\"
                case "\"": escaped += "\\\""
                default: escaped += String(ch)
                }
            }
            escaped += "\""
            guard let data = escaped.data(using: .utf8) else {
                throw Error.failed("Could not encode daemon request string")
            }
            payload = data
        } else {
            do {
                payload = try JSONSerialization.data(withJSONObject: request)
            } catch {
                throw Error.failed("Could not encode daemon request: \(error.localizedDescription)")
            }
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Error.daemonUnavailable("socket() failed") }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw Error.daemonUnavailable("socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    dst.update(from: src.baseAddress!, count: pathBytes.count)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw Error.daemonUnavailable(String(cString: strerror(errno)))
        }

        // LengthDelimitedCodec: 4-byte big-endian length + payload
        var length = UInt32(payload.count).bigEndian
        let lengthData = Data(bytes: &length, count: 4)
        try writeAll(fd: fd, data: lengthData, timeout: timeout)
        try writeAll(fd: fd, data: payload, timeout: timeout)

        let header = try readExact(fd: fd, count: 4, timeout: timeout)
        let responseLength = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard responseLength > 0, responseLength < 8_000_000 else {
            throw Error.failed("Invalid daemon response length \(responseLength)")
        }
        let body = try readExact(fd: fd, count: Int(responseLength), timeout: timeout)
        let object = try parseDaemonJSON(body)
        if let dict = object as? [String: Any], let message = dict["Error"] as? String {
            throw Error.failed(message)
        }
        return object
    }

    /// snx-rs replies with top-level JSON strings for unit enums (`"Ok"`, `"GetStatus"` requests),
    /// which `JSONSerialization` rejects — handle those manually.
    private static func parseDaemonJSON(_ data: Data) throws -> Any {
        let trimmed = data.trimmingASCIIWhitespace()
        guard !trimmed.isEmpty else { throw Error.failed("Empty daemon response") }

        if trimmed.first == UInt8(ascii: "\"") {
            guard let text = String(data: trimmed, encoding: .utf8) else {
                throw Error.failed("Invalid daemon string response")
            }
            // Decode a JSON string literal including escapes.
            var result = ""
            var chars = text.dropFirst().makeIterator()
            while let ch = chars.next() {
                if ch == "\"" { return result }
                if ch == "\\" {
                    guard let escaped = chars.next() else { break }
                    switch escaped {
                    case "\"", "\\", "/": result.append(escaped)
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    default: result.append(escaped)
                    }
                } else {
                    result.append(ch)
                }
            }
            throw Error.failed("Unterminated daemon string response")
        }

        do {
            return try JSONSerialization.jsonObject(with: trimmed)
        } catch {
            throw Error.failed("Could not parse daemon response: \(error.localizedDescription)")
        }
    }

    private static func writeAll(fd: Int32, data: Data, timeout: TimeInterval) throws {
        var offset = 0
        let deadline = Date().addingTimeInterval(timeout)
        while offset < data.count {
            if Date() > deadline { throw Error.daemonUnavailable("write timed out") }
            let wrote = data.withUnsafeBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return Darwin.write(fd, base + offset, data.count - offset)
            }
            if wrote < 0 {
                if errno == EINTR { continue }
                throw Error.daemonUnavailable(String(cString: strerror(errno)))
            }
            if wrote == 0 { throw Error.daemonUnavailable("write closed") }
            offset += wrote
        }
    }

    private static func readExact(fd: Int32, count: Int, timeout: TimeInterval) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        let deadline = Date().addingTimeInterval(timeout)
        while offset < count {
            if Date() > deadline { throw Error.daemonUnavailable("read timed out") }
            let readCount = data.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return Darwin.read(fd, base + offset, count - offset)
            }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw Error.daemonUnavailable(String(cString: strerror(errno)))
            }
            if readCount == 0 { throw Error.daemonUnavailable("connection closed") }
            offset += readCount
        }
        return data
    }

    private static func field(_ line: String, keys: [String]) -> String? {
        for key in keys {
            if line.lowercased().hasPrefix(key.lowercased()) {
                return String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        for key in keys {
            let bare = key.trimmingCharacters(in: CharacterSet(charactersIn: ":")).trimmingCharacters(in: .whitespaces)
            if let range = line.range(of: bare + ":", options: [.caseInsensitive]) {
                return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func which(_ name: String) -> String? {
        let result = run(executable: "/usr/bin/which", arguments: [name], timeout: 2)
        guard result.status == 0 else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
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
            // Give it a moment, then hard-kill if needed.
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            return (124, "Timed out after \(Int(timeout))s: \(executable) \(arguments.joined(separator: " "))")
        }
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = (out + "\n" + err).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, combined)
    }
}

private extension Data {
    func trimmingASCIIWhitespace() -> Data {
        var start = startIndex
        var end = endIndex
        let ws: Set<UInt8> = [0x09, 0x0A, 0x0D, 0x20]
        while start < end, ws.contains(self[start]) { start = index(after: start) }
        while end > start, ws.contains(self[index(before: end)]) { end = index(before: end) }
        return self[start..<end]
    }
}
