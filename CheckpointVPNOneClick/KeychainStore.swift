import Foundation
import Security

enum KeychainStore {
    static let service = "local.checkpointvpn.oneclick"
    static let passwordAccount = "vpn-password"
    static let totpAccount = "totp-secret"

    enum Error: Swift.Error, LocalizedError {
        case unexpected(OSStatus)
        case notPersisted

        var errorDescription: String? {
            switch self {
            case .unexpected(let status):
                return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            case .notPersisted:
                return "Could not save the secret. Try Save secrets again."
            }
        }
    }

    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    static func password() throws -> String? { try cached(passwordAccount) }
    static func totpSecret() throws -> String? { try cached(totpAccount) }

    static func setPassword(_ value: String) throws { try write(account: passwordAccount, value: value) }
    static func setTOTPSecret(_ value: String) throws { try write(account: totpAccount, value: value) }

    static func deletePassword() { delete(account: passwordAccount) }
    static func deleteTOTPSecret() { delete(account: totpAccount) }

    static func hasPassword() -> Bool { (try? password())?.isEmpty == false }
    static func hasTOTPSecret() -> Bool { (try? totpSecret())?.isEmpty == false }

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

    private static func cached(_ account: String) throws -> String? {
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

    private static func readAny(account: String) throws -> String? {
        if let keychain = try readKeychain(account: account) { return keychain }
        return try sidecar()[account]
    }

    private static func readKeychain(account: String) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
        guard status == errSecSuccess else { throw Error.unexpected(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func write(account: String, value: String) throws {
        guard !value.isEmpty else {
            delete(account: account)
            return
        }

        if !writeKeychain(account: account, value: value) {
            try writeSidecar(account: account, value: value)
        }
        dropCacheForTests()
        guard try readAny(account: account) == value else { throw Error.notPersisted }
        lock.lock()
        cache[account] = value
        lock.unlock()
    }

    /// Returns false when this Mac refuses the item (typical without an Apple Team ID).
    private static func writeKeychain(account: String, value: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrLabel as String] = "Checkpoint VPN"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { return false }
        return (try? readKeychain(account: account)) == value
    }

    // ponytail: no Apple Team ID → SecItemAdd often returns -34018. secrets.plist 0600 is the ceiling until a real signing identity exists.
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if var all = try? sidecar() {
            all.removeValue(forKey: account)
            try? saveSidecar(all)
        }
    }
}
