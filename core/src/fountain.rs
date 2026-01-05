//! Fountain codes for rateless erasure coding.
//!
//! Enables reliable data transfer over lossy channels:
//! - First K blocks are source data (no encoding overhead)
//! - Additional blocks are XOR combinations for redundancy
//! - Receiver can recover from any K blocks (with some extra for out-of-order)
//!
//! # Example
//!
//! ```
//! use ash_core::fountain::{FountainEncoder, FountainDecoder};
//!
//! let data = b"Hello, fountain codes!";
//! let mut encoder = FountainEncoder::new(data, 8);
//!
//! let mut decoder = FountainDecoder::from_block(&encoder.next_block());
//!
//! while !decoder.is_complete() {
//!     decoder.add_block(&encoder.next_block());
//! }
//!
//! assert_eq!(decoder.get_data().unwrap(), data);
//! ```

use crate::crc;
use crate::error::{Error, Result};

/// Default block size in bytes.
/// 1500 bytes + 16 header = 1516 bytes, base64 = ~2021 chars.
/// Fits in Version 23-24 QR codes with L correction.
/// Frame counts: ~44 for 64KB, ~175 for 256KB, ~699 for 1MB.
pub const DEFAULT_BLOCK_SIZE: usize = 1500;

/// An encoded block for transmission.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EncodedBlock {
    /// Block index (0..K are source blocks, K+ are XOR blocks).
    pub index: u32,
    /// Total number of source blocks.
    pub source_count: u16,
    /// Size of each block in bytes.
    pub block_size: u16,
    /// Original data length.
    pub original_len: u32,
    /// Block data.
    pub data: Vec<u8>,
    /// CRC-32 checksum.
    pub checksum: u32,
}

impl EncodedBlock {
    /// Encode to bytes: `[index:4][count:2][size:2][len:4][data:N][crc:4]`
    pub fn encode(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(16 + self.data.len());
        bytes.extend_from_slice(&self.index.to_be_bytes());
        bytes.extend_from_slice(&self.source_count.to_be_bytes());
        bytes.extend_from_slice(&self.block_size.to_be_bytes());
        bytes.extend_from_slice(&self.original_len.to_be_bytes());
        bytes.extend_from_slice(&self.data);
        bytes.extend_from_slice(&self.checksum.to_be_bytes());
        bytes
    }

    /// Decode from bytes.
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        if bytes.len() < 17 {
            return Err(Error::FountainBlockTooShort {
                size: bytes.len(),
                minimum: 17,
            });
        }

        let index = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        let source_count = u16::from_be_bytes([bytes[4], bytes[5]]);
        let block_size = u16::from_be_bytes([bytes[6], bytes[7]]);
        let original_len = u32::from_be_bytes([bytes[8], bytes[9], bytes[10], bytes[11]]);

        let data_end = 12 + block_size as usize;
        if bytes.len() < data_end + 4 {
            return Err(Error::FountainBlockTooShort {
                size: bytes.len(),
                minimum: data_end + 4,
            });
        }

        let data = bytes[12..data_end].to_vec();
        let checksum = u32::from_be_bytes([
            bytes[data_end],
            bytes[data_end + 1],
            bytes[data_end + 2],
            bytes[data_end + 3],
        ]);

        let computed = crc::compute(&data);
        if computed != checksum {
            return Err(Error::CrcMismatch {
                expected: checksum,
                actual: computed,
            });
        }

        Ok(Self {
            index,
            source_count,
            block_size,
            original_len,
            data,
            checksum,
        })
    }
}

/// Fountain encoder - generates blocks from source data.
pub struct FountainEncoder {
    source_blocks: Vec<Vec<u8>>,
    block_size: usize,
    original_len: usize,
    next_index: u32,
}

impl FountainEncoder {
    /// Create encoder with specified block size.
    pub fn new(data: &[u8], block_size: usize) -> Self {
        assert!(block_size > 0, "block_size must be > 0");

        let original_len = data.len();
        let k = if data.is_empty() {
            1
        } else {
            data.len().div_ceil(block_size)
        };

        // Split into blocks, pad last with zeros
        let mut source_blocks = Vec::with_capacity(k);
        for i in 0..k {
            let start = i * block_size;
            let end = ((i + 1) * block_size).min(data.len());
            let mut block = if start < data.len() {
                data[start..end].to_vec()
            } else {
                Vec::new()
            };
            block.resize(block_size, 0);
            source_blocks.push(block);
        }

        Self {
            source_blocks,
            block_size,
            original_len,
            next_index: 0,
        }
    }

