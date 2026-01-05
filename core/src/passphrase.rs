//! Passphrase-based key derivation for QR frame encryption.
//!
//! This module provides simple key derivation for optional encryption of QR frames
//! during the ceremony. The purpose is to protect against visual observation
//! (shoulder-surfing) of QR codes, not to provide cryptographic security.
//!
//! # Design
//!
//! - Both parties verbally agree on a passphrase before ceremony
//! - Sender encrypts frame payloads with derived key
//! - Receiver decrypts using the same passphrase
//! - Header (index, total) remains unencrypted for progress tracking
//!
//! # Security Note
//!
//! This is NOT a replacement for performing the ceremony privately.
//! It provides an additional layer against casual observation.
//! The passphrase should be spoken, not typed or stored.

use crate::crc;

/// Minimum passphrase length (characters).
pub const MIN_PASSPHRASE_LENGTH: usize = 4;

/// Maximum passphrase length (characters).
pub const MAX_PASSPHRASE_LENGTH: usize = 64;

/// Derive a key stream for encrypting/decrypting frame payload.
///
/// Uses CRC-32 chaining to expand the passphrase into a key of the required length.
/// Each frame uses its index as additional input to ensure different keys per frame.
///
/// # Arguments
///
/// * `passphrase` - The shared passphrase (UTF-8 string)
/// * `frame_index` - The index of the frame being encrypted
/// * `length` - The required key length in bytes
///
/// # Returns
///
/// A vector of bytes to XOR with the payload.
pub fn derive_key(passphrase: &str, frame_index: u16, length: usize) -> Vec<u8> {
    if length == 0 {
        return Vec::new();
    }

    let mut key = Vec::with_capacity(length);

    // Initial seed: CRC of passphrase + frame index
    let passphrase_bytes = passphrase.as_bytes();
    let mut seed_data = Vec::with_capacity(passphrase_bytes.len() + 2);
    seed_data.extend_from_slice(passphrase_bytes);
    seed_data.extend_from_slice(&frame_index.to_be_bytes());

    let mut state = crc::compute(&seed_data);

    // Expand key using CRC chaining
    // Each iteration produces 4 bytes from CRC output
    let mut counter: u32 = 0;
    while key.len() < length {
        // Mix counter into state
        let mut block_input = Vec::with_capacity(12);
        block_input.extend_from_slice(&state.to_be_bytes());
        block_input.extend_from_slice(&counter.to_be_bytes());
        block_input.extend_from_slice(passphrase_bytes);

        state = crc::compute(&block_input);

        // Add state bytes to key
        for byte in state.to_be_bytes() {
            if key.len() < length {
                key.push(byte);
            }
        }

        counter = counter.wrapping_add(1);
    }

    key
}

/// XOR data with key (encryption and decryption are identical for XOR).
///
/// # Arguments
///
/// * `data` - The data to encrypt/decrypt
/// * `key` - The key stream (must be same length as data)
///
/// # Panics
///
/// Panics if key length doesn't match data length.
pub fn xor_bytes(data: &[u8], key: &[u8]) -> Vec<u8> {
    assert_eq!(
        data.len(),
        key.len(),
        "key length must match data length"
    );

    data.iter().zip(key.iter()).map(|(d, k)| d ^ k).collect()
}

/// Encrypt frame payload using passphrase.
///
/// # Arguments
///
/// * `passphrase` - The shared passphrase
/// * `frame_index` - Index of the frame
/// * `payload` - The plaintext payload
///
/// # Returns
///
/// Encrypted payload bytes.
pub fn encrypt_payload(passphrase: &str, frame_index: u16, payload: &[u8]) -> Vec<u8> {
    let key = derive_key(passphrase, frame_index, payload.len());
    xor_bytes(payload, &key)
}

/// Decrypt frame payload using passphrase.
///
/// # Arguments
///
/// * `passphrase` - The shared passphrase
/// * `frame_index` - Index of the frame
/// * `encrypted_payload` - The encrypted payload
///
/// # Returns
///
/// Decrypted payload bytes.
pub fn decrypt_payload(passphrase: &str, frame_index: u16, encrypted_payload: &[u8]) -> Vec<u8> {
    // XOR is symmetric - encryption and decryption are the same operation
    encrypt_payload(passphrase, frame_index, encrypted_payload)
}

