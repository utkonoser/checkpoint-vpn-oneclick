import Foundation

struct VPNSite: Identifiable, Hashable {
    var name: String
    var status: VPNConnectionState
    var isActive: Bool
    var id: String { name }
}

enum VPNConnectionState: String, Equatable {
    case idle
    case connecting
    case connected
    case unknown

    init(raw: String) {
        switch raw.lowercased() {
        case "idle": self = .idle
        case "connecting": self = .connecting
        case "connected": self = .connected
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .unknown: return "Unknown"
        }
    }

    var menuBarImageName: String {
        self == .connected ? "MenuBarConnected" : "MenuBarDisconnected"
    }
}

struct TracSnapshot {
    var sites: [VPNSite]
    var active: VPNSite?

    var overall: VPNConnectionState {
        if let active, active.status == .connected { return .connected }
        if sites.contains(where: { $0.status == .connecting }) { return .connecting }
        if sites.contains(where: { $0.status == .connected }) { return .connected }
        return .idle
    }
}

enum TracClient {
    static let binaryPath = "/Library/Application Support/Checkpoint/Endpoint Connect/trac"
    static let guiPath = "/Applications/Endpoint Security VPN.app"

    enum Error: Swift.Error, LocalizedError {
        case missingBinary
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missingBinary:
                return "Check Point trac CLI not found at \(TracClient.binaryPath)."
            case .failed(let message):
                return message
            }
        }
    }

    static func info() throws -> TracSnapshot {
        let output = try run(["info"])
        return parseInfo(output)
    }

    static func connectGUI(site: String) throws {
        _ = try run(["connectgui", "-s", site])
    }

    static func disconnect() throws {
        _ = try run(["disconnect"])
    }

    static func run(_ arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw Error.missingBinary
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = (out + "\n" + err).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            throw Error.failed(combined.isEmpty ? "trac \(arguments.joined(separator: " ")) failed (\(process.terminationStatus))" : combined)
        }
        return combined
    }

    static func parseInfo(_ raw: String) -> TracSnapshot {
        var sites: [VPNSite] = []
        var currentName: String?
        var currentStatus = VPNConnectionState.unknown
        var currentActive = false

        func flush() {
            guard let name = currentName else { return }
            sites.append(VPNSite(name: name, status: currentStatus, isActive: currentActive))
            currentName = nil
            currentStatus = .unknown
            currentActive = false
        }

        for line in raw.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Conn ") {
                flush()
                var name = String(trimmed.dropFirst(5))
                if name.hasSuffix(":") { name.removeLast() }
                currentName = name.trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.lowercased().hasPrefix("status:") {
                let value = trimmed.split(separator: ":", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
                currentStatus = VPNConnectionState(raw: value)
                continue
            }
            if trimmed.lowercased().hasPrefix("active site:") {
                let value = trimmed.split(separator: ":", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
                currentActive = value == "true" || value == "yes"
            }
        }
        flush()
        return TracSnapshot(sites: sites, active: sites.first(where: \.isActive) ?? sites.first)
    }
}
