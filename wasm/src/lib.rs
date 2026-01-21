//! WebAssembly bindings for ASH cryptographic core.
//!
//! This crate exposes the core cryptographic functions to JavaScript
//! for use in browser-based demonstrations and educational purposes.
//!
//! Note: For production use, always use MessageFrame which includes
//! authentication. The raw OTP functions here are exposed for the
//! educational demo only.

use wasm_bindgen::prelude::*;

// Re-export core types for internal use
use ash_core::mac::{AuthKey, AUTH_KEY_SIZE, TAG_SIZE};
use ash_core::message::MIN_PADDED_SIZE;

/// XOR two byte slices (internal helper).
fn xor_bytes(key: &[u8], data: &[u8]) -> Result<Vec<u8>, JsError> {
    if key.len() != data.len() {
        return Err(JsError::new(&format!(
            "Length mismatch: key {} bytes, data {} bytes",
            key.len(),
            data.len()
        )));
    }
    Ok(key.iter().zip(data.iter()).map(|(k, d)| k ^ d).collect())
}

/// OTP encrypt: XOR plaintext with key bytes.
///
/// # Arguments
/// * `key` - Key bytes (must equal plaintext length)
/// * `plaintext` - Data to encrypt
///
/// # Returns
/// Ciphertext bytes, or throws on length mismatch.
#[wasm_bindgen]
pub fn otp_encrypt(key: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, JsError> {
    xor_bytes(key, plaintext)
}

/// OTP decrypt: XOR ciphertext with key bytes.
///
/// Since XOR is symmetric, this is the same operation as encrypt.
#[wasm_bindgen]
pub fn otp_decrypt(key: &[u8], ciphertext: &[u8]) -> Result<Vec<u8>, JsError> {
    xor_bytes(key, ciphertext)
}

/// Compute 256-bit Wegman-Carter authentication tag.
///
/// # Arguments
/// * `auth_key` - 64 bytes from pad (r1 || r2 || s1 || s2)
/// * `header` - Frame header bytes
/// * `ciphertext` - Encrypted payload
///
/// # Returns
/// 32-byte authentication tag.
#[wasm_bindgen]
pub fn compute_auth_tag(auth_key: &[u8], header: &[u8], ciphertext: &[u8]) -> Result<Vec<u8>, JsError> {
    if auth_key.len() != AUTH_KEY_SIZE {
        return Err(JsError::new(&format!(
            "Auth key must be {} bytes, got {}",
            AUTH_KEY_SIZE,
            auth_key.len()
        )));
    }

    let key = AuthKey::from_slice(auth_key);
    let tag = ash_core::mac::compute_tag(&key, header, ciphertext);
    Ok(tag.to_vec())
}

/// Verify 256-bit Wegman-Carter authentication tag.
///
/// # Arguments
/// * `auth_key` - 64 bytes from pad
/// * `header` - Frame header bytes
/// * `ciphertext` - Encrypted payload
/// * `tag` - 32-byte tag to verify
///
/// # Returns
/// true if valid, false otherwise.
#[wasm_bindgen]
pub fn verify_auth_tag(auth_key: &[u8], header: &[u8], ciphertext: &[u8], tag: &[u8]) -> Result<bool, JsError> {
    if auth_key.len() != AUTH_KEY_SIZE {
        return Err(JsError::new(&format!(
            "Auth key must be {} bytes, got {}",
            AUTH_KEY_SIZE,
            auth_key.len()
        )));
    }
    if tag.len() != TAG_SIZE {
        return Err(JsError::new(&format!(
            "Tag must be {} bytes, got {}",
            TAG_SIZE,
            tag.len()
        )));
    }

    let key = AuthKey::from_slice(auth_key);
    let tag_arr: [u8; TAG_SIZE] = tag.try_into().unwrap();
    Ok(ash_core::mac::verify_tag(&key, header, ciphertext, &tag_arr))
}

/// Pad a message to minimum 32 bytes.
///
/// Format: [0x00 marker][2-byte length BE][content][zero padding]
///
/// # Arguments
/// * `message` - Original message bytes
///
/// # Returns
/// Padded message (minimum 32 bytes).
#[wasm_bindgen]
pub fn pad_message(message: &[u8]) -> Result<Vec<u8>, JsError> {
    ash_core::message::pad_message(message).map_err(|e| JsError::new(&e.to_string()))
}

/// Remove padding from a message.
///
/// # Arguments
/// * `padded` - Padded message bytes
///
/// # Returns
/// Original message bytes.
#[wasm_bindgen]
pub fn unpad_message(padded: &[u8]) -> Result<Vec<u8>, JsError> {
    ash_core::message::unpad_message(padded).map_err(|e| JsError::new(&e.to_string()))
}

/// Get the minimum padded message size (32 bytes).
#[wasm_bindgen]
pub fn get_min_padded_size() -> usize {
    MIN_PADDED_SIZE
}

/// Get the authentication key size (64 bytes).
#[wasm_bindgen]
pub fn get_auth_key_size() -> usize {
    AUTH_KEY_SIZE
}

/// Get the authentication tag size (32 bytes).
#[wasm_bindgen]
pub fn get_tag_size() -> usize {
    TAG_SIZE
}

/// Convert bytes to hex string (for display).
#[wasm_bindgen]
pub fn bytes_to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02X}", b)).collect()
}

