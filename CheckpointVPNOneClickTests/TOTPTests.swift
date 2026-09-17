import XCTest
@testable import CheckpointVPNOneClick

final class TOTPTests: XCTestCase {
    func testRFC6238SHA1AtT59() {
        let key = Data("12345678901234567890".utf8)
        let date = Date(timeIntervalSince1970: 59)
        XCTAssertEqual(TOTP.generate(key: key, digits: 8, period: 30, at: date), "94287082")
        XCTAssertEqual(TOTP.generate(key: key, digits: 6, period: 30, at: date), "287082")
    }

    func testBase32DecodeFoobar() throws {
        XCTAssertEqual(try TOTP.decodeBase32("MZXW6YTBOI"), Data("foobar".utf8))
    }

    func testParseOtpauth() throws {
        let secret = try TOTP.parseSecret("otpauth://totp/Work:user?secret=JBSWY3DPEHPK3PXP&period=30&digits=6")
        XCTAssertEqual(secret.period, 30)
        XCTAssertEqual(secret.digits, 6)
        XCTAssertEqual(secret.key.count, 10)
    }

    func testQRRoundTrip() throws {
        let payload = "otpauth://totp/Work:user?secret=JBSWY3DPEHPK3PXP&period=30&digits=6"
        guard let image = QRCodeImporter.renderForTest(payload) else {
            XCTFail("Could not render QR")
            return
        }
        let decoded = try QRCodeImporter.decode(image: image)
        XCTAssertTrue(decoded.contains("JBSWY3DPEHPK3PXP"))
        _ = try TOTP.parseSecret(decoded)
    }

    func testKeychainPersistsAcrossCacheClear() throws {
        try KeychainStore.persistProbeForTests()
    }

    func testParseInfo() {
        let raw = """
        Trac connections:

        Conn vpn.example.com:
        \tgw: 1.2.3.4
        \tstatus: Idle
        \tactive site: false

        Conn vpn-backup.example.com:
        \tgw: 5.6.7.8
        \tstatus: Connected
        \tactive site: true
        """
        let snapshot = TracClient.parseInfo(raw)
        XCTAssertEqual(snapshot.sites.count, 2)
        XCTAssertEqual(snapshot.active?.name, "vpn-backup.example.com")
        XCTAssertEqual(snapshot.overall, .connected)
    }
}
