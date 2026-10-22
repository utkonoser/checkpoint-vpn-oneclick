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

    func testParseSplitDestinations() {
        let parsed = SplitDestinations.parse("""
        10.0.0.0/8
        192.168.1.1
        .Corp.Example
        rutube.ru

        # comment
        """)
        XCTAssertEqual(parsed.cidrs, ["10.0.0.0/8", "192.168.1.1/32"])
        XCTAssertEqual(parsed.hosts, ["corp.example", "rutube.ru"])
    }

    func testParseExcludeWildcardStrip() {
        let parsed = SplitDestinations.parse("""
        *.api5.cursor.sh
        *.authentication.cursor.sh
        api2.cursor.sh
        10.1.2.3
        # skip
        """)
        XCTAssertEqual(parsed.cidrs, ["10.1.2.3/32"])
        XCTAssertEqual(parsed.hosts, [
            "api5.cursor.sh",
            "authentication.cursor.sh",
            "api2.cursor.sh",
        ])
    }

    func testParseProxySubscriptionHysteria2() throws {
        let text = """
        # comment
        hysteria2://408c51e8-9246-483d-ba73-34ab4e202eb9@example.com:20326?security=tls&sni=example.com&insecure=0#%F0%9F%87%A9%F0%9F%87%AA%20Germany
        """
        let parsed = ProxySubscription.parse(text)
        XCTAssertEqual(parsed.nodes.count, 1)
        XCTAssertEqual(parsed.nodes[0].server, "example.com")
        XCTAssertEqual(parsed.nodes[0].proto, "hysteria2")
        let data = try ProxySubscription.buildConfig(parsed: parsed, selectedTag: ProxySubscription.autoTag)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let outbounds = root?["outbounds"] as? [[String: Any]] ?? []
        let tags = outbounds.compactMap { $0["tag"] as? String }
        XCTAssertTrue(tags.contains(ProxySubscription.autoTag))
        XCTAssertTrue(tags.contains(ProxySubscription.selectorTag))
        XCTAssertTrue(tags.contains("direct"))
    }

    func testParseProxySubscriptionMultilinePaste() {
        let text = """
        # mixed paste
        ss://YWVzLTI1Ni1nY206cGFzcw@ss.example.com:8388#SS-Node
        hysteria2://408c51e8-9246-483d-ba73-34ab4e202eb9@hy2.example.com:443?sni=hy2.example.com#HY2
        not-a-uri
        """
        let parsed = ProxySubscription.parse(text)
        XCTAssertEqual(parsed.nodes.count, 2)
        XCTAssertEqual(Set(parsed.nodes.map(\.proto)), Set(["ss", "hysteria2"]))
        XCTAssertEqual(Set(parsed.nodes.map(\.server)), Set(["ss.example.com", "hy2.example.com"]))
    }

    func testParseProxySubscriptionVlessRealityGrpc() throws {
        let text = """
        vless://11111111-2222-4333-8444-555555555555@vless.example.com:443?type=grpc&security=reality&encryption=none&sni=cdn.example.com&fp=firefox&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0123456789abcdef&alpn=h2&serviceName=grpc-svc#grpc-node
        """
        let parsed = ProxySubscription.parse(text)
        XCTAssertEqual(parsed.nodes.count, 1)
        XCTAssertEqual(parsed.nodes[0].proto, "vless")
        XCTAssertEqual(parsed.nodes[0].server, "vless.example.com")
        XCTAssertEqual(parsed.nodes[0].title, "grpc-node")

        let ob = parsed.outbounds[0]
        XCTAssertEqual(ob["type"] as? String, "vless")
        XCTAssertEqual(ob["uuid"] as? String, "11111111-2222-4333-8444-555555555555")
        XCTAssertEqual(ob["server_port"] as? Int, 443)

        let tls = ob["tls"] as? [String: Any]
        XCTAssertEqual(tls?["enabled"] as? Bool, true)
        XCTAssertEqual(tls?["server_name"] as? String, "cdn.example.com")
        XCTAssertEqual(tls?["alpn"] as? [String], ["h2"])
        let utls = tls?["utls"] as? [String: Any]
        XCTAssertEqual(utls?["fingerprint"] as? String, "firefox")
        let reality = tls?["reality"] as? [String: Any]
        XCTAssertEqual(reality?["enabled"] as? Bool, true)
        XCTAssertEqual(reality?["public_key"] as? String, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(reality?["short_id"] as? String, "0123456789abcdef")

        let transport = ob["transport"] as? [String: Any]
        XCTAssertEqual(transport?["type"] as? String, "grpc")
        XCTAssertEqual(transport?["service_name"] as? String, "grpc-svc")

        let data = try ProxySubscription.buildConfig(parsed: parsed, selectedTag: ProxySubscription.autoTag)
        XCTAssertFalse(data.isEmpty)
    }

    func testLoadTextPasteEmptyThrows() {
        ProxySubscription.clearPaste()
        XCTAssertThrowsError(
            try ProxySubscription.loadText(source: ProxySubscription.sourcePaste, url: "")
        ) { error in
            XCTAssertEqual(error as? ProxySubscription.Error, .empty)
        }
    }

    func testLoadTextPasteRoundTrip() throws {
        let body = "ss://YWVzLTI1Ni1nY206cGFzcw@paste.example.com:8388#Paste"
        try ProxySubscription.savePaste(body)
        defer { ProxySubscription.clearPaste() }
        let text = try ProxySubscription.loadText(source: ProxySubscription.sourcePaste, url: "")
        XCTAssertEqual(text, body)
        let parsed = ProxySubscription.parse(text)
        XCTAssertEqual(parsed.nodes.count, 1)
        XCTAssertEqual(parsed.nodes[0].server, "paste.example.com")
    }

    func testSortedProxyNodesByDelay() {
        let nodes = [
            ProxySubscription.Node(tag: "slow", title: "Slow", server: "a", proto: "ss"),
            ProxySubscription.Node(tag: "fast", title: "Fast", server: "b", proto: "ss"),
            ProxySubscription.Node(tag: "unknown", title: "Unknown", server: "c", proto: "ss"),
        ]
        let sorted = ProxySubscription.sortedByDelay(nodes, delays: ["slow": 200, "fast": 40])
        XCTAssertEqual(sorted.map(\.tag), ["fast", "slow", "unknown"])
    }
}
