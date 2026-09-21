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
            case .missingPassword: return "Save the VPN password for this site in Settings first."
            case .missingTOTP: return "Save the TOTP secret for this site in Settings first."
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
        guard let password = try KeychainStore.password(site: site), !password.isEmpty else { throw Error.missingPassword }
        guard let totpRaw = try KeychainStore.totpSecret(site: site), !totpRaw.isEmpty else { throw Error.missingTOTP }
        let secret = try TOTP.parseSecret(totpRaw)

        if let snapshot = try? TracClient.info(), snapshot.overall == .connected {
            throw Error.alreadyConnected
        }

        guard CheckpointAX.isTrusted(prompt: true) else {
            throw CheckpointAX.Error.notTrusted
        }

        _ = try await CheckpointAX.ensureGUIRunning()
        try TracClient.connectGUI(site: site)

        // OTP reject / failed password often returns to the empty login form — retry the pair.
        for round in 1...3 {
            do {
                try await CheckpointAX.fillLogin(username: username, password: password)

                let remaining = TOTP.secondsRemaining(period: secret.period)
                if remaining < TOTP.rolloverSafety {
                    try await Task.sleep(nanoseconds: UInt64((remaining + 0.35) * 1_000_000_000))
                }
                try await CheckpointAX.fillChallenge(expectedDigits: secret.digits, maxAttempts: 3) {
                    TOTP.code(for: secret)
                }
                break
            } catch let CheckpointAX.Error.timeout(step) {
                guard round < 3, step == "login" || step == "challenge" || step.contains("back-to-login") else {
                    throw CheckpointAX.Error.timeout(step)
                }
                NSLog("ConnectEngine retry \(round) after \(step)")
                try await Task.sleep(nanoseconds: 400_000_000)
                try? TracClient.connectGUI(site: site)
            }
        }

        try await waitUntilConnected()
    }

    static func disconnect() throws {
        try TracClient.disconnect()
    }

    private static func waitUntilConnected() async throws {
        let deadline = Date().addingTimeInterval(ConnectPoll.timeout)
        var last = "no status"
        var sawConnecting = false
        var idleTicks = 0
        while Date() < deadline {
            try Task.checkCancellation()
            if let snapshot = try? TracClient.info() {
                last = snapshot.sites.map { "\($0.name)=\($0.status.rawValue)" }.joined(separator: ", ")
                switch ConnectPoll.step(
                    overall: snapshot.overall,
                    sawConnecting: sawConnecting,
                    idleTicks: idleTicks
                ) {
                case .connected:
                    return
                case .failed(let reason):
                    throw Error.connectFailed("\(reason). Last: \(last)")
                case .wait:
                    if snapshot.overall == .connecting {
                        sawConnecting = true
                        idleTicks = 0
                    } else {
                        idleTicks += 1
                    }
                }
            }
            try await Task.sleep(nanoseconds: ConnectPoll.pollNs)
        }
        throw Error.connectFailed("VPN did not reach Connected. Last: \(last)")
    }
}

enum ConnectPoll {
    enum Step: Equatable {
        case connected
        case failed(String)
        case wait
    }

    static let timeout: TimeInterval = 10
    static let pollNs: UInt64 = 200_000_000
    static let idleGiveUpTicks = 15

    static func step(
        overall: VPNConnectionState,
        sawConnecting: Bool,
        idleTicks: Int
    ) -> Step {
        switch overall {
        case .connected:
            return .connected
        case .connecting:
            return .wait
        case .idle, .unknown:
            if sawConnecting { return .failed("VPN dropped back to Idle") }
            if idleTicks >= idleGiveUpTicks { return .failed("VPN stayed Idle") }
            return .wait
        }
    }
}
