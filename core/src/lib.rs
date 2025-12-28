//! ASH Core - Cryptographic core for secure ephemeral messaging.
//!
//! This library provides the cryptographic primitives for ASH:
//! - One-Time Pad generation and consumption
//! - OTP encryption/decryption
//! - Frame encoding/decoding for QR transfer
//! - Mnemonic checksum generation
//!
//! # Security Properties
//!
//! - Information-theoretic security via One-Time Pad
//! - Strict single-use pad consumption
//! - Deterministic behavior for verification
//! - Secure memory wiping
//!
//! # Constraints
//!
//! This library intentionally does NOT:
//! - Access the network
//! - Perform file I/O
//! - Access OS randomness (caller provides entropy)
//! - Contain platform-specific code
//! - Store data persistently
//! - Log sensitive data
//!
//! # Example
//!
//! ```
//! use ash_core::{Pad, PadSize, Frame, otp, frame, mnemonic};
//!
//! // === CEREMONY (Sender) ===
//!
//! // 1. Create pad from entropy (caller gathers entropy)
//! let entropy = vec![0u8; PadSize::Small.bytes()];
//! let pad = Pad::new(&entropy, PadSize::Small).unwrap();
//!
//! // 2. Create frames for QR transfer
//! let frames = frame::create_frames(pad.as_bytes(), 1000).unwrap();
//!
//! // 3. Generate mnemonic for verification
//! let sender_mnemonic = mnemonic::generate_default(pad.as_bytes());
//!
//! // === CEREMONY (Receiver) ===
//!
//! // 4. Decode received frames (from QR scans)
//! let encoded: Vec<Vec<u8>> = frames.iter().map(|f| f.encode()).collect();
//! let decoded: Vec<Frame> = encoded.iter()
//!     .map(|b| Frame::decode(b).unwrap())
//!     .collect();
//!
//! // 5. Reconstruct pad
//! let pad_bytes = frame::reconstruct_pad(&decoded).unwrap();
//! let mut receiver_pad = Pad::from_bytes(pad_bytes.clone());
//!
//! // 6. Verify mnemonic matches
//! let receiver_mnemonic = mnemonic::generate_default(&pad_bytes);
//! assert_eq!(sender_mnemonic, receiver_mnemonic);
//!
//! // === MESSAGING ===
//!
//! // Encrypt a message
//! let plaintext = b"Hello, secure world!";
//! let key = receiver_pad.consume(plaintext.len()).unwrap();
//! let ciphertext = otp::encrypt(&key, plaintext).unwrap();
//!
//! // Decrypt a message (on sender side with their pad)
//! // let decrypted = otp::decrypt(&key, &ciphertext).unwrap();
//! ```

// Note: unsafe is used ONLY in pad.rs for secure memory zeroing via write_volatile.
// This prevents the compiler from optimizing away the zeroing of sensitive data.
#![warn(missing_docs)]
#![warn(clippy::all)]

pub mod crc;
pub mod error;
pub mod frame;
pub mod mnemonic;
pub mod otp;
pub mod pad;
pub mod wordlist;

// Re-export main types at crate root
pub use error::{Error, Result};
pub use frame::Frame;
pub use pad::{Pad, PadSize};

/// Library version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_ceremony_roundtrip() {
        // Simulate complete ceremony and messaging flow

        // === Setup ===
        let entropy: Vec<u8> = (0..=255).cycle().take(PadSize::Small.bytes()).collect();

        // === Sender creates pad ===
        let sender_pad = Pad::new(&entropy, PadSize::Small).unwrap();

        // === Sender creates frames ===
        let frames = frame::create_frames(sender_pad.as_bytes(), 1000).unwrap();
        assert!(!frames.is_empty());

        // === Sender generates mnemonic ===
        let sender_mnemonic = mnemonic::generate_default(sender_pad.as_bytes());
        assert_eq!(sender_mnemonic.len(), 6);

        // === Simulate QR transfer ===
        let encoded: Vec<Vec<u8>> = frames.iter().map(|f| f.encode()).collect();

        // === Receiver decodes frames ===
        let decoded: Vec<Frame> = encoded.iter().map(|b| Frame::decode(b).unwrap()).collect();

        // === Receiver reconstructs pad ===
        let reconstructed = frame::reconstruct_pad(&decoded).unwrap();
        assert_eq!(reconstructed, sender_pad.as_bytes());

        // === Receiver generates mnemonic ===
        let receiver_mnemonic = mnemonic::generate_default(&reconstructed);

        // === Verify mnemonics match ===
        assert_eq!(sender_mnemonic, receiver_mnemonic);

        // === Both parties can now message ===
        let mut sender = Pad::from_bytes(sender_pad.as_bytes().to_vec());
        let mut receiver = Pad::from_bytes(reconstructed);

        // Sender encrypts
        let plaintext = b"Top secret message!";
        let sender_key = sender.consume(plaintext.len()).unwrap();
        let ciphertext = otp::encrypt(&sender_key, plaintext).unwrap();

        // Receiver decrypts
        let receiver_key = receiver.consume(ciphertext.len()).unwrap();
        let decrypted = otp::decrypt(&receiver_key, &ciphertext).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn pad_exhaustion() {
        let entropy = vec![0u8; 100];
        let mut pad = Pad::from_bytes(entropy);

        // Consume all bytes
        pad.consume(100).unwrap();
        assert!(pad.is_exhausted());

        // Try to consume more
        let result = pad.consume(1);
        assert!(result.is_err());
    }

    #[test]
    fn frame_corruption_detected() {
        let frame = Frame::new(0, 1, vec![1, 2, 3, 4, 5]).unwrap();
        let mut encoded = frame.encode();

        // Corrupt a byte
        encoded[5] ^= 0xFF;

        // Should fail CRC check
        let result = Frame::decode(&encoded);
        assert!(matches!(result, Err(Error::CrcMismatch { .. })));
    }

    #[test]
    fn mnemonic_consistency() {
        let pad1 = vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE];
        let pad2 = pad1.clone();

        let mnemonic1 = mnemonic::generate_default(&pad1);
        let mnemonic2 = mnemonic::generate_default(&pad2);

        assert_eq!(mnemonic1, mnemonic2);
    }

    #[test]
    fn otp_symmetric() {
        let key = vec![0xAB, 0xCD, 0xEF];
        let data = vec![0x12, 0x34, 0x56];

        let encrypted = otp::encrypt(&key, &data).unwrap();
        let decrypted = otp::decrypt(&key, &encrypted).unwrap();

        assert_eq!(data, decrypted);
    }
}