/// Validate passphrase meets requirements.
///
/// # Arguments
///
/// * `passphrase` - The passphrase to validate
///
/// # Returns
///
/// Ok if valid, Err with reason if invalid.
pub fn validate_passphrase(passphrase: &str) -> Result<(), &'static str> {
    let len = passphrase.chars().count();

    if len < MIN_PASSPHRASE_LENGTH {
        return Err("passphrase too short");
    }

    if len > MAX_PASSPHRASE_LENGTH {
        return Err("passphrase too long");
    }

    // Must contain only printable ASCII for verbal communication
    if !passphrase.chars().all(|c| c.is_ascii() && !c.is_ascii_control()) {
        return Err("passphrase must contain only printable ASCII characters");
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_key_produces_correct_length() {
        let key = derive_key("test", 0, 100);
        assert_eq!(key.len(), 100);

        let key = derive_key("test", 0, 1000);
        assert_eq!(key.len(), 1000);

        let key = derive_key("test", 0, 0);
        assert_eq!(key.len(), 0);
    }

    #[test]
    fn derive_key_deterministic() {
        let key1 = derive_key("password", 5, 50);
        let key2 = derive_key("password", 5, 50);
        assert_eq!(key1, key2);
    }

    #[test]
    fn derive_key_different_for_different_frames() {
        let key1 = derive_key("password", 0, 50);
        let key2 = derive_key("password", 1, 50);
        assert_ne!(key1, key2);
    }

    #[test]
    fn derive_key_different_for_different_passphrases() {
        let key1 = derive_key("password1", 0, 50);
        let key2 = derive_key("password2", 0, 50);
        assert_ne!(key1, key2);
    }

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let passphrase = "secret phrase";
        let frame_index = 42;
        let plaintext = b"Hello, this is sensitive pad data!";

        let encrypted = encrypt_payload(passphrase, frame_index, plaintext);
        assert_ne!(&encrypted[..], plaintext); // Should be different

        let decrypted = decrypt_payload(passphrase, frame_index, &encrypted);
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn wrong_passphrase_produces_garbage() {
        let plaintext = b"Secret message";
        let encrypted = encrypt_payload("correct", 0, plaintext);
        let decrypted = decrypt_payload("wrong", 0, &encrypted);
        assert_ne!(decrypted, plaintext);
    }

    #[test]
    fn wrong_frame_index_produces_garbage() {
        let plaintext = b"Secret message";
        let encrypted = encrypt_payload("password", 0, plaintext);
        let decrypted = decrypt_payload("password", 1, &encrypted);
        assert_ne!(decrypted, plaintext);
    }

    #[test]
    fn validate_passphrase_valid() {
        assert!(validate_passphrase("test").is_ok());
        assert!(validate_passphrase("a longer passphrase").is_ok());
        assert!(validate_passphrase("with-special_chars!@#").is_ok());
    }

    #[test]
    fn validate_passphrase_too_short() {
        assert!(validate_passphrase("abc").is_err());
        assert!(validate_passphrase("").is_err());
    }

    #[test]
    fn validate_passphrase_too_long() {
        let long = "a".repeat(MAX_PASSPHRASE_LENGTH + 1);
        assert!(validate_passphrase(&long).is_err());
    }

    #[test]
    fn validate_passphrase_non_ascii() {
        assert!(validate_passphrase("пароль").is_err()); // Cyrillic
        assert!(validate_passphrase("密码").is_err()); // Chinese
        assert!(validate_passphrase("test\x00null").is_err()); // Control char
    }

    #[test]
    fn xor_symmetric() {
        let data = vec![1, 2, 3, 4, 5];
        let key = vec![10, 20, 30, 40, 50];

        let encrypted = xor_bytes(&data, &key);
        let decrypted = xor_bytes(&encrypted, &key);

        assert_eq!(decrypted, data);
    }
}
