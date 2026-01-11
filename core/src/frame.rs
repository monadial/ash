//! Fountain code based QR frame transfer for ceremony.
//!
//! This module provides rateless erasure coding for reliable pad transfer:
//!
//! - **Sender** generates unlimited encoded blocks using [`FountainFrameGenerator`]
//! - **Receiver** decodes from ANY sufficient subset using [`FountainFrameReceiver`]
//! - No need to wait for specific frames - just keep scanning until complete
//!
//! # Why Fountain Codes?
//!
//! Traditional sequential frames require receiving ALL specific frames in a set.
//! Missing frame 47 of 100? You must wait for the display to cycle back to it.
//!
//! Fountain codes eliminate this problem:
//! - First K blocks are source data (no encoding overhead)
//! - Additional blocks are XOR combinations for redundancy
//! - Receiver can recover from ANY K blocks (with small overhead for out-of-order)
//!
//! # Performance
//!
//! For QR ceremony with ~10 QR codes/second scanning rate:
//! - Encoding: >100,000 blocks/second
//! - Decoding: >50,000 blocks/second
//! - QR scanning is the bottleneck, not fountain codes
//!
//! # Example
//!
//! ```
//! use ash_core::{CeremonyMetadata, frame};
//!
//! // Sender side
//! let metadata = CeremonyMetadata::default();
//! let pad = vec![0u8; 1000];
//! let mut generator = frame::create_fountain_ceremony(
//!     &metadata, &pad, 256, None
//! ).unwrap();
//!
//! // Generate QR frames (can generate unlimited)
//! let frame1 = generator.next_frame();
//! let frame2 = generator.next_frame();
//!
//! // Receiver side
//! let mut receiver = frame::FountainFrameReceiver::new(None);
//!
//! // Add frames as they're scanned
//! receiver.add_frame(&frame1).unwrap();
//! receiver.add_frame(&frame2).unwrap();
//!
//! // Continue until complete
//! while !receiver.is_complete() {
//!     let frame = generator.next_frame();
//!     receiver.add_frame(&frame).unwrap();
//! }
//!
//! // Get the result
//! let result = receiver.get_result().unwrap();
//! assert_eq!(result.pad, pad);
//! ```
//!
//! # Passphrase Encryption
//!
//! Optional passphrase encryption XORs each block's payload with a derived key:
//!
//! ```
//! use ash_core::{CeremonyMetadata, frame};
//!
//! let metadata = CeremonyMetadata::default();
//! let pad = vec![0u8; 1000];
//! let passphrase = "verbal code";
//!
//! // Encrypt on sender side
//! let mut generator = frame::create_fountain_ceremony(
//!     &metadata, &pad, 256, Some(passphrase)
//! ).unwrap();
//!
//! // Decrypt on receiver side (same passphrase required)
//! let mut receiver = frame::FountainFrameReceiver::new(Some(passphrase));
//! ```

use crate::error::{Error, Result};
use crate::fountain::{EncodedBlock, FountainDecoder, FountainEncoder};

/// Default block size for fountain encoding (1500 bytes).
///
/// With 16-byte header, total = 1516 bytes, base64 = ~2021 chars.
/// Fits in Version 23-24 QR codes with L correction.
///
/// Frame counts: ~44 for 64KB, ~175 for 256KB, ~699 for 1MB.
pub const DEFAULT_BLOCK_SIZE: usize = 1500;

/// Create a fountain frame generator for ceremony QR transfer.
///
/// This is the main entry point for creating QR frames. The generator
/// produces unlimited encoded blocks that can be displayed as QR codes.
///
/// # Arguments
///
/// * `metadata` - Ceremony metadata (TTL, relay URL, etc.)
/// * `pad_bytes` - The pad data to transfer
/// * `block_size` - Size of each fountain block (default 256)
/// * `passphrase` - Optional passphrase for encryption
///
/// # Returns
///
/// A [`FountainFrameGenerator`] that produces encoded frames.
///
/// # Errors
///
/// Returns [`Error::EmptyPayload`] if `pad_bytes` is empty.
///
/// # Example
///
/// ```
/// use ash_core::{CeremonyMetadata, frame};
///
/// let metadata = CeremonyMetadata::default();
/// let pad = vec![0u8; 64 * 1024]; // 64KB pad
///
/// let mut generator = frame::create_fountain_ceremony(
///     &metadata, &pad, 256, None
/// ).unwrap();
///
/// println!("Source blocks: {}", generator.source_count());
/// println!("Total size: {} bytes", generator.total_size());
/// ```
pub fn create_fountain_ceremony(
    metadata: &crate::CeremonyMetadata,
    pad_bytes: &[u8],
    block_size: usize,
    passphrase: Option<&str>,
) -> Result<FountainFrameGenerator> {
    FountainFrameGenerator::new(metadata, pad_bytes, block_size, passphrase)
}

