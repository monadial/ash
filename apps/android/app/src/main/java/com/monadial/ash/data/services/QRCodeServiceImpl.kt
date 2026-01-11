package com.monadial.ash.data.services

import android.graphics.Bitmap
import android.graphics.Color
import android.util.Base64
import android.util.Log
import androidx.core.graphics.createBitmap
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.monadial.ash.domain.services.QRCodeService
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Implementation of QR code generation and decoding service.
 *
 * Uses ZXing library for QR code generation with optimized settings:
 * - L error correction (7%) for maximum capacity (fountain codes provide redundancy)
 * - Base64 encoding for QR string compatibility
 * - Bulk pixel operations for performance
 */
@Singleton
class QRCodeServiceImpl @Inject constructor() : QRCodeService {

    companion object {
        private const val TAG = "QRCodeService"
        private const val MAX_BASE64_LENGTH = 2900
    }

    override fun generate(data: ByteArray, size: Int): Bitmap? {
        return try {
            val base64 = Base64.encodeToString(data, Base64.NO_WRAP)

            if (base64.length > MAX_BASE64_LENGTH) {
                Log.e(TAG, "Data too large for QR code: ${base64.length} chars")
                return null
            }

            Log.d(TAG, "Generating QR code: ${data.size} bytes -> ${base64.length} chars base64, target size: $size px")

            val writer = QRCodeWriter()
            val hints = mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.L,
                EncodeHintType.MARGIN to 1,
                EncodeHintType.CHARACTER_SET to "ISO-8859-1"
            )

            val bitMatrix = writer.encode(base64, BarcodeFormat.QR_CODE, size, size, hints)
            createBitmapFromMatrix(bitMatrix, Bitmap.Config.ARGB_8888)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate QR code: ${e.message}", e)
            null
        }
    }

    override fun generateCompact(data: ByteArray): Bitmap? {
        return try {
            val base64 = Base64.encodeToString(data, Base64.NO_WRAP)

            if (base64.length > MAX_BASE64_LENGTH) {
                Log.e(TAG, "Data too large for QR code: ${base64.length} chars")
                return null
            }

            val writer = QRCodeWriter()
            val hints = mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.L,
                EncodeHintType.MARGIN to 1
            )

            val bitMatrix = writer.encode(base64, BarcodeFormat.QR_CODE, 0, 0, hints)
            createBitmapFromMatrix(bitMatrix, Bitmap.Config.RGB_565)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate compact QR code: ${e.message}", e)
            null
        }
    }

    override fun decodeBase64(base64String: String): ByteArray? = try {
        Base64.decode(base64String, Base64.DEFAULT)
    } catch (e: Exception) {
        Log.e(TAG, "Failed to decode base64: ${e.message}")
        null
    }

    private fun createBitmapFromMatrix(
        bitMatrix: com.google.zxing.common.BitMatrix,
        config: Bitmap.Config
    ): Bitmap {
        val width = bitMatrix.width
        val height = bitMatrix.height

        val pixels = IntArray(width * height)
        for (y in 0 until height) {
            val offset = y * width
            for (x in 0 until width) {
                pixels[offset + x] = if (bitMatrix[x, y]) Color.BLACK else Color.WHITE
            }
        }

        val bitmap = createBitmap(width, height, config)
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)

        Log.d(TAG, "QR code generated: ${width}x$height pixels")
        return bitmap
    }
}
