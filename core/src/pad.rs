//! One-Time Pad generation and consumption.
//!
//! The Pad struct enforces strict single-use semantics:
//! - Bytes can only be consumed once
//! - Consumption is monotonic (no rewinding)
//! - Memory is securely wiped on drop

use crate::error::{Error, Result};

/// Available pad sizes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PadSize {
    /// 64 KB - approximately 50 short messages, ~1-2 min transfer
    Small,
    /// 256 KB - approximately 200 short messages, ~4-5 min transfer
    Medium,
    /// 1 MB - approximately 800 short messages, ~15-20 min transfer
    Large,
}

impl PadSize {
    /// Get the size in bytes.
    #[inline]
    pub const fn bytes(self) -> usize {
        match self {
            PadSize::Small => 64 * 1024,   // 64 KB
            PadSize::Medium => 256 * 1024, // 256 KB
            PadSize::Large => 1024 * 1024, // 1 MB
        }
    }
}

/// Securely zero memory, preventing compiler optimization.
///
/// Uses volatile writes to ensure the zeroing is not optimized away,
/// followed by a compiler fence to prevent reordering.
#[inline(never)]
fn secure_zero(data: &mut [u8]) {
    // Use volatile writes to prevent optimization
    for byte in data.iter_mut() {
        // SAFETY: We're writing to valid, aligned memory that we own
        unsafe {
            std::ptr::write_volatile(byte, 0);
        }
    }
    // Compiler fence to prevent reordering
    std::sync::atomic::compiler_fence(std::sync::atomic::Ordering::SeqCst);
}

/// A One-Time Pad with single-use consumption semantics.
///
/// # Security
///
/// - Pad bytes are consumed strictly once
/// - Consumption is monotonic (no rewinding or skipping)
/// - Memory is securely zeroed on drop
///
/// # Example
///
/// ```
/// use ash_core::pad::{Pad, PadSize};
///
/// // Create pad from entropy (caller provides entropy)
/// let entropy = vec![0u8; PadSize::Small.bytes()];
/// let mut pad = Pad::new(&entropy, PadSize::Small).unwrap();
///
/// // Consume bytes for encryption
/// let key_material = pad.consume(100).unwrap();
/// assert_eq!(key_material.len(), 100);
/// ```
pub struct Pad {
    /// The pad bytes (securely wiped on drop)
    bytes: Vec<u8>,
    /// Number of bytes consumed so far
    consumed: usize,
}

impl Drop for Pad {
    fn drop(&mut self) {
        secure_zero(&mut self.bytes);
    }
}

impl Pad {
    /// Create a new pad from entropy.
    ///
    /// The entropy must be exactly the size specified by `size`.
    /// The caller is responsible for gathering high-quality entropy
    /// (e.g., from OS randomness + gesture input).
    ///
    /// # Errors
    ///
    /// Returns `Error::InvalidEntropySize` if entropy length doesn't match size.
    pub fn new(entropy: &[u8], size: PadSize) -> Result<Self> {
        let expected = size.bytes();
        if entropy.len() != expected {
            return Err(Error::InvalidEntropySize {
                size: entropy.len(),
                expected,
            });
        }

        Ok(Self {
            bytes: entropy.to_vec(),
            consumed: 0,
        })
    }

    /// Create a pad directly from raw bytes.
    ///
    /// This is primarily used for reconstructing a pad after ceremony transfer.
    /// The bytes are used as-is without size validation.
    pub fn from_bytes(bytes: Vec<u8>) -> Self {
        Self { bytes, consumed: 0 }
    }

    /// Consume the next `n` bytes from the pad.
    ///
    /// # Security
    ///
    /// Each byte can only be consumed once. After consumption,
    /// those bytes cannot be retrieved again.
    ///
    /// # Errors
    ///
    /// Returns `Error::InsufficientPadBytes` if fewer than `n` bytes remain.
    pub fn consume(&mut self, n: usize) -> Result<Vec<u8>> {
        let available = self.remaining();
        if n > available {
            return Err(Error::InsufficientPadBytes {
                needed: n,
                available,
            });
        }

        let start = self.consumed;
        let end = start + n;
        let slice = self.bytes[start..end].to_vec();
        self.consumed = end;

        Ok(slice)
    }

    /// Get the number of bytes remaining in the pad.
    #[inline]
    pub fn remaining(&self) -> usize {
        self.bytes.len().saturating_sub(self.consumed)
    }

