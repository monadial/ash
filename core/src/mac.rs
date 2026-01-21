//! 256-bit Wegman-Carter Message Authentication Code.
//!
//! This module implements information-theoretically secure message authentication
//! using the Wegman-Carter construction with polynomial hashing.
//!
//! # Construction
//!
//! The 256-bit tag is computed as two independent 128-bit Wegman-Carter MACs:
//!
//! ```text
//! Tag = Tag_high || Tag_low
//!
//! Tag_high = PolyHash(data, r₁) ⊕ s₁
//! Tag_low  = PolyHash(data, r₂) ⊕ s₂
//! ```
//!
//! Where:
//! - `r₁, r₂` are 128-bit polynomial hash keys
//! - `s₁, s₂` are 128-bit one-time masks
//! - All four values come from the one-time pad (64 bytes total)
//!
//! # Security Properties
//!
//! - **Information-theoretic security**: Unbreakable regardless of computational power
//! - **256-bit security level**: Forgery probability ≤ 2⁻²⁵⁶
//! - **One-time keys**: Each (r₁, r₂, s₁, s₂) tuple must be used exactly once
//! - **Constant-time verification**: No timing side channels
//!
//! # Pad Consumption
//!
//! Each authenticated message consumes 64 bytes from the pad for authentication:
//! - r₁: 16 bytes (hash key 1)
//! - r₂: 16 bytes (hash key 2)
//! - s₁: 16 bytes (mask 1)
//! - s₂: 16 bytes (mask 2)
//!
//! Plus the message length for encryption.
//!
//! # Example
//!
//! ```
//! use ash_core::mac::{AuthKey, compute_tag, verify_tag, AUTH_KEY_SIZE, TAG_SIZE};
//!
//! // In practice, these 64 bytes come from the one-time pad
//! let auth_key_bytes = [0x42u8; AUTH_KEY_SIZE];
//! let auth_key = AuthKey::from_bytes(&auth_key_bytes);
//!
//! let header = [0x02, 0x01, 0x00, 0x10]; // Frame header
//! let ciphertext = b"encrypted data here";
//!
//! // Compute tag
//! let tag = compute_tag(&auth_key, &header, ciphertext);
//! assert_eq!(tag.len(), TAG_SIZE);
//!
//! // Verify tag (constant-time)
//! assert!(verify_tag(&auth_key, &header, ciphertext, &tag));
//! ```

use crate::gf128::{constant_time_eq_32, xor_bytes_16};
use crate::poly_hash::poly_hash_segments;

/// Size of authentication tag in bytes (256 bits).
pub const TAG_SIZE: usize = 32;

/// Size of authentication key material in bytes.
///
/// Layout: `[r₁: 16][r₂: 16][s₁: 16][s₂: 16]`
pub const AUTH_KEY_SIZE: usize = 64;

/// Authentication key for Wegman-Carter MAC.
///
/// Contains two hash keys and two one-time masks for 256-bit security.
/// Each instance must be used for exactly one message.
#[derive(Clone)]
pub struct AuthKey {
    /// First polynomial hash key
    r1: [u8; 16],
    /// Second polynomial hash key
    r2: [u8; 16],
    /// First one-time mask
    s1: [u8; 16],
    /// Second one-time mask
    s2: [u8; 16],
}

impl AuthKey {
    /// Create an authentication key from 64 bytes of pad material.
    ///
    /// # Layout
    ///
    /// ```text
    /// bytes[0..16]   → r₁ (first hash key)
    /// bytes[16..32]  → r₂ (second hash key)
    /// bytes[32..48]  → s₁ (first mask)
    /// bytes[48..64]  → s₂ (second mask)
    /// ```
    ///
    /// # Arguments
    ///
    /// * `bytes` - 64 bytes from the one-time pad
    pub fn from_bytes(bytes: &[u8; AUTH_KEY_SIZE]) -> Self {
        let mut r1 = [0u8; 16];
        let mut r2 = [0u8; 16];
        let mut s1 = [0u8; 16];
        let mut s2 = [0u8; 16];

        r1.copy_from_slice(&bytes[0..16]);
        r2.copy_from_slice(&bytes[16..32]);
        s1.copy_from_slice(&bytes[32..48]);
        s2.copy_from_slice(&bytes[48..64]);

        Self { r1, r2, s1, s2 }
    }

