package com.checkpoint.vpn.oneclick.vpn

/**
 * Bridge so Rust can open the VpnService TUN only after Check Point auth/IKE succeed.
 * Establishing earlier routes DNS into a dead tunnel and breaks gateway hostname lookup.
 */
object TunEstablisher {
    @Volatile
    var service: CheckpointVpnService? = null

    @JvmStatic
    fun establish(address: String, prefix: Int, mtu: Int, dnsCsv: String, routesCsv: String): Int {
        val svc = service ?: return -1
        return svc.establishTunForEngine(address, prefix, mtu, dnsCsv, routesCsv)
    }
}
