//! Authorization token derivation for API authentication.
//!
//! This module derives bearer tokens from pad bytes during ceremony.
//! Both parties compute the same tokens, enabling API authorization
//! without accounts or identity.
//!
//! # Token Types
//!
//! - **Auth Token**: Required for all API operations (messages, polling)
//! - **Burn Token**: Required specifically for burning conversations
//!
//! # Security Properties
//!
//! - Tokens are derived deterministically from pad bytes
//! - Without the pad, tokens cannot be computed or forged
//! - Different tokens for different operations (defense in depth)
//! - Backend stores only hash(token), can verify but not forge
//!
//! # Design
//!
//! Tokens are derived by mixing specific byte ranges from the pad.
//! Since pad bytes are truly random (from entropy), the derived
//! tokens are cryptographically unpredictable to anyone without
//! the pad.

use crate::error::{Error, Result};

/// Size of derived tokens in bytes (256 bits).
pub const TOKEN_SIZE: usize = 32;

/// Byte range for conversation ID derivation.
/// Uses first 32 bytes of pad.
const CONV_ID_RANGE: std::ops::Range<usize> = 0..32;

/// Byte range for auth token derivation.
/// Uses bytes 32-95 (64 bytes, mixed down to 32).
const AUTH_TOKEN_RANGE: std::ops::Range<usize> = 32..96;

/// Byte range for burn token derivation.
/// Uses bytes 96-159 (64 bytes, mixed down to 32).
const BURN_TOKEN_RANGE: std::ops::Range<usize> = 96..160;

/// Minimum pad size to support token derivation.
/// Must have at least 160 bytes for all token ranges.
pub const MIN_PAD_SIZE_FOR_TOKENS: usize = 160;

/// Domain separation constants for token derivation.
/// XORed into the mixing process to ensure different tokens
/// even if the same byte range were used.
const DOMAIN_AUTH: u8 = 0xA1;
const DOMAIN_BURN: u8 = 0xB2;
const DOMAIN_CONV: u8 = 0xC3;

/// Derive conversation ID from pad bytes.
///
/// The conversation ID is used to identify a conversation on the relay.
/// It's derived from the first 32 bytes of the pad.
///
/// # Arguments
///
/// * `pad_bytes` - The full pad bytes
///
/// # Returns
///
/// A 32-byte conversation ID, hex-encoded as a 64-character string.
///
/// # Errors
///
/// Returns error if pad is too small.
pub fn derive_conversation_id(pad_bytes: &[u8]) -> Result<String> {
    if pad_bytes.len() < MIN_PAD_SIZE_FOR_TOKENS {
        return Err(Error::PadTooSmallForTokens {
            size: pad_bytes.len(),
            minimum: MIN_PAD_SIZE_FOR_TOKENS,
        });
    }

    let bytes = mix_bytes(&pad_bytes[CONV_ID_RANGE], DOMAIN_CONV);
    Ok(hex_encode(&bytes))
}

/// Derive auth token from pad bytes.
///
/// The auth token is required for all API operations except burning.
/// It proves the caller participated in the ceremony.
///
/// # Arguments
///
/// * `pad_bytes` - The full pad bytes
///
/// # Returns
///
/// A 32-byte auth token, hex-encoded as a 64-character string.
///
/// # Errors
///
/// Returns error if pad is too small.
pub fn derive_auth_token(pad_bytes: &[u8]) -> Result<String> {
    if pad_bytes.len() < MIN_PAD_SIZE_FOR_TOKENS {
        return Err(Error::PadTooSmallForTokens {
            size: pad_bytes.len(),
            minimum: MIN_PAD_SIZE_FOR_TOKENS,
        });
    }

    let bytes = mix_bytes(&pad_bytes[AUTH_TOKEN_RANGE], DOMAIN_AUTH);
    Ok(hex_encode(&bytes))
}

/// Derive burn token from pad bytes.
///
/// The burn token is required specifically for burning conversations.
/// This provides defense-in-depth: knowing the auth token is not
/// enough to burn a conversation.
///
/// # Arguments
///
/// * `pad_bytes` - The full pad bytes
///
/// # Returns
///
/// A 32-byte burn token, hex-encoded as a 64-character string.
///
/// # Errors
///
/// Returns error if pad is too small.
pub fn derive_burn_token(pad_bytes: &[u8]) -> Result<String> {
    if pad_bytes.len() < MIN_PAD_SIZE_FOR_TOKENS {
        return Err(Error::PadTooSmallForTokens {
            size: pad_bytes.len(),
            minimum: MIN_PAD_SIZE_FOR_TOKENS,
        });
    }

    let bytes = mix_bytes(&pad_bytes[BURN_TOKEN_RANGE], DOMAIN_BURN);
    Ok(hex_encode(&bytes))
}

/// Derive all tokens at once during ceremony.
///
/// Returns (conversation_id, auth_token, burn_token).
///
/// # Arguments
///
/// * `pad_bytes` - The full pad bytes
///
/// # Returns
///
/// Tuple of (conversation_id, auth_token, burn_token) as hex strings.
///
/// # Errors
///
/// Returns error if pad is too small.
pub fn derive_all_tokens(pad_bytes: &[u8]) -> Result<(String, String, String)> {
    Ok((
        derive_conversation_id(pad_bytes)?,
        derive_auth_token(pad_bytes)?,
        derive_burn_token(pad_bytes)?,
    ))
}

