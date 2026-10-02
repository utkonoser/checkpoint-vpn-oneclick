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

    static func connect(site: String, username: String, loginType: String, ignoreServerCert: Bool = true) async throws {
        let site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let loginType = loginType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty else { throw Error.missingSite }
        guard !username.isEmpty else { throw Error.missingUsername }
        guard SnxClient.isInstalled() else { throw SnxClient.Error.notInstalled }
        guard let password = try KeychainStore.password(site: site), !password.isEmpty else { throw Error.missingPassword }
        guard let totpRaw = try KeychainStore.totpSecret(site: site), !totpRaw.isEmpty else { throw Error.missingTOTP }
        let secret = try TOTP.parseSecret(totpRaw)

        // After sleep/wake the snx-rs daemon often keeps a half-dead tunnel. Always start clean.
        try? SnxClient.disconnect()
        try await Task.sleep(nanoseconds: 400_000_000)

        if let status = try? SnxClient.status(), status.state == .connected {
            throw Error.alreadyConnected
        }

        var lastError: Swift.Error?
        for attempt in 1...2 {
            let remaining = TOTP.secondsRemaining(period: secret.period)
            if remaining < TOTP.rolloverSafety {
                try await Task.sleep(nanoseconds: UInt64((remaining + 0.35) * 1_000_000_000))
            }
            let mfa = TOTP.code(for: secret)

            do {
                try SnxClient.connect(
                    server: site,
                    loginType: loginType.isEmpty ? SnxClient.defaultLoginType : loginType,
                    username: username,
                    password: password,
                    mfaCode: mfa,
                    ignoreServerCert: ignoreServerCert
                )
                try await waitUntilConnected()
                return
            } catch {
                lastError = error
                let message = error.localizedDescription
                let retryable =
                    message.localizedCaseInsensitiveContains("certificate")
                    || message.localizedCaseInsensitiveContains("503")
                    || message.localizedCaseInsensitiveContains("challenge")
                    || message.localizedCaseInsensitiveContains("timeout")
                    || message.localizedCaseInsensitiveContains("unsuccessful")
                guard attempt == 1, retryable else { break }
                NSLog("ConnectEngine retry with daemon restart after: \(message)")
                // Soft disconnect is not enough after sleep — restart LaunchDaemon (admin prompt).
                _ = try? SnxClient.refreshStaleDaemonIfNeeded()
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        throw lastError ?? Error.connectFailed("Connect failed")
    }

    static func disconnect() throws {
        try SnxClient.disconnect()
    }

    private static func waitUntilConnected() async throws {
        let deadline = Date().addingTimeInterval(20)
        var last = "no status"
        while Date() < deadline {
            try Task.checkCancellation()
            if let status = try? SnxClient.status() {
                last = status.raw.isEmpty ? status.state.title : status.raw
                if status.state == .connected { return }
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw Error.connectFailed("VPN did not reach Connected. Last: \(last)")
    }
}