    /// Create encoder with default block size (256 bytes).
    pub fn with_default_block_size(data: &[u8]) -> Self {
        Self::new(data, DEFAULT_BLOCK_SIZE)
    }

    /// Generate next block.
    pub fn next_block(&mut self) -> EncodedBlock {
        let block = self.generate_block(self.next_index);
        self.next_index = self.next_index.wrapping_add(1);
        block
    }

    /// Generate specific block by index.
    pub fn generate_block(&self, index: u32) -> EncodedBlock {
        let k = self.source_blocks.len();
        let idx = index as usize;

        let data = if idx < k {
            // First K blocks: source blocks directly
            self.source_blocks[idx].clone()
        } else {
            // XOR blocks: combine two source blocks using pseudo-random pairs
            let i = idx - k;
            let (a, b) = xor_pair(i, k);
            xor_blocks(&self.source_blocks[a], &self.source_blocks[b])
        };

        let checksum = crc::compute(&data);

        EncodedBlock {
            index,
            source_count: k as u16,
            block_size: self.block_size as u16,
            original_len: self.original_len as u32,
            data,
            checksum,
        }
    }

    /// Number of source blocks.
    pub fn source_count(&self) -> usize {
        self.source_blocks.len()
    }

    /// Block size in bytes.
    pub fn block_size(&self) -> usize {
        self.block_size
    }

    /// Original data length.
    pub fn original_len(&self) -> usize {
        self.original_len
    }
}

/// Fountain decoder - reconstructs data from received blocks.
pub struct FountainDecoder {
    k: usize,
    block_size: usize,
    original_len: usize,
    decoded: Vec<Option<Vec<u8>>>,
    // Store XOR blocks for recovery: (index, data, source_a, source_b)
    xor_blocks: Vec<(u32, Vec<u8>, usize, usize)>,
}

impl FountainDecoder {
    /// Create decoder from first received block.
    pub fn from_block(block: &EncodedBlock) -> Self {
        Self::new(block.source_count, block.block_size, block.original_len as usize)
    }

    /// Create decoder with known parameters.
    pub fn new(source_count: u16, block_size: u16, original_len: usize) -> Self {
        let k = source_count as usize;
        Self {
            k,
            block_size: block_size as usize,
            original_len,
            decoded: vec![None; k],
            xor_blocks: Vec::new(),
        }
    }

    /// Add a received block. Returns true if decoding is complete.
    pub fn add_block(&mut self, block: &EncodedBlock) -> bool {
        if self.is_complete() {
            return true;
        }

        let idx = block.index as usize;

        if idx < self.k {
            // Source block - store directly
            if self.decoded[idx].is_none() {
                self.decoded[idx] = Some(block.data.clone());
                self.try_recover();
            }
        } else {
            // XOR block - compute which sources it combines (must match encoder)
            let i = idx - self.k;
            let (a, b) = xor_pair(i, self.k);

            // Try immediate recovery
            if self.decoded[a].is_some() && self.decoded[b].is_none() {
                let recovered = xor_blocks(self.decoded[a].as_ref().unwrap(), &block.data);
                self.decoded[b] = Some(recovered);
                self.try_recover();
            } else if self.decoded[b].is_some() && self.decoded[a].is_none() {
                let recovered = xor_blocks(self.decoded[b].as_ref().unwrap(), &block.data);
                self.decoded[a] = Some(recovered);
                self.try_recover();
            } else if self.decoded[a].is_none() && self.decoded[b].is_none() {
                // Store for later
                self.xor_blocks.push((block.index, block.data.clone(), a, b));
            }
            // If both decoded, block is redundant
        }

        self.is_complete()
    }

    /// Try to recover more blocks using stored XOR blocks.
    fn try_recover(&mut self) {
        let mut changed = true;
        while changed {
            changed = false;
            self.xor_blocks.retain(|(_idx, data, a, b)| {
                if self.decoded[*a].is_some() && self.decoded[*b].is_none() {
                    self.decoded[*b] = Some(xor_blocks(self.decoded[*a].as_ref().unwrap(), data));
                    changed = true;
                    false // Remove from list
                } else if self.decoded[*b].is_some() && self.decoded[*a].is_none() {
                    self.decoded[*a] = Some(xor_blocks(self.decoded[*b].as_ref().unwrap(), data));
                    changed = true;
                    false
                } else if self.decoded[*a].is_some() && self.decoded[*b].is_some() {
                    false // Both decoded, remove
                } else {
                    true // Keep for later
                }
            });
        }
    }

