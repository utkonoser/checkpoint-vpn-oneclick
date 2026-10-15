import Foundation

/// Parse proxy subscription URI lists and build a sing-box config (selector + urltest + nodes).
enum ProxySubscription {
    static let defaultURL =
        "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_SS%2BAll_RUS.txt"
    static let sourceURL = "url"
    static let sourcePaste = "paste"
    static let autoTag = "auto"
    static let selectorTag = "proxy"
    static let clashAPIPort = 9097
    static let clashAPISecret = "checkpoint-vpn-proxy-local"
    static let tunInterface = "utun223"

    struct Node: Equatable, Identifiable, Codable {
        var id: String { tag }
        var tag: String
        var title: String
        var server: String
        var proto: String
    }

    struct Parsed: Equatable {
        var nodes: [Node]
        var outbounds: [[String: Any]]

        static func == (lhs: Parsed, rhs: Parsed) -> Bool {
            lhs.nodes == rhs.nodes
        }
    }

    enum Error: Swift.Error, LocalizedError, Equatable {
        case empty
        case fetch(String)
        case encode

        var errorDescription: String? {
            switch self {
            case .empty: return "Subscription has no usable proxy nodes."
            case .fetch(let m): return m
            case .encode: return "Could not encode sing-box config."
            }
        }
    }

