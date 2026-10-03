package com.checkpoint.vpn.oneclick

import com.checkpoint.vpn.oneclick.data.Totp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TotpTest {
    @Test
    fun parsePlainBase32() {
        assertEquals("JBSWY3DPEHPK3PXP", Totp.parseSecret("jbswy3dpehpk3pxp"))
    }

    @Test
    fun parseOtpAuth() {
        val uri = "otpauth://totp/Example:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
        assertEquals("JBSWY3DPEHPK3PXP", Totp.parseSecret(uri))
    }

    @Test
    fun codeIsSixDigits() {
        val code = Totp.currentCode("JBSWY3DPEHPK3PXP")
        assertEquals(6, code.length)
        assertTrue(code.all { it.isDigit() })
    }
}