    /// Check if all source blocks are decoded.
    pub fn is_complete(&self) -> bool {
        self.decoded.iter().all(|b| b.is_some())
    }

    /// Decoding progress (0.0 to 1.0).
    pub fn progress(&self) -> f64 {
        if self.k == 0 {
            return 1.0;
        }
        self.decoded.iter().filter(|b| b.is_some()).count() as f64 / self.k as f64
    }

    /// Number of decoded blocks.
    pub fn decoded_count(&self) -> usize {
        self.decoded.iter().filter(|b| b.is_some()).count()
    }

    /// Total source blocks needed.
    pub fn source_count(&self) -> usize {
        self.k
    }

    /// Get decoded data (None if incomplete).
    pub fn get_data(&self) -> Option<Vec<u8>> {
        if !self.is_complete() {
            return None;
        }

        let mut data = Vec::with_capacity(self.k * self.block_size);
        for block in &self.decoded {
            data.extend_from_slice(block.as_ref()?);
        }
        data.truncate(self.original_len);
        Some(data)
    }
}

/// XOR two blocks together.
fn xor_blocks(a: &[u8], b: &[u8]) -> Vec<u8> {
    a.iter().zip(b.iter()).map(|(x, y)| x ^ y).collect()
}

/// Generate pseudo-random pair indices for XOR block.
/// Uses hash mixing for diverse pair selection (better coverage than sequential).
/// Both encoder and decoder must use this same function.
fn xor_pair(i: usize, k: usize) -> (usize, usize) {
    // Mix the index to get pseudo-random but deterministic pairs
    let mut h = i as u64;
    h = h.wrapping_mul(0x9E3779B97F4A7C15); // Golden ratio hash
    h ^= h >> 30;
    h = h.wrapping_mul(0xBF58476D1CE4E5B9);
    h ^= h >> 27;

    let a = (h as usize) % k;

    // Second index must be different from first
    h = h.wrapping_mul(0x94D049BB133111EB);
    h ^= h >> 31;
    let mut b = (h as usize) % k;
    if b == a {
        b = (b + 1) % k;
    }

    (a, b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encoded_block_roundtrip() {
        let block = EncodedBlock {
            index: 42,
            source_count: 10,
            block_size: 256,
            original_len: 2500,
            data: vec![0xAB; 256],
            checksum: crc::compute(&vec![0xAB; 256]),
        };

        let encoded = block.encode();
        let decoded = EncodedBlock::decode(&encoded).unwrap();
        assert_eq!(block, decoded);
    }

    #[test]
    fn encoded_block_crc_verification() {
        let block = EncodedBlock {
            index: 1,
            source_count: 5,
            block_size: 64,
            original_len: 300,
            data: vec![0x12; 64],
            checksum: crc::compute(&vec![0x12; 64]),
        };

        let mut encoded = block.encode();
        encoded[20] ^= 0xFF; // Corrupt

        assert!(matches!(
            EncodedBlock::decode(&encoded),
            Err(Error::CrcMismatch { .. })
        ));
    }

    #[test]
    fn fountain_small_data() {
        let data = b"Hello, fountain codes!";
        let mut encoder = FountainEncoder::new(data, 8);
        let mut decoder = FountainDecoder::from_block(&encoder.next_block());

        // Reset encoder
        let mut encoder = FountainEncoder::new(data, 8);
        let mut blocks_used = 0;

        while !decoder.is_complete() {
            decoder.add_block(&encoder.next_block());
            blocks_used += 1;
            assert!(blocks_used < 50, "Too many blocks needed");
        }

        assert_eq!(decoder.get_data().unwrap(), data);
        println!("Small: {} blocks for {} source", blocks_used, encoder.source_count());
    }

    #[test]
    fn fountain_medium_data() {
        let data: Vec<u8> = (0..1024).map(|i| (i % 256) as u8).collect();
        let mut encoder = FountainEncoder::new(&data, 256);
        let mut decoder = FountainDecoder::from_block(&encoder.next_block());

        let mut encoder = FountainEncoder::new(&data, 256);
        let mut blocks_used = 0;

        while !decoder.is_complete() {
            decoder.add_block(&encoder.next_block());
            blocks_used += 1;
            assert!(blocks_used < 20, "Too many blocks");
        }

        assert_eq!(decoder.get_data().unwrap(), data);
        println!("Medium: {} blocks for {} source", blocks_used, encoder.source_count());
    }

    #[test]
    fn fountain_large_data() {
        let data: Vec<u8> = (0..65536).map(|i| (i % 256) as u8).collect();
        let mut encoder = FountainEncoder::new(&data, 512);
        let mut decoder = FountainDecoder::from_block(&encoder.next_block());

        let mut encoder = FountainEncoder::new(&data, 512);
        let mut blocks_used = 0;

        while !decoder.is_complete() {
            decoder.add_block(&encoder.next_block());
            blocks_used += 1;
            assert!(blocks_used < 200, "Too many blocks");
        }

        assert_eq!(decoder.get_data().unwrap(), data);
        println!("Large: {} blocks for {} source", blocks_used, encoder.source_count());
    }

    #[test]
    fn fountain_out_of_order() {
        let data = b"Out of order test data here";
        let mut encoder = FountainEncoder::new(data, 8);
        let k = encoder.source_count();

        // Generate extra blocks
        let blocks: Vec<_> = (0..(k + 5)).map(|_| encoder.next_block()).collect();

        let mut decoder = FountainDecoder::new(k as u16, 8, data.len());

        // Add in reverse
        for block in blocks.iter().rev() {
            if decoder.add_block(block) {
                break;
            }
        }

        assert!(decoder.is_complete());
        assert_eq!(decoder.get_data().unwrap(), data);
    }

    #[test]
    fn fountain_skip_blocks() {
        let data = b"Test with some skipped blocks";
        let mut encoder = FountainEncoder::new(data, 4);
        let k = encoder.source_count();

        let blocks: Vec<_> = (0..(k * 3)).map(|_| encoder.next_block()).collect();

        let mut decoder = FountainDecoder::new(k as u16, 4, data.len());

        // Skip every other
        for (i, block) in blocks.iter().enumerate() {
            if i % 2 == 0 {
                if decoder.add_block(block) {
                    break;
                }
            }
        }

        // Add rest if needed
        if !decoder.is_complete() {
            for (i, block) in blocks.iter().enumerate() {
                if i % 2 == 1 {
                    if decoder.add_block(block) {
                        break;
                    }
                }
            }
        }

        assert!(decoder.is_complete());
        assert_eq!(decoder.get_data().unwrap(), data);
    }

    #[test]
    fn fountain_duplicate_blocks() {
        let data = b"Duplicate test";
        let mut encoder = FountainEncoder::new(data, 4);
        let mut decoder = FountainDecoder::from_block(&encoder.next_block());

        let mut encoder = FountainEncoder::new(data, 4);

        while !decoder.is_complete() {
            let block = encoder.next_block();
            decoder.add_block(&block);
            decoder.add_block(&block); // Duplicate
        }

        assert_eq!(decoder.get_data().unwrap(), data);
    }

    #[test]
    fn fountain_empty_data() {
        let data: &[u8] = &[];
        let mut encoder = FountainEncoder::new(data, 8);
        let mut decoder = FountainDecoder::from_block(&encoder.next_block());

        let mut encoder = FountainEncoder::new(data, 8);
        decoder.add_block(&encoder.next_block());

        assert!(decoder.is_complete());
        assert!(decoder.get_data().unwrap().is_empty());
    }

    #[test]
    fn fountain_single_byte() {
        let data = &[0x42u8];
        let mut encoder = FountainEncoder::new(data, 8);
        let mut decoder = FountainDecoder::from_block(&encoder.next_block());

        let mut encoder = FountainEncoder::new(data, 8);
        while !decoder.is_complete() {
            decoder.add_block(&encoder.next_block());
        }

        assert_eq!(decoder.get_data().unwrap(), data);
    }

    #[test]
    fn fountain_first_k_sufficient() {
        let data: Vec<u8> = (0..512).map(|i| (i % 256) as u8).collect();
        let mut encoder = FountainEncoder::new(&data, 64);
        let k = encoder.source_count();

        let mut decoder = FountainDecoder::new(k as u16, 64, data.len());

        // Only first K blocks
        for _ in 0..k {
            decoder.add_block(&encoder.next_block());
        }

        assert!(decoder.is_complete());
        assert_eq!(decoder.get_data().unwrap(), data);
    }

    #[test]
    fn fountain_progress() {
        let data: Vec<u8> = (0..256).map(|i| i as u8).collect();
        let mut encoder = FountainEncoder::new(&data, 64);
        let mut decoder = FountainDecoder::from_block(&encoder.next_block());

        let mut encoder = FountainEncoder::new(&data, 64);
        assert_eq!(decoder.progress(), 0.0);

        while !decoder.is_complete() {
            decoder.add_block(&encoder.next_block());
        }

        assert_eq!(decoder.progress(), 1.0);
    }

    #[test]
    fn fountain_regenerate_block() {
        let data = b"Regenerate test";
        let encoder = FountainEncoder::new(data, 8);

        let b1 = encoder.generate_block(42);
        let b2 = encoder.generate_block(42);
        assert_eq!(b1, b2);
    }

    // ==================== PERFORMANCE TESTS ====================

    #[test]
    fn perf_fountain_64kb() {
        run_perf("64KB", 64 * 1024, 256, 100);
    }

    #[test]
    fn perf_fountain_256kb() {
        run_perf("256KB", 256 * 1024, 256, 50);
    }

    #[test]
    fn perf_fountain_1mb() {
        run_perf("1MB", 1024 * 1024, 512, 20);
    }

    fn run_perf(name: &str, size: usize, block_size: usize, iters: usize) {
        let data: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();

        // Encode
        let start = std::time::Instant::now();
        let mut total_blocks = 0;
        for _ in 0..iters {
            let mut enc = FountainEncoder::new(&data, block_size);
            let k = enc.source_count();
            for _ in 0..(k + k / 5) {
                let _ = enc.next_block();
                total_blocks += 1;
            }
        }
        let enc_time = start.elapsed();
        let enc_rate = total_blocks as f64 / enc_time.as_secs_f64();

        // Decode
        let mut enc = FountainEncoder::new(&data, block_size);
        let k = enc.source_count();
        let blocks: Vec<_> = (0..(k + k / 5)).map(|_| enc.next_block()).collect();

        let start = std::time::Instant::now();
        total_blocks = 0;
        for _ in 0..iters {
            let mut dec = FountainDecoder::new(k as u16, block_size as u16, size);
            for b in &blocks {
                dec.add_block(b);
                total_blocks += 1;
                if dec.is_complete() {
                    break;
                }
            }
        }
        let dec_time = start.elapsed();
        let dec_rate = total_blocks as f64 / dec_time.as_secs_f64();

        println!(
            "\n{}: encode {:.0} blk/s, decode {:.0} blk/s",
            name, enc_rate, dec_rate
        );
    }

    #[test]
    fn perf_out_of_order_overhead() {
        println!("\n=== Out-of-Order Overhead ===");
        println!("{:>8} {:>6} {:>8} {:>8} {:>8}", "Size", "K", "InOrder", "Reverse", "Random");

        for size in [16 * 1024, 64 * 1024, 256 * 1024] {
            let data: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();
            let mut enc = FountainEncoder::new(&data, 256);
            let k = enc.source_count();
            let blocks: Vec<_> = (0..(k * 2)).map(|_| enc.next_block()).collect();

            // In-order
            let mut dec = FountainDecoder::new(k as u16, 256, size);
            let mut in_order = 0;
            for b in &blocks {
                in_order += 1;
                if dec.add_block(b) {
                    break;
                }
            }

            // Reversed
            let mut dec = FountainDecoder::new(k as u16, 256, size);
            let mut reversed = 0;
            for b in blocks.iter().rev() {
                reversed += 1;
                if dec.add_block(b) {
                    break;
                }
            }

            // Random shuffle
            let mut shuffled = blocks.clone();
            let mut s = 12345u64;
            for i in (1..shuffled.len()).rev() {
                s ^= s << 13;
                s ^= s >> 7;
                s ^= s << 17;
                shuffled.swap(i, s as usize % (i + 1));
            }

            let mut dec = FountainDecoder::new(k as u16, 256, size);
            let mut random = 0;
            for b in &shuffled {
                random += 1;
                if dec.add_block(b) {
                    break;
                }
            }

            println!(
                "{:>7}K {:>6} {:>8} {:>8} {:>8}",
                size / 1024, k, in_order, reversed, random
            );
        }
    }
}
