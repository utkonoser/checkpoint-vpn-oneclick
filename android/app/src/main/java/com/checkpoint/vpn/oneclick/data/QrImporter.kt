package com.checkpoint.vpn.oneclick.data

import android.content.Context
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

object QrImporter {
    suspend fun decodeUri(context: Context, uri: Uri): String {
        val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri))
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
        }
        val image = InputImage.fromBitmap(bitmap, 0)
        return decodeImage(image)
    }

    suspend fun decodeImage(image: InputImage): String {
        val scanner = BarcodeScanning.getClient()
        val barcodes = suspendCancellableCoroutine { cont ->
            scanner.process(image)
                .addOnSuccessListener { cont.resume(it) }
                .addOnFailureListener { cont.resumeWithException(it) }
        }
        val raw = barcodes
            .asSequence()
            .mapNotNull { it.rawValue?.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?: error("No QR code found in image")
        return normalizeTotpPayload(raw)
    }

    fun normalizeTotpPayload(raw: String): String {
        val trimmed = raw.trim()
        when {
            trimmed.startsWith("otpauth://", ignoreCase = true) -> return Totp.parseSecret(trimmed)
            trimmed.startsWith("otpauth-migration://", ignoreCase = true) ->
                error("Google Authenticator migration QR is not supported — export a single otpauth:// code")
            else -> {
                // Plain Base32 secret printed as QR.
                return Totp.parseSecret(trimmed)
            }
        }
    }

    fun isLikelyQrPayload(value: String): Boolean {
        val t = value.trim()
        return t.startsWith("otpauth://", ignoreCase = true) ||
            t.replace(" ", "").matches(Regex("^[A-Z2-7]+=*$", RegexOption.IGNORE_CASE))
    }
}
