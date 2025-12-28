//! One-Time Pad encryption and decryption.
//!
//! OTP provides information-theoretic security when:
//! - The key is truly random
//! - The key is at least as long as the message
//! - The key is never reused
//!
//! This module provides the XOR operation; the Pad module
//! enforces the single-use constraint.

use crate::error::{Error, Result};

/// Encrypt plaintext using OTP (XOR with pad bytes).
///
/// # Arguments
///
/// * `pad_slice` - Key material from the pad (must equal plaintext length)
/// * `plaintext` - Data to encrypt
///
/// # Returns
///
/// Ciphertext of the same length as input.
///
/// # Errors
///
/// Returns `Error::LengthMismatch` if lengths don't match.
///
/// # Example
///
/// ```
/// use ash_core::otp;
///
/// let key = [0xAB, 0xCD, 0xEF];
/// let plaintext = [0x01, 0x02, 0x03];
/// let ciphertext = otp::encrypt(&key, &plaintext).unwrap();
/// assert_eq!(ciphertext, vec![0xAA, 0xCF, 0xEC]);
/// ```
pub fn encrypt(pad_slice: &[u8], plaintext: &[u8]) -> Result<Vec<u8>> {
    xor(pad_slice, plaintext)
}

/// Decrypt ciphertext using OTP (XOR with pad bytes).
///
/// Since XOR is symmetric, this is the same operation as encrypt.
///
/// # Arguments
///
/// * `pad_slice` - Key material from the pad (must equal ciphertext length)
/// * `ciphertext` - Data to decrypt
///
/// # Returns
///
/// Plaintext of the same length as input.
///
/// # Errors
///
/// Returns `Error::LengthMismatch` if lengths don't match.
pub fn decrypt(pad_slice: &[u8], ciphertext: &[u8]) -> Result<Vec<u8>> {
    xor(pad_slice, ciphertext)
}

/// XOR two byte slices of equal length.
#[inline]
fn xor(key: &[u8], data: &[u8]) -> Result<Vec<u8>> {
    if key.len() != data.len() {
        return Err(Error::LengthMismatch {
            pad_len: key.len(),
            data_len: data.len(),
        });
    }

    Ok(key.iter().zip(data.iter()).map(|(k, d)| k ^ d).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xor_basic() {
        let key = [0xFF, 0x00, 0xAA];
        let data = [0x00, 0xFF, 0x55];
        let result = xor(&key, &data).unwrap();
        assert_eq!(result, vec![0xFF, 0xFF, 0xFF]);
    }

    #[test]
    fn xor_length_mismatch() {
        let key = [0x00, 0x00];
        let data = [0x00, 0x00, 0x00];
        let result = xor(&key, &data);
        assert!(matches!(result, Err(Error::LengthMismatch { .. })));
    }

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let key = vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE];
        let plaintext = b"Hello!".to_vec();

        let ciphertext = encrypt(&key, &plaintext).unwrap();
        let decrypted = decrypt(&key, &ciphertext).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn encrypt_decrypt_empty() {
        let key: Vec<u8> = vec![];
        let plaintext: Vec<u8> = vec![];

        let ciphertext = encrypt(&key, &plaintext).unwrap();
        assert!(ciphertext.is_empty());

        let decrypted = decrypt(&key, &ciphertext).unwrap();
        assert!(decrypted.is_empty());
    }

    #[test]
    fn xor_self_is_zero() {
        let data = vec![0x12, 0x34, 0x56, 0x78];
        let result = xor(&data, &data).unwrap();
        assert!(result.iter().all(|&b| b == 0));
    }

    #[test]
    fn xor_with_zero_is_identity() {
        let data = vec![0x12, 0x34, 0x56, 0x78];
        let zero = vec![0x00; data.len()];
        let result = xor(&zero, &data).unwrap();
        assert_eq!(result, data);
    }

    #[test]
    fn encrypt_known_vector() {
        // OTP: plaintext XOR key = ciphertext
        // 'A' (0x41) XOR 0xFF = 0xBE
        let key = vec![0xFF];
        let plaintext = vec![0x41];
        let ciphertext = encrypt(&key, &plaintext).unwrap();
        assert_eq!(ciphertext, vec![0xBE]);
    }
}
