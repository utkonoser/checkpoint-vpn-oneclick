import Foundation
import Security

enum KeychainStore {
    static let service = "local.checkpointvpn.oneclick"
    /// Legacy global keys — migrated onto the first selected site.
    static let legacyPasswordAccount = "vpn-password"
    static let legacyTOTPAccount = "totp-secret"
    static let legacyTOTPVaultAccount = "totp-accounts"

    enum Error: Swift.Error, LocalizedError {
        case unexpected(OSStatus)
        case notPersisted
        case missingSite

        var errorDescription: String? {
            switch self {
            case .unexpected(let status):
                return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            case .notPersisted:
                return "Could not save the secret. Try Save secrets again."
            case .missingSite:
                return "Pick a Check Point site first."
            }
        }
    }

    private static let lock = NSLock()
    private static var cache: [String: String] = [:]
    private static var didPurgeSystemKeychain = false

    static func password(site: String) throws -> String? {
        try cached(passwordAccount(for: site))
    }

    static func totpSecret(site: String) throws -> String? {
        try cached(totpAccount(for: site))
    }

    static func setPassword(_ value: String, site: String) throws {
        try write(account: passwordAccount(for: site), value: value)
    }

    static func setTOTPSecret(_ value: String, site: String) throws {
        try write(account: totpAccount(for: site), value: value)
    }

    static func hasPassword(site: String) -> Bool {
        (try? password(site: site))?.isEmpty == false
    }

    static func hasTOTPSecret(site: String) -> Bool {
        (try? totpSecret(site: site))?.isEmpty == false
    }

    /// Move old global / multi-TOTP vault secrets onto `site` once.
    static func migrateLegacySecretsIfNeeded(to site: String) throws {
        purgeSystemKeychainOnce()
        let site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !site.isEmpty else { return }

        if !hasPassword(site: site), let old = try cached(legacyPasswordAccount), !old.isEmpty {
            try setPassword(old, site: site)
            delete(account: legacyPasswordAccount)
        }

        if !hasTOTPSecret(site: site) {
            if let vaultRaw = try cached(legacyTOTPVaultAccount),
               let data = vaultRaw.data(using: .utf8),
               let vault = try? JSONDecoder().decode(LegacyVault.self, from: data) {
                let picked = vault.accounts.first(where: { $0.id == vault.selectedID })
                    ?? vault.accounts.first
                if let secret = picked?.secret, !secret.isEmpty {
                    try setTOTPSecret(secret, site: site)
                }
                delete(account: legacyTOTPVaultAccount)
            } else if let old = try cached(legacyTOTPAccount), !old.isEmpty {
                try setTOTPSecret(old, site: site)
                delete(account: legacyTOTPAccount)
            }
        } else {
            delete(account: legacyTOTPVaultAccount)
            delete(account: legacyTOTPAccount)
        }
    }

    static func dropCacheForTests() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    static func persistProbeForTests() throws {
        let account = "keychain-probe"
        let value = "probe-value"
        try write(account: account, value: value)
        dropCacheForTests()
        let read = try readAny(account: account)
        delete(account: account)
        guard read == value else { throw Error.notPersisted }
    }

    static func passwordAccount(for site: String) throws -> String {
        "password:\(try normalizedSite(site))"
    }

    static func totpAccount(for site: String) throws -> String {
        "totp:\(try normalizedSite(site))"
    }

    static func normalizedSite(_ site: String) throws -> String {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.missingSite }
        return trimmed
    }

    private struct LegacyVault: Codable {
        struct Account: Codable {
            var id: String
            var name: String
            var secret: String
        }
        var accounts: [Account]
        var selectedID: String?
    }

    private static func cached(_ account: String) throws -> String? {
        purgeSystemKeychainOnce()
        lock.lock()
        if let hit = cache[account] {
            lock.unlock()
            return hit.isEmpty ? nil : hit
        }
        lock.unlock()
        let value = try readAny(account: account)
        lock.lock()
        cache[account] = value ?? ""
        lock.unlock()
        return value
    }

    // ponytail: ad-hoc rebuilds change the CDHash → login Keychain prompts on every SecItem read.
    // Ceiling until a real Team ID: secrets.plist 0600 only. System Keychain is abandoned.
    private static func readAny(account: String) throws -> String? {
        try sidecar()[account]
    }

    private static func write(account: String, value: String) throws {
        purgeSystemKeychainOnce()
        guard !value.isEmpty else {
            delete(account: account)
            return
        }

        try writeSidecar(account: account, value: value)
        dropCacheForTests()
        guard try readAny(account: account) == value else { throw Error.notPersisted }
        lock.lock()
        cache[account] = value
        lock.unlock()
    }

    private static func sidecarURL() throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CheckpointVPNOneClick", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir.appendingPathComponent("secrets.plist")
    }

    private static func sidecar() throws -> [String: String] {
        let url = try sidecarURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return (try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]) ?? [:]
    }

    private static func writeSidecar(account: String, value: String) throws {
        var all = try sidecar()
        all[account] = value
        try saveSidecar(all)
    }

    private static func saveSidecar(_ all: [String: String]) throws {
        let url = try sidecarURL()
        if all.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: all, format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func delete(account: String) {
        lock.lock()
        cache[account] = ""
        lock.unlock()
        if var all = try? sidecar() {
            all.removeValue(forKey: account)
            try? saveSidecar(all)
        }
    }

    /// Drop ACL-bound login-keychain items so macOS stops asking for the login password.
    /// Best-effort: copy into secrets.plist first (may prompt once), then delete.
    private static func purgeSystemKeychainOnce() {
        lock.lock()
        defer { lock.unlock() }
        guard !didPurgeSystemKeychain else { return }
        didPurgeSystemKeychain = true

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let items = result as? [[String: Any]] {
            var all = (try? sidecarUnlocked()) ?? [:]
            for item in items {
                guard let account = item[kSecAttrAccount as String] as? String,
                      let data = item[kSecValueData as String] as? Data,
                      let value = String(data: data, encoding: .utf8),
                      !value.isEmpty else { continue }
                if all[account] == nil || all[account]?.isEmpty == true {
                    all[account] = value
                }
            }
            try? saveSidecar(all)
        }

        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }

    /// Caller already holds `lock` or is single-threaded during purge.
    private static func sidecarUnlocked() throws -> [String: String] {
        try sidecar()
    }
}