/// Fountain frame generator for QR display.
///
/// Generates unlimited encoded blocks from ceremony data. The display
/// cycles through blocks until the receiver signals completion.
///
/// # Block Types
///
/// - **Blocks 0..K**: Source blocks (direct data, no encoding overhead)
/// - **Blocks K+**: XOR blocks (combinations of two source blocks)
///
/// # Usage Pattern
///
/// ```text
/// [Generator] ─── next_frame() ──▶ [QR Display] ─── scan ──▶ [Receiver]
///      │                                                          │
///      └──────────────── repeat until complete ◀──────────────────┘
/// ```
pub struct FountainFrameGenerator {
    encoder: FountainEncoder,
    passphrase: Option<String>,
}

impl FountainFrameGenerator {
    /// Create a new fountain frame generator.
    ///
    /// # Data Format
    ///
    /// The generator prepends metadata to the pad data:
    /// ```text
    /// [metadata_len: 4B][metadata][pad_bytes]
    /// ```
    ///
    /// This allows the receiver to extract both metadata and pad
    /// from the decoded fountain data.
    pub fn new(
        metadata: &crate::CeremonyMetadata,
        pad_bytes: &[u8],
        block_size: usize,
        passphrase: Option<&str>,
    ) -> Result<Self> {
        if pad_bytes.is_empty() {
            return Err(Error::EmptyPayload);
        }

        // Prepend metadata to pad data
        let metadata_bytes = metadata.encode();
        let mut data = Vec::with_capacity(4 + metadata_bytes.len() + pad_bytes.len());

        // Format: [metadata_len: 4B][metadata][pad_bytes]
        data.extend_from_slice(&(metadata_bytes.len() as u32).to_be_bytes());
        data.extend_from_slice(&metadata_bytes);
        data.extend_from_slice(pad_bytes);

        let encoder = FountainEncoder::new(&data, block_size);

        Ok(Self {
            encoder,
            passphrase: passphrase.map(String::from),
        })
    }

    /// Generate the next QR frame bytes.
    ///
    /// Can be called infinitely - generates new blocks each time.
    /// Blocks cycle through source blocks first, then XOR blocks.
    ///
    /// # Returns
    ///
    /// Encoded block bytes ready for QR code display.
    pub fn next_frame(&mut self) -> Vec<u8> {
        let block = self.encoder.next_block();
        self.encode_block(&block)
    }

    /// Generate a specific block by index.
    ///
    /// Useful for regenerating specific blocks or random access.
    /// Same index always produces same block (deterministic).
    ///
    /// # Arguments
    ///
    /// * `index` - Block index (0..K for source, K+ for XOR blocks)
    pub fn generate_frame(&self, index: u32) -> Vec<u8> {
        let block = self.encoder.generate_block(index);
        self.encode_block(&block)
    }

    /// Encode a block for QR transmission.
    fn encode_block(&self, block: &EncodedBlock) -> Vec<u8> {
        let encoded = block.encode();

        // Optionally encrypt payload portion
        if let Some(ref pass) = self.passphrase {
            encrypt_fountain_block(&encoded, pass)
        } else {
            encoded
        }
    }

    /// Number of source blocks (minimum needed for decoding).
    ///
    /// This is K in the fountain code. Receiving any K distinct
    /// source blocks is sufficient to decode (in-order reception).
    /// Out-of-order reception may require K + small overhead.
    pub fn source_count(&self) -> usize {
        self.encoder.source_count()
    }

    /// Block size in bytes.
    pub fn block_size(&self) -> usize {
        self.encoder.block_size()
    }

    /// Total data size being transferred (metadata + pad).
    pub fn total_size(&self) -> usize {
        self.encoder.original_len()
    }
}

