package com.checkpoint.vpn.oneclick.data

import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.math.pow

object Totp {
    data class Secret(
        val key: ByteArray,
        val period: Long = 30,
        val digits: Int = 6,
    )

    fun parseSecret(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.startsWith("otpauth://", ignoreCase = true)) {
            val query = trimmed.substringAfter('?', "")
            val secret = query
                .split('&')
                .mapNotNull { part ->
                    val key = part.substringBefore('=')
                    val value = part.substringAfter('=', "")
                    if (key.equals("secret", ignoreCase = true)) value else null
                }
                .firstOrNull()
                ?.trim()
                ?.uppercase()
                ?: error("otpauth URI missing secret")
            return secret
        }
        return trimmed.replace(" ", "").uppercase()
    }

    fun currentCode(base32Secret: String, nowMillis: Long = System.currentTimeMillis()): String {
        val secret = decodeBase32(parseSecret(base32Secret))
        val counter = nowMillis / 1000 / 30
        return hotp(secret, counter, 6)
    }

    fun secondsRemaining(nowMillis: Long = System.currentTimeMillis()): Long {
        val period = 30L
        return period - ((nowMillis / 1000) % period)
    }

    private fun hotp(key: ByteArray, counter: Long, digits: Int): String {
        val data = ByteBuffer.allocate(8).putLong(counter).array()
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(key, "HmacSHA1"))
        val hash = mac.doFinal(data)
        val offset = hash.last().toInt() and 0x0f
        val binary =
            ((hash[offset].toInt() and 0x7f) shl 24) or
                ((hash[offset + 1].toInt() and 0xff) shl 16) or
                ((hash[offset + 2].toInt() and 0xff) shl 8) or
                (hash[offset + 3].toInt() and 0xff)
        val otp = binary % 10.0.pow(digits).toInt()
        return otp.toString().padStart(digits, '0')
    }

    private fun decodeBase32(input: String): ByteArray {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        val cleaned = input.uppercase().filter { it != '=' }
        var buffer = 0
        var bitsLeft = 0
        val out = ArrayList<Byte>()
        for (ch in cleaned) {
            val value = alphabet.indexOf(ch)
            require(value >= 0) { "Invalid Base32 character: $ch" }
            buffer = (buffer shl 5) or value
            bitsLeft += 5
            if (bitsLeft >= 8) {
                out.add(((buffer shr (bitsLeft - 8)) and 0xff).toByte())
                bitsLeft -= 8
            }
        }
        return out.toByteArray()
    }
}
