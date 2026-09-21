import Foundation
import Security

enum KeychainStore {
    static let service = "local.checkpointvpn.oneclick"
    static let passwordAccount = "vpn-password"
    static let totpAccount = "totp-secret"
    static let totpVaultAccount = "totp-accounts"

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
    static func totpSecret() throws -> String? { try selectedTOTP()?.secret }

    static func totpAccounts() throws -> [TOTP.Account] { try loadVault().accounts }

    static func selectedTOTP() throws -> TOTP.Account? {
        let vault = try loadVault()
        if let id = vault.selectedID, let match = vault.accounts.first(where: { $0.id == id }) {
            return match
        }
        return vault.accounts.first
    }

    static func addTOTP(secret: String, name: String) throws {
        var vault = try loadVault()
        if let existing = vault.accounts.first(where: { sameSecret($0.secret, secret) }) {
            vault.selectedID = existing.id
            try saveVault(vault)
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = TOTP.Account(
            id: UUID().uuidString,
            name: trimmedName.isEmpty ? TOTP.defaultName(from: secret) : trimmedName,
            secret: secret
        )
        vault.accounts.append(account)
        vault.selectedID = account.id
        try saveVault(vault)
    }

    static func renameTOTP(id: String, name: String) throws {
        var vault = try loadVault()
        guard let index = vault.accounts.firstIndex(where: { $0.id == id }) else { return }
        vault.accounts[index].name = name
        try saveVault(vault)
    }

    static func selectTOTP(id: String) throws {
        var vault = try loadVault()
        guard vault.accounts.contains(where: { $0.id == id }) else { return }
        vault.selectedID = id
        try saveVault(vault)
    }

    static func deleteTOTP(id: String) throws {
        var vault = try loadVault()
        vault.accounts.removeAll { $0.id == id }
        if vault.selectedID == id {
            vault.selectedID = vault.accounts.first?.id
        }
        try saveVault(vault)
    }

    static func setPassword(_ value: String) throws { try write(account: passwordAccount, value: value) }

    static func deletePassword() { delete(account: passwordAccount) }

    static func hasPassword() -> Bool { (try? password())?.isEmpty == false }
    static func hasTOTPSecret() -> Bool { (try? totpAccounts())?.isEmpty == false }

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

    private static func loadVault() throws -> TOTP.Vault {
        if let raw = try cached(totpVaultAccount),
           let data = raw.data(using: .utf8),
           let vault = try? JSONDecoder().decode(TOTP.Vault.self, from: data) {
            return normalized(vault)
        }
        if let old = try cached(totpAccount), !old.isEmpty {
            let account = TOTP.Account(
                id: UUID().uuidString,
                name: TOTP.defaultName(from: old),
                secret: old
            )
            let vault = TOTP.Vault(accounts: [account], selectedID: account.id)
            try saveVault(vault)
            delete(account: totpAccount)
            return vault
        }
        return TOTP.Vault(accounts: [], selectedID: nil)
    }

    private static func normalized(_ vault: TOTP.Vault) -> TOTP.Vault {
        var vault = vault
        if vault.selectedID == nil || !vault.accounts.contains(where: { $0.id == vault.selectedID }) {
            vault.selectedID = vault.accounts.first?.id
        }
        return vault
    }

    private static func saveVault(_ vault: TOTP.Vault) throws {
        let data = try JSONEncoder().encode(normalized(vault))
        guard let raw = String(data: data, encoding: .utf8) else { throw Error.notPersisted }
        try write(account: totpVaultAccount, value: raw)
    }

    private static func sameSecret(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard let left = try? TOTP.parseSecret(a), let right = try? TOTP.parseSecret(b) else { return false }
        return left.key == right.key && left.period == right.period && left.digits == right.digits
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
