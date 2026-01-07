//! ASH Core - Cryptographic core for secure ephemeral messaging.
//!
//! This library provides the cryptographic primitives for ASH:
//! - One-Time Pad generation and consumption
//! - OTP encryption/decryption
//! - Fountain code encoding for reliable QR transfer
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
//! # Example: Complete Ceremony Flow
//!
//! ```
//! use ash_core::{Pad, PadSize, Role, CeremonyMetadata, frame, otp, mnemonic};
//!
//! // === CEREMONY (Initiator) ===
//!
//! // 1. Create pad from entropy (caller gathers entropy)
//! let entropy = vec![0u8; PadSize::Small.bytes()];
//! let initiator_pad = Pad::new(&entropy, PadSize::Small).unwrap();
//!
//! // 2. Create fountain frames for QR transfer
//! let metadata = CeremonyMetadata::default();
//! let mut generator = frame::create_fountain_ceremony(
//!     &metadata,
//!     initiator_pad.as_bytes(),
//!     256,
//!     None, // Optional passphrase
//! ).unwrap();
//!
//! // 3. Generate mnemonic for verification
//! let initiator_mnemonic = mnemonic::generate_default(initiator_pad.as_bytes());
//!
//! // === CEREMONY (Responder) ===
//!
//! // 4. Receive fountain frames (from QR scans)
//! let mut receiver = frame::FountainFrameReceiver::new(None);
//! while !receiver.is_complete() {
//!     let frame = generator.next_frame();
//!     receiver.add_frame(&frame).unwrap();
//! }
//!
//! // 5. Get decoded pad
//! let result = receiver.get_result().unwrap();
//! let mut responder_pad = Pad::from_bytes(result.pad.clone());
//!
//! // 6. Verify mnemonic matches
//! let responder_mnemonic = mnemonic::generate_default(&result.pad);
//! assert_eq!(initiator_mnemonic, responder_mnemonic);
//!
//! // === MESSAGING ===
//!
//! // Responder sends a message (consumes from end)
//! let plaintext = b"Hello, secure world!";
//! let key = responder_pad.consume(plaintext.len(), Role::Responder).unwrap();
//! let ciphertext = otp::encrypt(&key, plaintext).unwrap();
//!
//! // Initiator decrypts (using Responder role to get same bytes)
//! let mut initiator = Pad::from_bytes(initiator_pad.as_bytes().to_vec());
//! let decrypt_key = initiator.consume(ciphertext.len(), Role::Responder).unwrap();
//! let decrypted = otp::decrypt(&decrypt_key, &ciphertext).unwrap();
//! assert_eq!(decrypted, plaintext);
//! ```

// Note: unsafe is used ONLY in pad.rs for secure memory zeroing via write_volatile.
// This prevents the compiler from optimizing away the zeroing of sensitive data.
#![warn(missing_docs)]
#![warn(clippy::all)]

pub mod auth;
pub mod ceremony;
pub mod crc;
pub mod error;
pub mod fountain;
pub mod frame;
pub mod mnemonic;
pub mod otp;
pub mod pad;
pub mod passphrase;
pub mod wordlist;

// Re-export main types at crate root
pub use ceremony::{CeremonyMetadata, NotificationFlags, DEFAULT_TTL_SECONDS, METADATA_VERSION};
pub use error::{Error, Result};
pub use fountain::{EncodedBlock, FountainDecoder, FountainEncoder};
pub use frame::{
    create_fountain_ceremony, FountainCeremonyResult, FountainFrameGenerator,
    FountainFrameReceiver, DEFAULT_BLOCK_SIZE,
};
pub use pad::{Pad, PadSize, Role};

/// Library version.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn full_ceremony_roundtrip() {
        // Simulate complete ceremony and messaging flow using fountain codes

        // === Setup ===
        let entropy: Vec<u8> = (0..=255).cycle().take(PadSize::Small.bytes()).collect();

        // === Initiator creates pad ===
        let initiator_pad = Pad::new(&entropy, PadSize::Small).unwrap();

        // === Initiator creates fountain frames ===
        let metadata = CeremonyMetadata::default();
        let mut generator =
            frame::create_fountain_ceremony(&metadata, initiator_pad.as_bytes(), 256, None)
                .unwrap();

        // === Initiator generates mnemonic ===
        let initiator_mnemonic = mnemonic::generate_default(initiator_pad.as_bytes());
        assert_eq!(initiator_mnemonic.len(), 6);

        // === Simulate QR transfer with fountain codes ===
        let mut receiver = FountainFrameReceiver::new(None);
        while !receiver.is_complete() {
            let frame = generator.next_frame();
            receiver.add_frame(&frame).unwrap();
        }

        // === Responder gets decoded result ===
        let result = receiver.get_result().unwrap();
        let reconstructed = result.pad;
        assert_eq!(reconstructed, initiator_pad.as_bytes());

        // === Responder generates mnemonic ===
        let responder_mnemonic = mnemonic::generate_default(&reconstructed);

        // === Verify mnemonics match ===
        assert_eq!(initiator_mnemonic, responder_mnemonic);

        // === Both parties can now message ===
        // Both have the SAME pad bytes, but consume from opposite ends
        let mut initiator = Pad::from_bytes(initiator_pad.as_bytes().to_vec());
        let mut responder = Pad::from_bytes(reconstructed);

        // Initiator sends a message (consumes from start)
        let plaintext1 = b"Hello from initiator!";
        let init_key = initiator
            .consume(plaintext1.len(), Role::Initiator)
            .unwrap();
        let ciphertext1 = otp::encrypt(&init_key, plaintext1).unwrap();

        // Responder decrypts (using Initiator role because that's where the bytes came from)
        let resp_decrypt_key = responder
            .consume(ciphertext1.len(), Role::Initiator)
            .unwrap();
        let decrypted1 = otp::decrypt(&resp_decrypt_key, &ciphertext1).unwrap();
        assert_eq!(decrypted1, plaintext1);

        // Responder sends a message (consumes from end)
        let plaintext2 = b"Hello from responder!";
        let resp_key = responder
            .consume(plaintext2.len(), Role::Responder)
            .unwrap();
        let ciphertext2 = otp::encrypt(&resp_key, plaintext2).unwrap();

        // Initiator decrypts (using Responder role because that's where the bytes came from)
        let init_decrypt_key = initiator
            .consume(ciphertext2.len(), Role::Responder)
            .unwrap();
        let decrypted2 = otp::decrypt(&init_decrypt_key, &ciphertext2).unwrap();
        assert_eq!(decrypted2, plaintext2);
    }

    #[test]
    fn pad_exhaustion() {
        let entropy = vec![0u8; 100];
        let mut pad = Pad::from_bytes(entropy);

        // Consume 50 from initiator side, 50 from responder side
        pad.consume(50, Role::Initiator).unwrap();
        pad.consume(50, Role::Responder).unwrap();
        assert!(pad.is_exhausted());

        // Try to consume more
        let result = pad.consume(1, Role::Initiator);
        assert!(result.is_err());
    }

    #[test]
    fn fountain_corruption_detected() {
        let metadata = CeremonyMetadata::default();
        let pad = vec![0u8; 1000];
        let mut generator = frame::create_fountain_ceremony(&metadata, &pad, 256, None).unwrap();

        let mut frame = generator.next_frame();

        // Corrupt a byte in the payload
        frame[15] ^= 0xFF;

        // Should fail CRC check
        let mut receiver = FountainFrameReceiver::new(None);
        let result = receiver.add_frame(&frame);
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
