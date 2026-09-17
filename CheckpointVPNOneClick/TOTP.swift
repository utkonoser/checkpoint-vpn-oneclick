import Foundation
import CryptoKit

enum TOTP {
    static let defaultPeriod = 30
    static let defaultDigits = 6
    static let rolloverSafety: TimeInterval = 5

    struct Secret {
        var key: Data
        var period: Int
        var digits: Int
    }

    enum Error: Swift.Error, LocalizedError {
        case empty
        case badBase32
        case tooShort

        var errorDescription: String? {
            switch self {
            case .empty: return "TOTP secret is empty."
            case .badBase32: return "TOTP secret is not valid Base32."
            case .tooShort: return "TOTP secret is too short."
            }
        }
    }

    static func parseSecret(_ raw: String) throws -> Secret {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Error.empty }

        var period = defaultPeriod
        var digits = defaultDigits
        var secretValue = trimmed

        if let url = URL(string: trimmed), url.scheme?.lowercased() == "otpauth" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let s = items.first(where: { $0.name.lowercased() == "secret" })?.value {
                secretValue = s
            }
            if let p = items.first(where: { $0.name.lowercased() == "period" })?.value, let n = Int(p), n > 0 {
                period = n
            }
            if let d = items.first(where: { $0.name.lowercased() == "digits" })?.value, let n = Int(d), n > 0 {
                digits = n
            }
        }

        let key = try decodeBase32(secretValue)
        guard key.count >= 10 else { throw Error.tooShort }
        return Secret(key: key, period: period, digits: digits)
    }

    static func code(for secret: Secret, at date: Date = Date()) -> String {
        generate(key: secret.key, digits: secret.digits, period: secret.period, at: date)
    }

    static func secondsRemaining(period: Int, at date: Date = Date()) -> TimeInterval {
        let p = TimeInterval(period)
        let now = date.timeIntervalSince1970
        let elapsed = now.truncatingRemainder(dividingBy: p)
        return p - elapsed
    }

    static func generate(key: Data, digits: Int, period: Int, at date: Date) -> String {
        let counter = UInt64(date.timeIntervalSince1970 / TimeInterval(period)).bigEndian
        var counterBytes = withUnsafeBytes(of: counter) { Data($0) }
        if counterBytes.count < 8 {
            counterBytes = Data(repeating: 0, count: 8 - counterBytes.count) + counterBytes
        }
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: SymmetricKey(data: key))
        let hash = Data(mac)
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let binary =
            (UInt32(hash[offset]) & 0x7f) << 24
            | UInt32(hash[offset + 1]) << 16
            | UInt32(hash[offset + 2]) << 8
            | UInt32(hash[offset + 3])
        let modulus = UInt32(pow(10, Double(digits)))
        let otp = binary % modulus
        return String(format: "%0\(digits)u", otp)
    }

    static func decodeBase32(_ string: String) throws -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var map = [Character: UInt8]()
        for (i, c) in alphabet.enumerated() {
            map[c] = UInt8(i)
            map[Character(c.lowercased())] = UInt8(i)
        }
        let cleaned = string.filter { !$0.isWhitespace && $0 != "=" }
        guard !cleaned.isEmpty else { throw Error.empty }
        var buffer: UInt32 = 0
        var bits = 0
        var out = Data()
        for ch in cleaned {
            guard let val = map[ch] else { throw Error.badBase32 }
            buffer = (buffer << 5) | UInt32(val)
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> bits) & 0xff))
            }
        }
        return out
    }
}