    /// Create an authentication key from a byte slice.
    ///
    /// # Panics
    ///
    /// Panics if the slice length is not exactly 64 bytes.
    pub fn from_slice(bytes: &[u8]) -> Self {
        assert_eq!(
            bytes.len(),
            AUTH_KEY_SIZE,
            "AuthKey requires exactly {} bytes",
            AUTH_KEY_SIZE
        );
        let arr: [u8; AUTH_KEY_SIZE] = bytes.try_into().unwrap();
        Self::from_bytes(&arr)
    }
}

/// Compute a 256-bit authentication tag.
///
/// The tag authenticates both the header and ciphertext, protecting against
/// any modification to either component.
///
/// # Arguments
///
/// * `key` - Authentication key (64 bytes from pad, used once)
/// * `header` - Frame header bytes to authenticate
/// * `ciphertext` - Encrypted payload to authenticate
///
/// # Returns
///
/// 32-byte (256-bit) authentication tag.
///
/// # Example
///
/// ```
/// use ash_core::mac::{AuthKey, compute_tag, AUTH_KEY_SIZE};
///
/// let key = AuthKey::from_bytes(&[0u8; AUTH_KEY_SIZE]);
/// let tag = compute_tag(&key, &[0x02, 0x01], b"ciphertext");
/// assert_eq!(tag.len(), 32);
/// ```
pub fn compute_tag(key: &AuthKey, header: &[u8], ciphertext: &[u8]) -> [u8; TAG_SIZE] {
    // Compute first 128-bit hash: H₁ = PolyHash(header || ciphertext, r₁)
    let h1 = poly_hash_segments(&key.r1, &[header, ciphertext]);

    // Compute second 128-bit hash: H₂ = PolyHash(header || ciphertext, r₂)
    let h2 = poly_hash_segments(&key.r2, &[header, ciphertext]);

    // Mask with one-time pads
    let tag_high = xor_bytes_16(&h1, &key.s1);
    let tag_low = xor_bytes_16(&h2, &key.s2);

    // Concatenate to form 256-bit tag
    let mut tag = [0u8; TAG_SIZE];
    tag[0..16].copy_from_slice(&tag_high);
    tag[16..32].copy_from_slice(&tag_low);

    tag
}

/// Verify an authentication tag in constant time.
///
/// Returns `true` if and only if the tag is valid for the given header and ciphertext.
/// The verification runs in constant time to prevent timing attacks.
///
/// # Arguments
///
/// * `key` - Authentication key (must be the same key used to compute the tag)
/// * `header` - Frame header bytes
/// * `ciphertext` - Encrypted payload
/// * `tag` - 32-byte tag to verify
///
/// # Returns
///
/// `true` if the tag is valid, `false` otherwise.
///
/// # Security
///
/// - Runs in constant time regardless of where (or if) the tag differs
/// - Does not reveal any information about the expected tag on failure
///
/// # Example
///
/// ```
/// use ash_core::mac::{AuthKey, compute_tag, verify_tag, AUTH_KEY_SIZE};
///
/// let key = AuthKey::from_bytes(&[0x42u8; AUTH_KEY_SIZE]);
/// let header = &[0x02, 0x01, 0x00, 0x10];
/// let ciphertext = b"secret message";
///
/// let tag = compute_tag(&key, header, ciphertext);
/// assert!(verify_tag(&key, header, ciphertext, &tag));
///
/// // Tampering with ciphertext fails verification
/// let tampered = b"tampered message";
/// assert!(!verify_tag(&key, header, tampered, &tag));
/// ```
pub fn verify_tag(key: &AuthKey, header: &[u8], ciphertext: &[u8], tag: &[u8; TAG_SIZE]) -> bool {
    let expected = compute_tag(key, header, ciphertext);
    constant_time_eq_32(&expected, tag)
}