/// Encrypt a fountain block's payload (XOR with passphrase-derived key).
///
/// # Block Format
///
/// ```text
/// [index:4][count:2][size:2][len:4][payload:N][crc:4]
///                                  ~~~~~~~~~~
///                                  encrypted portion
/// ```
///
/// Only the payload is encrypted. Header remains readable for
/// decoder initialization and progress tracking.
fn encrypt_fountain_block(encoded: &[u8], passphrase: &str) -> Vec<u8> {
    let mut result = encoded.to_vec();

    let header_len = 12; // index(4) + source_count(2) + block_size(2) + original_len(4)
    let block_size = u16::from_be_bytes([encoded[6], encoded[7]]) as usize;
    let payload_end = header_len + block_size;

    if result.len() < payload_end + 4 {
        return result; // Invalid block, return as-is
    }

    // Use lower 16 bits of index for key derivation
    let index_u16 = u16::from_be_bytes([encoded[2], encoded[3]]);

    // XOR payload with passphrase-derived key
    let key = crate::passphrase::derive_key(passphrase, index_u16, block_size);
    for i in 0..block_size {
        result[header_len + i] ^= key[i];
    }

    // Recompute CRC over just the payload (after XOR)
    // EncodedBlock::decode() expects CRC over data only, not header
    let new_crc = crate::crc::compute(&result[header_len..payload_end]);
    result[payload_end..payload_end + 4].copy_from_slice(&new_crc.to_be_bytes());

    result
}

/// Decrypt a fountain block's payload.
///
/// XOR encryption is symmetric, so decryption is identical to encryption.
fn decrypt_fountain_block(encoded: &[u8], passphrase: &str) -> Vec<u8> {
    encrypt_fountain_block(encoded, passphrase)
}

/// Fountain frame receiver for QR scanning.
///
/// Collects scanned blocks and tracks decoding progress.
/// Can decode from any sufficient subset of blocks.
///
/// # Usage
///
/// ```
/// use ash_core::frame::FountainFrameReceiver;
///
/// let mut receiver = FountainFrameReceiver::new(None);
///
/// // Add frames as they're scanned
/// // receiver.add_frame(&scanned_bytes).unwrap();
///
/// // Check progress
/// println!("Progress: {:.0}%", receiver.progress() * 100.0);
/// println!("Blocks received: {}", receiver.blocks_received());
///
/// // Check completion
/// if receiver.is_complete() {
///     let result = receiver.get_result().unwrap();
///     println!("Pad size: {} bytes", result.pad.len());
/// }
/// ```
pub struct FountainFrameReceiver {
    decoder: Option<FountainDecoder>,
    passphrase: Option<String>,
    blocks_received: usize,
}

impl FountainFrameReceiver {
    /// Create a new receiver.
    ///
    /// # Arguments
    ///
    /// * `passphrase` - Must match sender's passphrase if encryption was used
    pub fn new(passphrase: Option<&str>) -> Self {
        Self {
            decoder: None,
            passphrase: passphrase.map(String::from),
            blocks_received: 0,
        }
    }

    /// Add a scanned QR frame.
    ///
    /// # Returns
    ///
    /// - `Ok(true)` if decoding is now complete
    /// - `Ok(false)` if more blocks are needed
    /// - `Err(_)` if the block is invalid or CRC fails
    ///
    /// # Note
    ///
    /// Duplicate blocks are safely ignored. Out-of-order blocks
    /// are handled automatically by the fountain decoder.
    pub fn add_frame(&mut self, frame_bytes: &[u8]) -> Result<bool> {
        // Decode block (with optional decryption)
        let block = self.decode_block(frame_bytes)?;

        // Initialize decoder on first block
        if self.decoder.is_none() {
            self.decoder = Some(FountainDecoder::from_block(&block));
        }

        let decoder = self.decoder.as_mut().unwrap();
        decoder.add_block(&block);
        self.blocks_received += 1;

        Ok(decoder.is_complete())
    }

    /// Decode a received block.
    fn decode_block(&self, frame_bytes: &[u8]) -> Result<EncodedBlock> {
        let bytes = if let Some(ref pass) = self.passphrase {
            decrypt_fountain_block(frame_bytes, pass)
        } else {
            frame_bytes.to_vec()
        };

        EncodedBlock::decode(&bytes)
    }

