import Foundation

enum ConnectEngine {
    enum Error: Swift.Error, LocalizedError {
        case missingPassword
        case missingTOTP
        case missingUsername
        case missingSite
        case alreadyConnected
        case proxyAlreadyRunning
        case connectFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingPassword: return "Save the VPN password for this site in Settings first."
            case .missingTOTP: return "Save the TOTP secret for this site in Settings first."
            case .missingUsername: return "Username is empty."
            case .missingSite: return "No VPN site selected."
            case .alreadyConnected: return "Work VPN is already connected."
            case .proxyAlreadyRunning: return "Personal proxy is already running."
            case .connectFailed(let message): return message
            }
        }
    }

    // MARK: - Work VPN (Check Point)

    static func connectWork(
        site: String,
        username: String,
        loginType: String,
        ignoreServerCert: Bool = true,
        splitDestinations: String = "",
        excludeDestinations: String = "",
        extraIgnoreHosts: [String] = []
    ) async throws {
        let site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let loginType = loginType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty else { throw Error.missingSite }
        guard !username.isEmpty else { throw Error.missingUsername }
        guard SnxClient.isInstalled() else { throw SnxClient.Error.notInstalled }
        guard let password = try KeychainStore.password(site: site), !password.isEmpty else { throw Error.missingPassword }
        guard let totpRaw = try KeychainStore.totpSecret(site: site), !totpRaw.isEmpty else { throw Error.missingTOTP }
        let secret = try TOTP.parseSecret(totpRaw)

        var ignoreRoutes = SplitDestinations.resolveIgnoreRoutes(excludeDestinations)
        if !extraIgnoreHosts.isEmpty {
            let more = SplitDestinations.resolveIgnoreRoutes(extraIgnoreHosts.joined(separator: "\n"))
            var seen = Set(ignoreRoutes)
            for cidr in more where seen.insert(cidr).inserted {
                ignoreRoutes.append(cidr)
            }
        }
        let ignoreSet = Set(ignoreRoutes)
        let addRoutes = try SplitDestinations.resolveAddRoutes(splitDestinations)
            .filter { !ignoreSet.contains($0) }

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
                    ignoreServerCert: ignoreServerCert,
                    addRoutes: addRoutes,
                    ignoreRoutes: ignoreRoutes
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
                try? SnxClient.disconnect()
                let needsDaemonRestart =
                    message.localizedCaseInsensitiveContains("Internal IPSec certificate")
                    || {
                        do {
                            _ = try SnxClient.status()
                            return false
                        } catch SnxClient.Error.daemonUnavailable {
                            return true
                        } catch {
                            return false
                        }
                    }()
                if needsDaemonRestart {
                    NSLog("ConnectEngine retry with daemon restart after: \(message)")
                    try SnxClient.restartDaemon()
                } else {
                    NSLog("ConnectEngine retry without daemon restart after: \(message)")
                }
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        throw lastError ?? Error.connectFailed("Work VPN connect failed")
    }

    static func disconnectWork() throws {
        try SnxClient.disconnect()
    }

    // MARK: - Personal proxy (sing-box)

    static func connectProxy(
        subscriptionURL: String,
        includeDestinations: String,
        nodeTag: String
    ) async throws -> String {
        if ProxyClient.isRunning() {
            throw Error.proxyAlreadyRunning
        }
        let text = try ProxySubscription.fetch(urlString: subscriptionURL)
        let parsed = ProxySubscription.parse(text)
        guard !parsed.nodes.isEmpty else { throw ProxySubscription.Error.empty }
        var selected = nodeTag
        if selected != ProxySubscription.autoTag,
           !parsed.nodes.contains(where: { $0.tag == selected }) {
            selected = ProxySubscription.autoTag
        }
        let configURL = try ProxySubscription.save(parsed: parsed, selectedTag: selected)
        let includeCIDRs = SplitDestinations.resolveIgnoreRoutes(includeDestinations)
        try ProxyClient.start(configURL: configURL, includeCIDRs: includeCIDRs)
        try await Task.sleep(nanoseconds: 500_000_000)
        try? ProxyClient.selectNode(tag: selected)
        return selected
    }

    static func disconnectProxy() throws {
        try ProxyClient.stop()
    }

    /// Disconnect every tunnel we manage.
    static func disconnectAll() throws {
        try? ProxyClient.stop()
        try? SnxClient.disconnect()
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
