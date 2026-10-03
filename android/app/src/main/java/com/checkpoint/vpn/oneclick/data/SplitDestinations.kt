package com.checkpoint.vpn.oneclick.data

import java.net.Inet4Address
import java.net.InetAddress

object SplitDestinations {
    fun parse(raw: String): List<String> =
        raw
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .distinct()
            .toList()

    /** Resolve hostnames to IPv4 CIDRs for VpnService.Builder.addRoute. */
    fun resolveRoutes(raw: String): List<Pair<String, Int>> {
        val out = LinkedHashSet<Pair<String, Int>>()
        for (item in parse(raw)) {
            when {
                item.contains('/') -> {
                    val parts = item.split('/', limit = 2)
                    val host = parts[0]
                    val prefix = parts.getOrNull(1)?.toIntOrNull() ?: continue
                    val ip = resolveIpv4(host) ?: continue
                    out += ip to prefix.coerceIn(0, 32)
                }
                looksLikeIpv4(item) -> out += item to 32
                else -> {
                    val ip = resolveIpv4(item) ?: continue
                    out += ip to 32
                }
            }
        }
        return out.toList()
    }

    private fun looksLikeIpv4(value: String): Boolean =
        value.split('.').size == 4 && value.all { it.isDigit() || it == '.' }

    private fun resolveIpv4(host: String): String? {
        return try {
            val addresses = InetAddress.getAllByName(host)
            addresses.filterIsInstance<Inet4Address>().firstOrNull()?.hostAddress
        } catch (_: Exception) {
            null
        }
    }
}