    /// Check if decoding is complete.
    ///
    /// When true, [`get_result`](Self::get_result) will return the decoded data.
    pub fn is_complete(&self) -> bool {
        self.decoder.as_ref().is_some_and(|d| d.is_complete())
    }

    /// Get decoding progress (0.0 to 1.0).
    ///
    /// This represents the fraction of source blocks decoded,
    /// not the fraction of blocks received.
    pub fn progress(&self) -> f64 {
        self.decoder.as_ref().map_or(0.0, |d| d.progress())
    }

    /// Number of blocks received (including duplicates).
    pub fn blocks_received(&self) -> usize {
        self.blocks_received
    }

    /// Number of source blocks needed for complete decoding.
    ///
    /// Returns 0 before the first block is received.
    pub fn source_count(&self) -> usize {
        self.decoder.as_ref().map_or(0, |d| d.source_count())
    }

    /// Number of unique blocks received (excluding duplicates).
    ///
    /// This is more useful for progress tracking than [`blocks_received`]
    /// since it excludes frames that were scanned multiple times.
    pub fn unique_blocks_received(&self) -> usize {
        self.decoder
            .as_ref()
            .map_or(0, |d| d.unique_blocks_received())
    }

    /// Get the decoded ceremony result.
    ///
    /// Returns `None` if decoding is not complete.
    ///
    /// # Result Contents
    ///
    /// - `metadata`: Ceremony settings (TTL, relay URL, etc.)
    /// - `pad`: The reconstructed pad bytes
    /// - `blocks_used`: Number of blocks received to complete decoding
    pub fn get_result(&self) -> Option<FountainCeremonyResult> {
        let decoder = self.decoder.as_ref()?;
        let data = decoder.get_data()?;

        // Parse: [metadata_len: 4B][metadata][pad_bytes]
        if data.len() < 4 {
            return None;
        }

        let metadata_len = u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize;
        if data.len() < 4 + metadata_len {
            return None;
        }

        let metadata_bytes = &data[4..4 + metadata_len];
        let pad_bytes = data[4 + metadata_len..].to_vec();

        let metadata = crate::CeremonyMetadata::decode(metadata_bytes).ok()?;

        Some(FountainCeremonyResult {
            metadata,
            pad: pad_bytes,
            blocks_used: self.blocks_received,
        })
    }
}

/// Result of fountain ceremony decoding.
///
/// Contains both the ceremony metadata and the reconstructed pad.
#[derive(Debug, Clone)]
pub struct FountainCeremonyResult {
    /// Ceremony metadata (TTL, relay URL, disappearing messages settings).
    pub metadata: crate::CeremonyMetadata,
    /// Reconstructed pad bytes.
    pub pad: Vec<u8>,
    /// Number of blocks used for decoding.
    ///
    /// This is typically close to `source_count`, but may be
    /// higher if blocks were received out of order.
    pub blocks_used: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fountain_ceremony_roundtrip() {
        let metadata =
            crate::CeremonyMetadata::new(3600, 30, "https://relay.ash.test".to_string()).unwrap();
        let pad: Vec<u8> = (0..=255).cycle().take(5000).collect();

        let mut generator = create_fountain_ceremony(&metadata, &pad, 256, None).unwrap();
        let mut receiver = FountainFrameReceiver::new(None);

        let source_count = generator.source_count();

        let mut blocks = 0;
        while !receiver.is_complete() {
            let frame = generator.next_frame();
            receiver.add_frame(&frame).unwrap();
            blocks += 1;

            assert!(blocks <= source_count * 2, "Too many blocks needed");
        }

        let result = receiver.get_result().unwrap();
        assert_eq!(result.metadata.ttl_seconds, 3600);
        assert_eq!(result.metadata.disappearing_messages_seconds, 30);
        assert_eq!(result.pad, pad);
    }

    #[test]
    fn fountain_ceremony_with_passphrase() {
        let metadata = crate::CeremonyMetadata::default();
        let pad: Vec<u8> = vec![0xAB; 2000];
        let passphrase = "secret phrase";

        // Test single block round-trip
        let mut generator =
            create_fountain_ceremony(&metadata, &pad, 256, Some(passphrase)).unwrap();
        let encrypted_frame = generator.next_frame();

        // Verify decryption works
        let decrypted = decrypt_fountain_block(&encrypted_frame, passphrase);
        let block = EncodedBlock::decode(&decrypted);
        assert!(block.is_ok(), "Decrypted block should be valid");

        // Full roundtrip
        let mut generator =
            create_fountain_ceremony(&metadata, &pad, 256, Some(passphrase)).unwrap();
        let mut receiver = FountainFrameReceiver::new(Some(passphrase));

        while !receiver.is_complete() {
            let frame = generator.next_frame();
            receiver.add_frame(&frame).unwrap();
        }

        let result = receiver.get_result().unwrap();
        assert_eq!(result.pad, pad);
    }

