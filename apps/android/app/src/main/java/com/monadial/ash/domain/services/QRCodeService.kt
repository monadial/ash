package com.monadial.ash.domain.services

import android.graphics.Bitmap

/**
 * Service interface for QR code generation and decoding.
 *
 * This is a domain-level abstraction that allows for testing and mocking.
 * Note: Uses Android Bitmap type - this is a pragmatic trade-off for Android-only apps
 * to avoid over-engineering platform-neutral abstractions.
 */
interface QRCodeService {
    /**
     * Generate a QR code bitmap from raw bytes.
     *
     * @param data Raw bytes to encode
     * @param size Target size in pixels
     * @return QR code bitmap or null on failure
     */
    fun generate(data: ByteArray, size: Int = 600): Bitmap?

    /**
     * Generate a compact QR code (smaller file size).
     *
     * @param data Raw bytes to encode
     * @return QR code bitmap or null on failure
     */
    fun generateCompact(data: ByteArray): Bitmap?

    /**
     * Decode base64 string from QR code back to raw bytes.
     *
     * @param base64String Base64 encoded string from scanned QR code
     * @return Decoded bytes or null on failure
     */
    fun decodeBase64(base64String: String): ByteArray?
}
