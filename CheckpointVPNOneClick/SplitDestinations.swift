import Foundation

/// User-configured destinations that should go through the work VPN (CIDRs and hostnames).
enum SplitDestinations {
    struct Parsed: Equatable {
        var cidrs: [String]
        var hosts: [String]

        var isEmpty: Bool { cidrs.isEmpty && hosts.isEmpty }

        var allLines: [String] { cidrs + hosts }
    }

    /// One entry per line: `10.0.0.0/8`, `192.168.1.1`, or `corp.example`.
    static func parse(_ raw: String) -> Parsed {
        var cidrs: [String] = []
        var hosts: [String] = []
        var seen = Set<String>()

        for line in raw.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let entry = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
            let key = entry.lowercased()
            guard seen.insert(key).inserted else { continue }

            if looksLikeCIDROrIP(entry) {
                cidrs.append(normalizeIPOrCIDR(entry))
            } else {
                hosts.append(key)
            }
        }
        return Parsed(cidrs: cidrs, hosts: hosts)
    }

    /// Resolve hostnames and return unique CIDRs for snx-rs `add-routes`.
    static func resolveAddRoutes(_ raw: String) throws -> [String] {
        let parsed = parse(raw)
        var routes = parsed.cidrs
        var seen = Set(routes)
        for host in parsed.hosts {
            for ip in try resolveIPv4(host) {
                let cidr = "\(ip)/32"
                if seen.insert(cidr).inserted {
                    routes.append(cidr)
                }
            }
        }
        return routes
    }

    private static func looksLikeCIDROrIP(_ value: String) -> Bool {
        let hostPart = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
        var addr = in_addr()
        return hostPart.withCString { inet_pton(AF_INET, $0, &addr) == 1 }
    }

    private static func normalizeIPOrCIDR(_ value: String) -> String {
        if value.contains("/") { return value }
        return "\(value)/32"
    }

    private static func resolveIPv4(_ host: String) throws -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let first = result else {
            let message = String(cString: gai_strerror(status))
            throw SnxClient.Error.failed("Could not resolve \(host): \(message)")
        }
        defer { freeaddrinfo(first) }

        var ips: [String] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = first
        while let info = ptr {
            if info.pointee.ai_family == AF_INET, let addr = info.pointee.ai_addr {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr,
                    socklen_t(info.pointee.ai_addrlen),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ip = String(cString: hostname)
                    if !ips.contains(ip) { ips.append(ip) }
                }
            }
            ptr = info.pointee.ai_next
        }
        if ips.isEmpty {
            throw SnxClient.Error.failed("No IPv4 addresses for \(host)")
        }
        return ips
    }
}