    static func supportDir() throws -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CheckpointVPNOneClick", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir
    }

    static func nodesCacheURL() throws -> URL {
        try supportDir().appendingPathComponent("proxy-nodes.json")
    }

    static func configURL() throws -> URL {
        try supportDir().appendingPathComponent("sing-box.json")
    }

    static func pasteURL() throws -> URL {
        try supportDir().appendingPathComponent("proxy-subscription.txt")
    }

    static func loadPaste() -> String {
        guard let url = try? pasteURL(),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return "" }
        return text
    }

    static func savePaste(_ text: String) throws {
        let url = try pasteURL()
        try Data(text.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func clearPaste() {
        guard let url = try? pasteURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Resolve subscription body from URL fetch or saved paste (`source` is `url` / `paste`).
    static func loadText(source: String, url: String) throws -> String {
        if source == sourcePaste {
            let text = loadPaste()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Error.empty
            }
            return text
        }
        return try fetch(urlString: url)
    }

    static func fetch(urlString: String) throws -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.isEmpty ? defaultURL : trimmed) else {
            throw Error.fetch("Invalid subscription URL")
        }
        let sem = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultError: Swift.Error?
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            defer { sem.signal() }
            if let error { resultError = error; return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code), let data else {
                resultError = Error.fetch("HTTP \(code) fetching subscription")
                return
            }
            resultData = data
        }
        task.resume()
        if sem.wait(timeout: .now() + 45) == .timedOut {
            throw Error.fetch("Timed out fetching subscription")
        }
        if let resultError { throw resultError }
        guard let data = resultData, let text = String(data: data, encoding: .utf8) else {
            throw Error.fetch("Empty subscription body")
        }
        return text
    }

    static func parse(_ text: String) -> Parsed {
        var nodes: [Node] = []
        var outbounds: [[String: Any]] = []
        var usedTags = Set<String>()

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let (node, outbound) = parseURI(line, usedTags: &usedTags) else { continue }
            nodes.append(node)
            outbounds.append(outbound)
        }
        return Parsed(nodes: nodes, outbounds: outbounds)
    }

    static func buildConfig(parsed: Parsed, selectedTag: String) throws -> Data {
        guard !parsed.nodes.isEmpty else { throw Error.empty }
        let nodeTags = parsed.nodes.map(\.tag)
        let defaultTag = nodeTags.contains(selectedTag) || selectedTag == autoTag ? selectedTag : autoTag

        var outbounds: [[String: Any]] = parsed.outbounds
        outbounds.append([
            "type": "urltest",
            "tag": autoTag,
            "outbounds": nodeTags,
            "url": "https://www.gstatic.com/generate_204",
            "interval": "3m",
            "tolerance": 50,
        ])
        outbounds.append([
            "type": "selector",
            "tag": selectorTag,
            "outbounds": [autoTag] + nodeTags,
            "default": defaultTag,
        ])
        outbounds.append(["type": "direct", "tag": "direct"])

        let root: [String: Any] = [
            "log": ["level": "info", "timestamp": true],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "interface_name": tunInterface,
                "address": ["172.19.0.1/30"],
                "mtu": 1500,
                "auto_route": false,
                "strict_route": false,
                "stack": "system",
            ]],
            "outbounds": outbounds,
            "route": [
                "auto_detect_interface": true,
                "final": selectorTag,
            ],
            "experimental": [
                "clash_api": [
                    "external_controller": "127.0.0.1:\(clashAPIPort)",
                    "secret": clashAPISecret,
                ],
            ],
        ]

        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else {
            throw Error.encode
        }
        return data
    }

    static func save(parsed: Parsed, selectedTag: String) throws -> URL {
        let data = try buildConfig(parsed: parsed, selectedTag: selectedTag)
        let url = try configURL()
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        let cache = try JSONEncoder().encode(parsed.nodes)
        try cache.write(to: try nodesCacheURL(), options: .atomic)
        return url
    }

    static func loadCachedNodes() -> [Node] {
        guard let url = try? nodesCacheURL(),
              let data = try? Data(contentsOf: url),
              let nodes = try? JSONDecoder().decode([Node].self, from: data)
        else { return [] }
        return nodes
    }

    /// Lowest ping first; unknown delay sinks to the bottom (then by title).
    static func sortedByDelay(_ nodes: [Node], delays: [String: Int]) -> [Node] {
        nodes.sorted { a, b in
            let da = delays[a.tag]
            let db = delays[b.tag]
            switch (da, db) {
            case let (x?, y?):
                if x != y { return x < y }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    /// Unique server hosts for Check Point ignore-routes (resolved by caller).
    static func serverHosts(in nodes: [Node]) -> [String] {
        var seen = Set<String>()
        var hosts: [String] = []
        for n in nodes {
            let h = n.server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !h.isEmpty, seen.insert(h).inserted else { continue }
            hosts.append(h)
        }
        return hosts
    }

    // MARK: - URI parsers

    private static func parseURI(_ line: String, usedTags: inout Set<String>) -> (Node, [String: Any])? {
        let lower = line.lowercased()
        if lower.hasPrefix("hysteria2://") || lower.hasPrefix("hy2://") {
            return parseHysteria2(line, usedTags: &usedTags)
        }
        if lower.hasPrefix("ss://") {
            return parseShadowsocks(line, usedTags: &usedTags)
        }
        if lower.hasPrefix("trojan://") {
            return parseTrojan(line, usedTags: &usedTags)
        }
        if lower.hasPrefix("vmess://") {
            return parseVmess(line, usedTags: &usedTags)
        }
        return nil
    }

    private static func uniqueTag(_ base: String, usedTags: inout Set<String>) -> String {
        var cleaned = base
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"[^\w.\-]+"#, with: "", options: .regularExpression)
        if cleaned.isEmpty { cleaned = "node" }
        if cleaned.count > 48 { cleaned = String(cleaned.prefix(48)) }
        var tag = cleaned
        var i = 2
        while usedTags.contains(tag) || tag == autoTag || tag == selectorTag || tag == "direct" {
            tag = "\(cleaned)-\(i)"
            i += 1
        }
        usedTags.insert(tag)
        return tag
    }

    private static func fragmentTitle(from url: URL, fallback: String) -> String {
        guard let frag = url.fragment, !frag.isEmpty else { return fallback }
        return frag.removingPercentEncoding ?? frag
    }

    private static func parseHysteria2(_ line: String, usedTags: inout Set<String>) -> (Node, [String: Any])? {
        var normalized = line
        if normalized.lowercased().hasPrefix("hy2://") {
            normalized = "hysteria2://" + normalized.dropFirst(6)
        }
        guard let url = URL(string: normalized),
              let host = url.host, !host.isEmpty,
              let port = url.port ?? Optional(443)
        else { return nil }
        let password = url.user?.removingPercentEncoding ?? url.user ?? ""
        guard !password.isEmpty else { return nil }
        let title = fragmentTitle(from: url, fallback: "\(host):\(port)")
        let tag = uniqueTag(title, usedTags: &usedTags)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        let sni = q("sni") ?? q("server_name") ?? host
        let insecure = (q("insecure") == "1" || q("allowInsecure") == "1")
        var tls: [String: Any] = ["enabled": true, "server_name": sni, "insecure": insecure]
        if let alpn = q("alpn"), !alpn.isEmpty {
            tls["alpn"] = alpn.split(separator: ",").map(String.init)
        }
        let outbound: [String: Any] = [
            "type": "hysteria2",
            "tag": tag,
            "server": host,
            "server_port": port,
            "password": password,
            "tls": tls,
        ]
        return (Node(tag: tag, title: title, server: host, proto: "hysteria2"), outbound)
    }

    private static func parseTrojan(_ line: String, usedTags: inout Set<String>) -> (Node, [String: Any])? {
        guard let url = URL(string: line),
              let host = url.host, !host.isEmpty,
              let port = url.port ?? Optional(443)
        else { return nil }
        let password = url.user?.removingPercentEncoding ?? url.user ?? ""
        guard !password.isEmpty else { return nil }
        let title = fragmentTitle(from: url, fallback: "\(host):\(port)")
        let tag = uniqueTag(title, usedTags: &usedTags)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        let sni = q("sni") ?? q("peer") ?? host
        let insecure = (q("allowInsecure") == "1" || q("insecure") == "1")
        let outbound: [String: Any] = [
            "type": "trojan",
            "tag": tag,
            "server": host,
            "server_port": port,
            "password": password,
            "tls": ["enabled": true, "server_name": sni, "insecure": insecure],
        ]
        return (Node(tag: tag, title: title, server: host, proto: "trojan"), outbound)
    }

    private static func parseShadowsocks(_ line: String, usedTags: inout Set<String>) -> (Node, [String: Any])? {
        // ss://base64(method:pass@host:port)#name  OR  ss://method:pass@host:port
        let withoutScheme = String(line.dropFirst(5))
        let parts = withoutScheme.split(separator: "#", maxSplits: 1).map(String.init)
        let main = parts[0]
        let titlePart = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : nil

        var method = ""
        var password = ""
        var host = ""
        var port = 0

        if main.contains("@"), let at = main.lastIndex(of: "@") {
            let userinfo = String(main[..<at]).removingPercentEncoding ?? String(main[..<at])
            let hostport = String(main[main.index(after: at)...])
            if userinfo.contains(":"), let colon = userinfo.firstIndex(of: ":") {
                method = String(userinfo[..<colon])
                password = String(userinfo[userinfo.index(after: colon)...])
            } else if let decoded = Data(base64Encoded: padBase64(userinfo)),
                      let text = String(data: decoded, encoding: .utf8),
                      let c = text.firstIndex(of: ":") {
                method = String(text[..<c])
                password = String(text[text.index(after: c)...])
            }
            if let colon = hostport.lastIndex(of: ":") {
                host = String(hostport[..<colon])
                port = Int(hostport[hostport.index(after: colon)...]) ?? 0
            }
        } else {
            let b64 = main.components(separatedBy: "/").first ?? main
            guard let data = Data(base64Encoded: padBase64(b64)),
                  let text = String(data: data, encoding: .utf8),
                  let at = text.lastIndex(of: "@")
            else { return nil }
            let userinfo = String(text[..<at])
            let hostport = String(text[text.index(after: at)...])
            guard let c = userinfo.firstIndex(of: ":"),
                  let hc = hostport.lastIndex(of: ":")
            else { return nil }
            method = String(userinfo[..<c])
            password = String(userinfo[userinfo.index(after: c)...])
            host = String(hostport[..<hc])
            port = Int(hostport[hostport.index(after: hc)...]) ?? 0
        }

        guard !method.isEmpty, !password.isEmpty, !host.isEmpty, port > 0 else { return nil }
        let title = titlePart ?? "\(host):\(port)"
        let tag = uniqueTag(title, usedTags: &usedTags)
        let outbound: [String: Any] = [
            "type": "shadowsocks",
            "tag": tag,
            "server": host,
            "server_port": port,
            "method": method,
            "password": password,
        ]
        return (Node(tag: tag, title: title, server: host, proto: "ss"), outbound)
    }

    private static func parseVmess(_ line: String, usedTags: inout Set<String>) -> (Node, [String: Any])? {
        let b64 = String(line.dropFirst(8))
        guard let data = Data(base64Encoded: padBase64(b64)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let host = (obj["add"] as? String) ?? ""
        let port: Int = {
            if let n = obj["port"] as? Int { return n }
            if let s = obj["port"] as? String { return Int(s) ?? 0 }
            return 0
        }()
        let uuid = (obj["id"] as? String) ?? ""
        guard !host.isEmpty, port > 0, !uuid.isEmpty else { return nil }
        let title = (obj["ps"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(host):\(port)"
        let tag = uniqueTag(title, usedTags: &usedTags)
        let security = (obj["scy"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "auto"
        var outbound: [String: Any] = [
            "type": "vmess",
            "tag": tag,
            "server": host,
            "server_port": port,
            "uuid": uuid,
            "security": security,
            "alter_id": (obj["aid"] as? Int) ?? Int(obj["aid"] as? String ?? "") ?? 0,
        ]
        let tlsFlag = (obj["tls"] as? String)?.lowercased()
        if tlsFlag == "tls" {
            let sni = (obj["sni"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? host
            outbound["tls"] = ["enabled": true, "server_name": sni]
        }
        let net = (obj["net"] as? String)?.lowercased() ?? "tcp"
        if net == "ws" {
            var ws: [String: Any] = ["type": "ws"]
            if let path = obj["path"] as? String, !path.isEmpty { ws["path"] = path }
            if let hostHeader = obj["host"] as? String, !hostHeader.isEmpty {
                ws["headers"] = ["Host": hostHeader]
            }
            outbound["transport"] = ws
        }
        return (Node(tag: tag, title: title, server: host, proto: "vmess"), outbound)
    }

    private static func padBase64(_ value: String) -> String {
        var s = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = s.count % 4
        if rem > 0 { s += String(repeating: "=", count: 4 - rem) }
        return s
    }
}
