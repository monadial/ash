//! Mnemonic checksum generation for ceremony verification.
//!
//! Generates a human-readable word sequence from pad bytes
//! that both parties can compare verbally.

use crate::wordlist::WORDLIST;

/// Default number of words in the checksum.
pub const DEFAULT_WORD_COUNT: usize = 6;

/// Generate a mnemonic checksum from pad bytes.
///
/// The checksum is deterministic: the same pad always produces
/// the same word sequence.
///
/// # Arguments
///
/// * `pad_bytes` - The full pad to generate checksum from
/// * `word_count` - Number of words to generate (default: 6)
///
/// # Returns
///
/// A vector of words from the wordlist.
///
/// # Algorithm
///
/// Uses the first N bytes of the pad to select words:
/// - Each word requires 9 bits (512 = 2^9)
/// - Bytes are combined to extract 9-bit indices
/// - This provides 54 bits of verification for 6 words
///
/// # Example
///
/// ```
/// use ash_core::mnemonic;
///
/// let pad = vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE];
/// let words = mnemonic::generate(&pad, 6);
/// assert_eq!(words.len(), 6);
/// ```
pub fn generate(pad_bytes: &[u8], word_count: usize) -> Vec<&'static str> {
    if pad_bytes.is_empty() || word_count == 0 {
        return Vec::new();
    }

    // We need approximately 9 bits per word (512 words = 2^9)
    // Use a simple deterministic algorithm:
    // - Combine bytes into a bit stream
    // - Extract 9-bit indices for each word

    let mut words = Vec::with_capacity(word_count);
    let mut bit_accumulator: u32 = 0;
    let mut bits_in_accumulator: u32 = 0;
    let mut byte_index = 0;

    while words.len() < word_count {
        // Add more bits if needed
        while bits_in_accumulator < 9 && byte_index < pad_bytes.len() {
            bit_accumulator = (bit_accumulator << 8) | (pad_bytes[byte_index] as u32);
            bits_in_accumulator += 8;
            byte_index += 1;
        }

        // If we don't have enough bytes, wrap around
        if bits_in_accumulator < 9 {
            // Pad with zeros or cycle - use cycling for more entropy
            let cycle_byte = pad_bytes[byte_index % pad_bytes.len()];
            bit_accumulator = (bit_accumulator << 8) | (cycle_byte as u32);
            bits_in_accumulator += 8;
            byte_index += 1;
        }

        // Extract 9 bits for word index
        bits_in_accumulator -= 9;
        let index = ((bit_accumulator >> bits_in_accumulator) & 0x1FF) as usize;

        // Mask off used bits
        bit_accumulator &= (1 << bits_in_accumulator) - 1;

        words.push(WORDLIST[index]);
    }

    words
}

/// Generate a mnemonic checksum with default word count (6 words).
#[inline]
pub fn generate_default(pad_bytes: &[u8]) -> Vec<&'static str> {
    generate(pad_bytes, DEFAULT_WORD_COUNT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_returns_correct_count() {
        let pad = vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE, 0x12, 0x34];

        let words = generate(&pad, 4);
        assert_eq!(words.len(), 4);

        let words = generate(&pad, 6);
        assert_eq!(words.len(), 6);

        let words = generate(&pad, 8);
        assert_eq!(words.len(), 8);
    }

    #[test]
    fn generate_empty_pad() {
        let words = generate(&[], 6);
        assert!(words.is_empty());
    }

    #[test]
    fn generate_zero_words() {
        let pad = vec![0xDE, 0xAD, 0xBE, 0xEF];
        let words = generate(&pad, 0);
        assert!(words.is_empty());
    }

    #[test]
    fn generate_deterministic() {
        let pad = vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE];

        let words1 = generate(&pad, 6);
        let words2 = generate(&pad, 6);

        assert_eq!(words1, words2);
    }

    #[test]
    fn generate_different_pads_different_words() {
        let pad1 = vec![0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
        let pad2 = vec![0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];

        let words1 = generate(&pad1, 6);
        let words2 = generate(&pad2, 6);

        assert_ne!(words1, words2);
    }

    #[test]
    fn generate_all_words_in_wordlist() {
        let pad: Vec<u8> = (0..255).collect();
        let words = generate(&pad, 20);

        for word in words {
            assert!(WORDLIST.contains(&word), "word '{}' not in wordlist", word);
        }
    }

    #[test]
    fn generate_default_six_words() {
        let pad = vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE];
        let words = generate_default(&pad);
        assert_eq!(words.len(), 6);
    }

    #[test]
    fn generate_with_small_pad() {
        // Even with just 2 bytes, we should be able to generate words
        let pad = vec![0xAB, 0xCD];
        let words = generate(&pad, 4);
        assert_eq!(words.len(), 4);
    }

    #[test]
    fn generate_known_vector() {
        // Create a reproducible test vector
        let pad = vec![0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
        let words = generate(&pad, 6);

        // First word index = 0x000 = 0 -> "able"
        assert_eq!(words[0], "able");
    }

    #[test]
    fn words_are_pronounceable() {
        let pad: Vec<u8> = (0..100).collect();
        let words = generate(&pad, 10);

        for word in words {
            // All words should be 2-7 characters
            assert!(word.len() >= 2 && word.len() <= 7);
            // All words should be lowercase ASCII
            assert!(word.chars().all(|c| c.is_ascii_lowercase()));
        }
    }
}