/// Verify a tag given as a slice (convenience function).
///
/// Returns `false` if the slice is not exactly 32 bytes.
pub fn verify_tag_slice(key: &AuthKey, header: &[u8], ciphertext: &[u8], tag: &[u8]) -> bool {
    if tag.len() != TAG_SIZE {
        return false;
    }
    let tag_arr: [u8; TAG_SIZE] = tag.try_into().unwrap();
    verify_tag(key, header, ciphertext, &tag_arr)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_key(seed: u8) -> AuthKey {
        let mut bytes = [0u8; AUTH_KEY_SIZE];
        for (i, b) in bytes.iter_mut().enumerate() {
            *b = seed.wrapping_add(i as u8);
        }
        AuthKey::from_bytes(&bytes)
    }

    #[test]
    fn tag_size_is_256_bits() {
        let key = make_test_key(0x42);
        let tag = compute_tag(&key, &[0x02], b"test");
        assert_eq!(tag.len(), 32);
    }

    #[test]
    fn compute_verify_roundtrip() {
        let key = make_test_key(0x11);
        let header = [0x02, 0x01, 0x00, 0x10];
        let ciphertext = b"This is the encrypted message content";

        let tag = compute_tag(&key, &header, ciphertext);
        assert!(verify_tag(&key, &header, ciphertext, &tag));
    }

    #[test]
    fn different_keys_different_tags() {
        let key1 = make_test_key(0x11);
        let key2 = make_test_key(0x22);
        let header = [0x02, 0x01];
        let ciphertext = b"same message";

        let tag1 = compute_tag(&key1, &header, ciphertext);
        let tag2 = compute_tag(&key2, &header, ciphertext);

        assert_ne!(tag1, tag2);
    }

    #[test]
    fn different_headers_different_tags() {
        let key = make_test_key(0x33);
        let header1 = [0x02, 0x01, 0x00, 0x10];
        let header2 = [0x02, 0x02, 0x00, 0x10]; // Different type
        let ciphertext = b"same ciphertext";

        let tag1 = compute_tag(&key, &header1, ciphertext);
        let tag2 = compute_tag(&key, &header2, ciphertext);

        assert_ne!(tag1, tag2);
    }

    #[test]
    fn different_ciphertext_different_tags() {
        let key = make_test_key(0x44);
        let header = [0x02, 0x01];
        let ciphertext1 = b"message one";
        let ciphertext2 = b"message two";

        let tag1 = compute_tag(&key, &header, ciphertext1);
        let tag2 = compute_tag(&key, &header, ciphertext2);

        assert_ne!(tag1, tag2);
    }

    #[test]
    fn tampered_ciphertext_fails_verify() {
        let key = make_test_key(0x55);
        let header = [0x02, 0x01, 0x00, 0x10];
        let ciphertext = b"original message";

        let tag = compute_tag(&key, &header, ciphertext);

        // Tamper with ciphertext
        let tampered = b"tampered message";
        assert!(!verify_tag(&key, &header, tampered, &tag));
    }

    #[test]
    fn tampered_header_fails_verify() {
        let key = make_test_key(0x66);
        let header = [0x02, 0x01, 0x00, 0x10];
        let ciphertext = b"message content";

        let tag = compute_tag(&key, &header, ciphertext);

        // Tamper with header
        let tampered_header = [0x02, 0x02, 0x00, 0x10];
        assert!(!verify_tag(&key, &tampered_header, ciphertext, &tag));
    }

    #[test]
    fn tampered_tag_fails_verify() {
        let key = make_test_key(0x77);
        let header = [0x02, 0x01];
        let ciphertext = b"message";

        let mut tag = compute_tag(&key, &header, ciphertext);

        // Tamper with tag (flip one bit)
        tag[0] ^= 0x01;
        assert!(!verify_tag(&key, &header, ciphertext, &tag));

        // Tamper in the middle
        let mut tag2 = compute_tag(&key, &header, ciphertext);
        tag2[16] ^= 0x80;
        assert!(!verify_tag(&key, &header, ciphertext, &tag2));

        // Tamper at the end
        let mut tag3 = compute_tag(&key, &header, ciphertext);
        tag3[31] ^= 0x01;
        assert!(!verify_tag(&key, &header, ciphertext, &tag3));
    }

    #[test]
    fn empty_ciphertext() {
        let key = make_test_key(0x88);
        let header = [0x02, 0x01, 0x00, 0x00]; // Length = 0

        let tag = compute_tag(&key, &header, &[]);
        assert!(verify_tag(&key, &header, &[], &tag));
    }

    #[test]
    fn empty_header() {
        let key = make_test_key(0x99);
        let ciphertext = b"just ciphertext, no header";

        let tag = compute_tag(&key, &[], ciphertext);
        assert!(verify_tag(&key, &[], ciphertext, &tag));
    }

    #[test]
    fn deterministic() {
        let key = make_test_key(0xAA);
        let header = [0x02, 0x01, 0x00, 0x20];
        let ciphertext = b"test message for determinism check";

        let tag1 = compute_tag(&key, &header, ciphertext);
        let tag2 = compute_tag(&key, &header, ciphertext);

        assert_eq!(tag1, tag2);
    }

    #[test]
    fn large_ciphertext() {
        let key = make_test_key(0xBB);
        let header = [0x02, 0x01];
        let ciphertext = vec![0x42u8; 10000]; // 10KB

        let tag = compute_tag(&key, &header, &ciphertext);
        assert!(verify_tag(&key, &header, &ciphertext, &tag));
    }

    #[test]
    fn auth_key_from_slice() {
        let bytes = [0x12u8; AUTH_KEY_SIZE];
        let key = AuthKey::from_slice(&bytes);

        let tag = compute_tag(&key, &[0x02], b"test");
        assert_eq!(tag.len(), TAG_SIZE);
    }

    #[test]
    #[should_panic(expected = "AuthKey requires exactly 64 bytes")]
    fn auth_key_from_slice_wrong_size() {
        let bytes = [0x12u8; 32]; // Wrong size
        let _key = AuthKey::from_slice(&bytes);
    }

    #[test]
    fn verify_tag_slice_correct_size() {
        let key = make_test_key(0xCC);
        let header = [0x02, 0x01];
        let ciphertext = b"test";

        let tag = compute_tag(&key, &header, ciphertext);
        assert!(verify_tag_slice(&key, &header, ciphertext, &tag));
    }

    #[test]
    fn verify_tag_slice_wrong_size() {
        let key = make_test_key(0xDD);
        let header = [0x02, 0x01];
        let ciphertext = b"test";

        // Wrong tag size should fail
        let short_tag = [0u8; 16];
        assert!(!verify_tag_slice(&key, &header, ciphertext, &short_tag));

        let long_tag = [0u8; 64];
        assert!(!verify_tag_slice(&key, &header, ciphertext, &long_tag));
    }

    #[test]
    fn all_bits_matter_in_tag() {
        let key = make_test_key(0xEE);
        let header = [0x02, 0x01, 0x00, 0x10];
        let ciphertext = b"test message";

        let correct_tag = compute_tag(&key, &header, ciphertext);

        // Flip each bit position and verify it fails
        for byte_idx in 0..TAG_SIZE {
            for bit in 0..8 {
                let mut bad_tag = correct_tag;
                bad_tag[byte_idx] ^= 1 << bit;
                assert!(
                    !verify_tag(&key, &header, ciphertext, &bad_tag),
                    "Flipping bit {} of byte {} should fail verification",
                    bit,
                    byte_idx
                );
            }
        }
    }

    #[test]
    fn single_bit_change_in_ciphertext_fails() {
        let key = make_test_key(0xFF);
        let header = [0x02, 0x01];
        let ciphertext = b"test message content";

        let tag = compute_tag(&key, &header, ciphertext);

        // Flip single bits in ciphertext
        for byte_idx in 0..ciphertext.len() {
            for bit in 0..8 {
                let mut tampered = ciphertext.to_vec();
                tampered[byte_idx] ^= 1 << bit;
                assert!(
                    !verify_tag(&key, &header, &tampered, &tag),
                    "Flipping bit {} of byte {} in ciphertext should fail",
                    bit,
                    byte_idx
                );
            }
        }
    }

    #[test]
    fn truncated_ciphertext_fails() {
        let key = make_test_key(0x01);
        let header = [0x02, 0x01, 0x00, 0x10];
        let ciphertext = b"original message";

        let tag = compute_tag(&key, &header, ciphertext);

        // Truncate ciphertext
        let truncated = &ciphertext[..ciphertext.len() - 1];
        assert!(!verify_tag(&key, &header, truncated, &tag));
    }

    #[test]
    fn extended_ciphertext_fails() {
        let key = make_test_key(0x02);
        let header = [0x02, 0x01, 0x00, 0x10];
        let ciphertext = b"original message";

        let tag = compute_tag(&key, &header, ciphertext);

        // Extend ciphertext
        let mut extended = ciphertext.to_vec();
        extended.push(0x00);
        assert!(!verify_tag(&key, &header, &extended, &tag));
    }

    // Test that the two halves of the tag are independent
    #[test]
    fn tag_halves_are_independent() {
        let key = make_test_key(0x03);
        let header = [0x02, 0x01];
        let ciphertext = b"test";

        let tag = compute_tag(&key, &header, ciphertext);

        // The two 128-bit halves should generally be different
        // (statistically certain for non-degenerate inputs)
        let high: [u8; 16] = tag[0..16].try_into().unwrap();
        let low: [u8; 16] = tag[16..32].try_into().unwrap();
        assert_ne!(high, low);
    }
}