/// Mix input bytes with domain separation to produce a fixed-size token.
///
/// Uses a simple but effective mixing function:
/// 1. XOR-fold input bytes into TOKEN_SIZE output
/// 2. Apply domain separation constant
/// 3. Mix adjacent bytes for diffusion
///
/// Since input bytes are truly random (from entropy), the output
/// is cryptographically unpredictable without the input.
fn mix_bytes(input: &[u8], domain: u8) -> [u8; TOKEN_SIZE] {
    let mut output = [0u8; TOKEN_SIZE];

    // XOR-fold input into output
    for (i, &byte) in input.iter().enumerate() {
        output[i % TOKEN_SIZE] ^= byte;
    }

    // Apply domain separation
    for byte in &mut output {
        *byte ^= domain;
    }

    // Multiple mixing rounds for diffusion
    for _ in 0..4 {
        // Mix each byte with its neighbors (circular)
        let prev = output;
        for i in 0..TOKEN_SIZE {
            let left = prev[(i + TOKEN_SIZE - 1) % TOKEN_SIZE];
            let right = prev[(i + 1) % TOKEN_SIZE];
            output[i] = output[i]
                .wrapping_add(left.rotate_left(3))
                .wrapping_add(right.rotate_right(5));
        }
    }

    output
}

/// Encode bytes as lowercase hex string.
fn hex_encode(bytes: &[u8]) -> String {
    use std::fmt::Write;
    bytes.iter().fold(String::with_capacity(bytes.len() * 2), |mut s, b| {
        let _ = write!(s, "{:02x}", b);
        s
    })
}

/// Decode hex string to bytes.
#[allow(dead_code)]
fn hex_decode(s: &str) -> Option<Vec<u8>> {
    if s.len() % 2 != 0 {
        return None;
    }

    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_pad(size: usize) -> Vec<u8> {
        (0..size).map(|i| i as u8).collect()
    }

    #[test]
    fn derive_conversation_id_works() {
        let pad = make_test_pad(1000);
        let id = derive_conversation_id(&pad).unwrap();

        // Should be 64 hex chars (32 bytes)
        assert_eq!(id.len(), 64);
        assert!(id.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn derive_auth_token_works() {
        let pad = make_test_pad(1000);
        let token = derive_auth_token(&pad).unwrap();

        assert_eq!(token.len(), 64);
        assert!(token.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn derive_burn_token_works() {
        let pad = make_test_pad(1000);
        let token = derive_burn_token(&pad).unwrap();

        assert_eq!(token.len(), 64);
        assert!(token.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn tokens_are_different() {
        let pad = make_test_pad(1000);

        let conv_id = derive_conversation_id(&pad).unwrap();
        let auth_token = derive_auth_token(&pad).unwrap();
        let burn_token = derive_burn_token(&pad).unwrap();

        // All three should be different
        assert_ne!(conv_id, auth_token);
        assert_ne!(conv_id, burn_token);
        assert_ne!(auth_token, burn_token);
    }

    #[test]
    fn tokens_are_deterministic() {
        let pad = make_test_pad(1000);

        // Derive twice
        let conv_id_1 = derive_conversation_id(&pad).unwrap();
        let conv_id_2 = derive_conversation_id(&pad).unwrap();

        let auth_1 = derive_auth_token(&pad).unwrap();
        let auth_2 = derive_auth_token(&pad).unwrap();

        let burn_1 = derive_burn_token(&pad).unwrap();
        let burn_2 = derive_burn_token(&pad).unwrap();

        // Same input produces same output
        assert_eq!(conv_id_1, conv_id_2);
        assert_eq!(auth_1, auth_2);
        assert_eq!(burn_1, burn_2);
    }

    #[test]
    fn different_pads_produce_different_tokens() {
        let pad1 = make_test_pad(1000);
        let mut pad2 = make_test_pad(1000);
        pad2[50] ^= 0xFF; // Change one byte

        let token1 = derive_auth_token(&pad1).unwrap();
        let token2 = derive_auth_token(&pad2).unwrap();

        assert_ne!(token1, token2);
    }

    #[test]
    fn pad_too_small_returns_error() {
        let small_pad = vec![0u8; 100]; // Less than MIN_PAD_SIZE_FOR_TOKENS

        let result = derive_auth_token(&small_pad);
        assert!(matches!(result, Err(Error::PadTooSmallForTokens { .. })));
    }

    #[test]
    fn derive_all_tokens_works() {
        let pad = make_test_pad(1000);
        let (conv, auth, burn) = derive_all_tokens(&pad).unwrap();

        assert_eq!(conv.len(), 64);
        assert_eq!(auth.len(), 64);
        assert_eq!(burn.len(), 64);
        assert_ne!(conv, auth);
        assert_ne!(auth, burn);
    }

    #[test]
    fn hex_roundtrip() {
        let bytes = vec![0xDE, 0xAD, 0xBE, 0xEF];
        let hex = hex_encode(&bytes);
        assert_eq!(hex, "deadbeef");

        let decoded = hex_decode(&hex).unwrap();
        assert_eq!(decoded, bytes);
    }

    #[test]
    fn mix_bytes_produces_different_outputs() {
        // Changing input should change output
        let input1: Vec<u8> = (0..64).collect();
        let mut input2 = input1.clone();
        input2[32] ^= 0x01; // Flip one bit

        let output1 = mix_bytes(&input1, DOMAIN_AUTH);
        let output2 = mix_bytes(&input2, DOMAIN_AUTH);

        // Outputs should be different
        assert_ne!(output1, output2, "Different inputs should produce different outputs");

        // At least some bytes should differ
        let diff_count = output1
            .iter()
            .zip(output2.iter())
            .filter(|(a, b)| a != b)
            .count();
        assert!(diff_count > 0, "At least one byte should differ");
    }
}
