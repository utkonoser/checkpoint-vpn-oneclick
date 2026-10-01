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

    func testSiteScopedKeychainAccounts() throws {
        XCTAssertEqual(try KeychainStore.passwordAccount(for: " vpn.example.com "), "password:vpn.example.com")
        XCTAssertEqual(try KeychainStore.totpAccount(for: "vpn.example.com"), "totp:vpn.example.com")
        XCTAssertThrowsError(try KeychainStore.passwordAccount(for: "  "))
    }

    func testKeychainPersistsAcrossCacheClear() throws {
        try KeychainStore.persistProbeForTests()
    }

    func testParseSnxStatusConnected() {
        let raw = """
             Server name: vpn.rutube-net.ru
             User name: nn.selin
             IP address: 10.1.2.3
             Connected since: Wed Oct  1 09:00:00 2025
        """
        let status = SnxClient.parseStatus(raw)
        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.serverName, "vpn.rutube-net.ru")
        XCTAssertEqual(status.userName, "nn.selin")
        XCTAssertEqual(status.ipAddress, "10.1.2.3")
    }

    func testParseSnxStatusIdle() {
        let status = SnxClient.parseStatus("Tunnel error: unsuccessful client response")
        XCTAssertEqual(status.state, .idle)
    }

    func testParseDaemonStatusJSON() throws {
        let disconnected = try JSONSerialization.jsonObject(
            with: Data(#"{"ConnectionStatus":"Disconnected"}"#.utf8)
        )
        XCTAssertEqual(SnxClient.parseDaemonStatus(disconnected).state, .idle)

        let connecting = try JSONSerialization.jsonObject(
            with: Data(#"{"ConnectionStatus":"Connecting"}"#.utf8)
        )
        XCTAssertEqual(SnxClient.parseDaemonStatus(connecting).state, .connecting)

        let connected = try JSONSerialization.jsonObject(with: Data("""
        {"ConnectionStatus":{"Connected":{"server_name":"vpn.example.com","username":"alice","ip_address":"10.0.0.5/32","login_type":"vpn_VPN_RA","tunnel_type":"IPsec","transport_type":"Auto","dns_servers":[],"search_domains":[],"interface_name":"utun4","dns_configured":true,"routing_configured":true,"default_route":false,"profile_id":"38703862-805c-441c-922e-ee45eaf2bb5e","profile_name":"Default","live":{},"ike_state":null,"since":"2025-10-01T09:00:00+03:00"}}}
        """.utf8))
        let status = SnxClient.parseDaemonStatus(connected)
        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.serverName, "vpn.example.com")
        XCTAssertEqual(status.userName, "alice")
        XCTAssertEqual(status.ipAddress, "10.0.0.5/32")
    }

    func testParseSnxLoginTypes() {
        let raw = """
        Available login types:
        [0] vpn_VPN_RA: Certificate authentication for Remote Access
        [1] vpn_Something: Other
        """
        XCTAssertEqual(SnxClient.parseLoginTypes(raw), ["vpn_VPN_RA", "vpn_Something"])
    }

    func testRedShieldInstalledOnlyWhenPathExists() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("rs-missing-\(UUID().uuidString)")
        XCTAssertFalse(RedShieldVPN.isInstalled(at: missing.path))

        let present = FileManager.default.temporaryDirectory
            .appendingPathComponent("rs-present-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: present) }
        XCTAssertTrue(RedShieldVPN.isInstalled(at: present.path))
    }
}
