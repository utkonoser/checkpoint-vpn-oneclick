import AppKit
import Foundation

enum ConnectEngine {
    enum Error: Swift.Error, LocalizedError {
        case missingPassword
        case missingTOTP
        case missingUsername
        case missingSite
        case alreadyConnected
        case connectFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingPassword: return "Save the VPN password in Settings first."
            case .missingTOTP: return "Save the TOTP secret in Settings first."
            case .missingUsername: return "Username is empty."
            case .missingSite: return "No VPN site selected."
            case .alreadyConnected: return "Already connected."
            case .connectFailed(let message): return message
            }
        }
    }

    static func connect(site: String, username: String) async throws {
        let site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty else { throw Error.missingSite }
        guard !username.isEmpty else { throw Error.missingUsername }
        guard let password = try KeychainStore.password(), !password.isEmpty else { throw Error.missingPassword }
        guard let totpRaw = try KeychainStore.totpSecret(), !totpRaw.isEmpty else { throw Error.missingTOTP }
        let secret = try TOTP.parseSecret(totpRaw)

        if let snapshot = try? TracClient.info(), snapshot.overall == .connected {
            throw Error.alreadyConnected
        }

        guard CheckpointAX.isTrusted(prompt: true) else {
            throw CheckpointAX.Error.notTrusted
        }

        _ = try await CheckpointAX.ensureGUIRunning()
        try await Task.sleep(nanoseconds: 400_000_000)
        try TracClient.connectGUI(site: site)

        try await CheckpointAX.fillLogin(username: username, password: password)

        let remaining = TOTP.secondsRemaining(period: secret.period)
        if remaining < TOTP.rolloverSafety {
            try await Task.sleep(nanoseconds: UInt64((remaining + 0.25) * 1_000_000_000))
        }
        try await CheckpointAX.fillChallenge {
            TOTP.code(for: secret)
        }

        try await waitUntilConnected(timeout: 45)
    }

    static func disconnect() throws {
        try TracClient.disconnect()
    }

    private static func waitUntilConnected(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last = "no status"
        while Date() < deadline {
            try Task.checkCancellation()
            if let snapshot = try? TracClient.info() {
                last = snapshot.sites.map { "\($0.name)=\($0.status.rawValue)" }.joined(separator: ", ")
                if snapshot.overall == .connected { return }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw Error.connectFailed("VPN did not reach Connected. Last: \(last)")
    }
}