/// Convert hex string to bytes.
#[wasm_bindgen]
pub fn hex_to_bytes(hex: &str) -> Result<Vec<u8>, JsError> {
    if hex.len() % 2 != 0 {
        return Err(JsError::new("Hex string must have even length"));
    }

    (0..hex.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&hex[i..i + 2], 16)
                .map_err(|_| JsError::new("Invalid hex character"))
        })
        .collect()
}

// === Mnemonic Generation ===

/// Generate a mnemonic checksum from pad bytes.
///
/// Returns a comma-separated string of 6 words from the custom wordlist.
/// Both parties can compare these words verbally to verify pad integrity.
#[wasm_bindgen]
pub fn generate_mnemonic(pad_bytes: &[u8]) -> String {
    let words = ash_core::mnemonic::generate_default(pad_bytes);
    words.join(" ")
}

/// Generate a mnemonic with custom word count.
#[wasm_bindgen]
pub fn generate_mnemonic_n(pad_bytes: &[u8], word_count: usize) -> String {
    let words = ash_core::mnemonic::generate(pad_bytes, word_count);
    words.join(" ")
}

// === Token Derivation ===

/// Minimum pad size needed for token derivation (160 bytes).
#[wasm_bindgen]
pub fn get_min_pad_size_for_tokens() -> usize {
    ash_core::auth::MIN_PAD_SIZE_FOR_TOKENS
}

/// Derive conversation ID from pad bytes.
///
/// Returns a 64-character hex string identifying the conversation.
#[wasm_bindgen]
pub fn derive_conversation_id(pad_bytes: &[u8]) -> Result<String, JsError> {
    ash_core::auth::derive_conversation_id(pad_bytes)
        .map_err(|e| JsError::new(&e.to_string()))
}

/// Derive auth token from pad bytes.
///
/// Returns a 64-character hex string used for API authentication.
#[wasm_bindgen]
pub fn derive_auth_token(pad_bytes: &[u8]) -> Result<String, JsError> {
    ash_core::auth::derive_auth_token(pad_bytes)
        .map_err(|e| JsError::new(&e.to_string()))
}

/// Derive burn token from pad bytes.
///
/// Returns a 64-character hex string required for burning conversations.
#[wasm_bindgen]
pub fn derive_burn_token(pad_bytes: &[u8]) -> Result<String, JsError> {
    ash_core::auth::derive_burn_token(pad_bytes)
        .map_err(|e| JsError::new(&e.to_string()))
}

// === CRC-32 ===

/// Compute CRC-32 checksum (ISO 3309 polynomial).
#[wasm_bindgen]
pub fn compute_crc32(data: &[u8]) -> u32 {
    ash_core::crc::compute(data)
}

/// Verify CRC-32 checksum.
#[wasm_bindgen]
pub fn verify_crc32(data: &[u8], expected: u32) -> bool {
    ash_core::crc::verify(data, expected)
}

// === Passphrase Key Derivation ===

/// Derive key bytes from passphrase for frame encryption.
#[wasm_bindgen]
pub fn derive_passphrase_key(passphrase: &str, frame_index: u16, length: usize) -> Vec<u8> {
    ash_core::passphrase::derive_key(passphrase, frame_index, length)
}