    #[test]
    fn fountain_ceremony_out_of_order() {
        let metadata = crate::CeremonyMetadata::default();
        let pad: Vec<u8> = (0..1000).map(|i| (i % 256) as u8).collect();

        let mut generator = create_fountain_ceremony(&metadata, &pad, 128, None).unwrap();
        let k = generator.source_count();

        // Generate extra blocks
        let frames: Vec<Vec<u8>> = (0..(k + 5)).map(|_| generator.next_frame()).collect();

        // Receive in reverse order
        let mut receiver = FountainFrameReceiver::new(None);
        for frame in frames.iter().rev() {
            if receiver.add_frame(frame).unwrap() {
                break;
            }
        }

        assert!(receiver.is_complete());
        let result = receiver.get_result().unwrap();
        assert_eq!(result.pad, pad);
    }

    #[test]
    fn fountain_ceremony_skip_frames() {
        let metadata = crate::CeremonyMetadata::default();
        let pad: Vec<u8> = vec![0x42; 1500];

        let mut generator = create_fountain_ceremony(&metadata, &pad, 128, None).unwrap();
        let k = generator.source_count();

        // Generate many blocks
        let frames: Vec<Vec<u8>> = (0..(k * 3)).map(|_| generator.next_frame()).collect();

        // Receive every other block
        let mut receiver = FountainFrameReceiver::new(None);
        for (i, frame) in frames.iter().enumerate() {
            if i % 2 == 0 {
                if receiver.add_frame(frame).unwrap() {
                    break;
                }
            }
        }

        // Add remaining if needed
        if !receiver.is_complete() {
            for (i, frame) in frames.iter().enumerate() {
                if i % 2 == 1 {
                    if receiver.add_frame(frame).unwrap() {
                        break;
                    }
                }
            }
        }

        assert!(receiver.is_complete());
        let result = receiver.get_result().unwrap();
        assert_eq!(result.pad, pad);
    }

    #[test]
    fn fountain_ceremony_progress() {
        let metadata = crate::CeremonyMetadata::default();
        let pad: Vec<u8> = vec![0; 2000];

        let mut generator = create_fountain_ceremony(&metadata, &pad, 256, None).unwrap();
        let mut receiver = FountainFrameReceiver::new(None);

        assert_eq!(receiver.progress(), 0.0);
        assert_eq!(receiver.blocks_received(), 0);
        assert!(!receiver.is_complete());

        while !receiver.is_complete() {
            let frame = generator.next_frame();
            receiver.add_frame(&frame).unwrap();
        }

        assert_eq!(receiver.progress(), 1.0);
        assert!(receiver.is_complete());
    }

    #[test]
    fn fountain_all_pad_sizes() {
        let metadata = crate::CeremonyMetadata::default();

        let sizes = [
            ("64KB", 64 * 1024),
            ("256KB", 256 * 1024),
            ("1MB", 1024 * 1024),
        ];

        for (name, size) in sizes {
            let pad = vec![0u8; size];
            let generator = create_fountain_ceremony(&metadata, &pad, 256, None).unwrap();
            println!("{}: {} source blocks", name, generator.source_count());
        }
    }

    #[test]
    fn fountain_empty_pad_error() {
        let metadata = crate::CeremonyMetadata::default();
        let result = create_fountain_ceremony(&metadata, &[], 256, None);
        assert!(matches!(result, Err(Error::EmptyPayload)));
    }

    #[test]
    fn fountain_generator_deterministic() {
        let metadata = crate::CeremonyMetadata::default();
        let pad: Vec<u8> = vec![0x42; 1000];

        let generator = create_fountain_ceremony(&metadata, &pad, 256, None).unwrap();

        // Same index produces same block
        let block1 = generator.generate_frame(5);
        let block2 = generator.generate_frame(5);
        assert_eq!(block1, block2);
    }
}
