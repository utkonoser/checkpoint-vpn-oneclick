package com.checkpoint.vpn.oneclick

import com.checkpoint.vpn.oneclick.data.QrImporter
import org.junit.Assert.assertEquals
import org.junit.Test

class QrImporterTest {
    @Test
    fun normalizeOtpAuth() {
        val raw = "otpauth://totp/Example:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
        assertEquals("JBSWY3DPEHPK3PXP", QrImporter.normalizeTotpPayload(raw))
    }

    @Test
    fun normalizePlainSecret() {
        assertEquals("JBSWY3DPEHPK3PXP", QrImporter.normalizeTotpPayload("jbswy3dpehpk3pxp"))
    }
}
