package com.monadial.ash.core.services

import android.graphics.Bitmap
import android.graphics.Color
import android.util.Base64
import android.util.Log
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class QRCodeService @Inject constructor() {

    companion object {
        private const val TAG = "QRCodeService"
    }

    /**
     * Generate a QR code bitmap from raw bytes.
     * Uses L error correction level (7%) for maximum capacity.
     * Fountain codes provide their own redundancy.
     *
     * @param data Raw bytes to encode
     * @param size Target size in pixels
     * @return QR code bitmap or null on failure
     */
    fun generate(data: ByteArray, size: Int = 400): Bitmap? {
        return try {
            // Base64 encode for compatibility with QR string parsing
            val base64 = Base64.encodeToString(data, Base64.NO_WRAP)

            // Check if data is within QR code limits (roughly 2953 chars for L level)
            if (base64.length > 2900) {
                Log.e(TAG, "Data too large for QR code: ${base64.length} chars")
                return null
            }

            val writer = QRCodeWriter()
            val hints = mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.L,
                EncodeHintType.MARGIN to 1,
                EncodeHintType.CHARACTER_SET to "UTF-8"
            )

            val bitMatrix = writer.encode(base64, BarcodeFormat.QR_CODE, size, size, hints)

            val width = bitMatrix.width
            val height = bitMatrix.height

            // Use bulk pixel operations for performance (10-100x faster than setPixel)
            val pixels = IntArray(width * height)
            for (y in 0 until height) {
                val offset = y * width
                for (x in 0 until width) {
                    pixels[offset + x] = if (bitMatrix[x, y]) Color.BLACK else Color.WHITE
                }
            }

            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            bitmap
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate QR code: ${e.message}", e)
            null
        }
    }

    /**
     * Generate QR code with specific dimensions from the bit matrix.
     * More memory efficient for smaller displays.
     */
    fun generateCompact(data: ByteArray): Bitmap? {
        return try {
            val base64 = Base64.encodeToString(data, Base64.NO_WRAP)

            if (base64.length > 2900) {
                Log.e(TAG, "Data too large for QR code: ${base64.length} chars")
                return null
            }

            val writer = QRCodeWriter()
            val hints = mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.L,
                EncodeHintType.MARGIN to 1
            )

            // Let ZXing determine optimal size
            val bitMatrix = writer.encode(base64, BarcodeFormat.QR_CODE, 0, 0, hints)

            val width = bitMatrix.width
            val height = bitMatrix.height

            val pixels = IntArray(width * height)
            for (y in 0 until height) {
                val offset = y * width
                for (x in 0 until width) {
                    pixels[offset + x] = if (bitMatrix[x, y]) Color.BLACK else Color.WHITE
                }
            }

            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            bitmap
        } catch (e: Exception) {
            Log.e(TAG, "Failed to generate compact QR code: ${e.message}", e)
            null
        }
    }

    /**
     * Decode base64 string from QR code back to raw bytes.
     * Uses DEFAULT flag for maximum compatibility with iOS base64 encoding.
     */
    fun decodeBase64(base64String: String): ByteArray? {
        return try {
            // Use DEFAULT for decoding - it's more permissive and handles
            // both with/without line breaks and padding variations
            Base64.decode(base64String, Base64.DEFAULT)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to decode base64: ${e.message}")
            null
        }
    }
}