    /// Get the total size of the pad.
    #[inline]
    pub fn total_size(&self) -> usize {
        self.bytes.len()
    }

    /// Get the number of bytes consumed so far.
    #[inline]
    pub fn consumed(&self) -> usize {
        self.consumed
    }

    /// Check if the pad is fully exhausted.
    #[inline]
    pub fn is_exhausted(&self) -> bool {
        self.remaining() == 0
    }

    /// Get the raw pad bytes (for ceremony transfer).
    ///
    /// # Security
    ///
    /// This should only be used during ceremony to create frames.
    /// The returned slice includes all bytes, not just unconsumed ones.
    pub fn as_bytes(&self) -> &[u8] {
        &self.bytes
    }
}

impl std::fmt::Debug for Pad {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // Don't expose actual bytes in debug output
        f.debug_struct("Pad")
            .field("total_size", &self.bytes.len())
            .field("consumed", &self.consumed)
            .field("remaining", &self.remaining())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pad_size_bytes() {
        assert_eq!(PadSize::Small.bytes(), 65536);
        assert_eq!(PadSize::Medium.bytes(), 262144);
        assert_eq!(PadSize::Large.bytes(), 1048576);
    }

    #[test]
    fn pad_new_valid() {
        let entropy = vec![0xAB; PadSize::Small.bytes()];
        let pad = Pad::new(&entropy, PadSize::Small).unwrap();
        assert_eq!(pad.total_size(), PadSize::Small.bytes());
        assert_eq!(pad.remaining(), PadSize::Small.bytes());
        assert_eq!(pad.consumed(), 0);
    }

    #[test]
    fn pad_new_wrong_size() {
        let entropy = vec![0xAB; 100]; // Wrong size
        let result = Pad::new(&entropy, PadSize::Small);
        assert!(matches!(result, Err(Error::InvalidEntropySize { .. })));
    }

    #[test]
    fn pad_consume_basic() {
        let entropy = vec![0xAB; PadSize::Small.bytes()];
        let mut pad = Pad::new(&entropy, PadSize::Small).unwrap();

        let slice = pad.consume(100).unwrap();
        assert_eq!(slice.len(), 100);
        assert!(slice.iter().all(|&b| b == 0xAB));
        assert_eq!(pad.consumed(), 100);
        assert_eq!(pad.remaining(), PadSize::Small.bytes() - 100);
    }

    #[test]
    fn pad_consume_all() {
        let size = 256;
        let entropy: Vec<u8> = (0..size).map(|i| i as u8).collect();
        let mut pad = Pad::from_bytes(entropy);

        let slice = pad.consume(size).unwrap();
        assert_eq!(slice.len(), size);
        assert!(pad.is_exhausted());
        assert_eq!(pad.remaining(), 0);
    }

    #[test]
    fn pad_consume_insufficient() {
        let entropy = vec![0u8; 100];
        let mut pad = Pad::from_bytes(entropy);

        pad.consume(50).unwrap();
        let result = pad.consume(100); // Only 50 left
        assert!(matches!(
            result,
            Err(Error::InsufficientPadBytes {
                needed: 100,
                available: 50
            })
        ));
    }

    #[test]
    fn pad_monotonic_consumption() {
        let entropy: Vec<u8> = (0..100).collect();
        let mut pad = Pad::from_bytes(entropy);

        let first = pad.consume(10).unwrap();
        let second = pad.consume(10).unwrap();

        // First slice should be 0..10
        assert_eq!(first, (0..10).collect::<Vec<u8>>());
        // Second slice should be 10..20
        assert_eq!(second, (10..20).collect::<Vec<u8>>());
    }

    #[test]
    fn pad_debug_hides_bytes() {
        let entropy = vec![0xDE, 0xAD, 0xBE, 0xEF];
        let pad = Pad::from_bytes(entropy);
        let debug = format!("{:?}", pad);

        // Debug output should not contain actual byte values
        assert!(!debug.contains("0xde"));
        assert!(!debug.contains("dead"));
        assert!(debug.contains("total_size"));
        assert!(debug.contains("remaining"));
    }

    #[test]
    fn secure_zero_works() {
        let mut data = vec![0xAB; 100];
        secure_zero(&mut data);
        assert!(data.iter().all(|&b| b == 0));
    }
}
