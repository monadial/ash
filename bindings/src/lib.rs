//! UniFFI bindings for ash-core.
//!
//! This crate provides Swift/Kotlin bindings via Mozilla's UniFFI.

use std::sync::Mutex;

// Re-export for UniFFI
uniffi::include_scaffolding!("ash");

// === Error Mapping ===

/// FFI-friendly error type
#[derive(Debug, thiserror::Error)]
pub enum AshError {
    #[error("Insufficient pad bytes")]
    InsufficientPadBytes,
    #[error("Invalid entropy size")]
    InvalidEntropySize,
    #[error("Pad exhausted")]
    PadExhausted,
    #[error("Length mismatch")]
    LengthMismatch,
    #[error("Frame too short")]
    FrameTooShort,
    #[error("CRC mismatch")]
    CrcMismatch,
    #[error("Frame index out of bounds")]
    FrameIndexOutOfBounds,
    #[error("Frame count mismatch")]
    FrameCountMismatch,
    #[error("Missing frames")]
    MissingFrames,
    #[error("Duplicate frame")]
    DuplicateFrame,
    #[error("Empty payload")]
    EmptyPayload,
    #[error("Payload too large")]
    PayloadTooLarge,
    #[error("No frames")]
    NoFrames,
    #[error("Zero total frames")]
    ZeroTotalFrames,
}

impl From<ash_core::Error> for AshError {
    fn from(e: ash_core::Error) -> Self {
        match e {
            ash_core::Error::InsufficientPadBytes { .. } => AshError::InsufficientPadBytes,
            ash_core::Error::InvalidEntropySize { .. } => AshError::InvalidEntropySize,
            ash_core::Error::PadExhausted => AshError::PadExhausted,
            ash_core::Error::LengthMismatch { .. } => AshError::LengthMismatch,
            ash_core::Error::FrameTooShort { .. } => AshError::FrameTooShort,
            ash_core::Error::CrcMismatch { .. } => AshError::CrcMismatch,
            ash_core::Error::FrameIndexOutOfBounds { .. } => AshError::FrameIndexOutOfBounds,
            ash_core::Error::FrameCountMismatch { .. } => AshError::FrameCountMismatch,
            ash_core::Error::MissingFrames { .. } => AshError::MissingFrames,
            ash_core::Error::DuplicateFrame { .. } => AshError::DuplicateFrame,
            ash_core::Error::EmptyPayload => AshError::EmptyPayload,
            ash_core::Error::PayloadTooLarge { .. } => AshError::PayloadTooLarge,
            ash_core::Error::NoFrames => AshError::NoFrames,
            ash_core::Error::ZeroTotalFrames => AshError::ZeroTotalFrames,
        }
    }
}

// === Pad Size Enum ===

/// Pad size options exposed to FFI
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PadSize {
    Small,
    Medium,
    Large,
}

impl From<PadSize> for ash_core::PadSize {
    fn from(size: PadSize) -> Self {
        match size {
            PadSize::Small => ash_core::PadSize::Small,
            PadSize::Medium => ash_core::PadSize::Medium,
            PadSize::Large => ash_core::PadSize::Large,
        }
    }
}

// === Pad Wrapper ===

/// Thread-safe wrapper around ash_core::Pad for FFI
pub struct Pad {
    inner: Mutex<ash_core::Pad>,
}

impl Pad {
    /// Create pad from entropy bytes
    pub fn from_entropy(entropy: Vec<u8>, size: PadSize) -> Result<Self, AshError> {
        let pad = ash_core::Pad::new(&entropy, size.into())?;
        Ok(Self {
            inner: Mutex::new(pad),
        })
    }

    /// Create pad from raw bytes
    pub fn from_bytes(bytes: Vec<u8>) -> Self {
        Self {
            inner: Mutex::new(ash_core::Pad::from_bytes(bytes)),
        }
    }

    /// Consume next n bytes from pad
    pub fn consume(&self, n: u32) -> Result<Vec<u8>, AshError> {
        let mut pad = self.inner.lock().unwrap();
        Ok(pad.consume(n as usize)?)
    }

    /// Get remaining bytes count
    pub fn remaining(&self) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.remaining() as u64
    }

    /// Get total pad size
    pub fn total_size(&self) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.total_size() as u64
    }

    /// Get consumed bytes count
    pub fn consumed(&self) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.consumed() as u64
    }

    /// Check if pad is exhausted
    pub fn is_exhausted(&self) -> bool {
        let pad = self.inner.lock().unwrap();
        pad.is_exhausted()
    }

    /// Get raw bytes for ceremony transfer
    pub fn as_bytes(&self) -> Vec<u8> {
        let pad = self.inner.lock().unwrap();
        pad.as_bytes().to_vec()
    }
}

// === Frame Wrapper ===

/// Wrapper around ash_core::Frame for FFI
pub struct Frame {
    inner: ash_core::Frame,
}

impl Frame {
    /// Create a new frame
    pub fn new(index: u16, total: u16, payload: Vec<u8>) -> Result<Self, AshError> {
        let frame = ash_core::Frame::new(index, total, payload)?;
        Ok(Self { inner: frame })
    }

    /// Decode frame from bytes
    pub fn decode(bytes: Vec<u8>) -> Result<Self, AshError> {
        let frame = ash_core::Frame::decode(&bytes)?;
        Ok(Self { inner: frame })
    }

    /// Encode frame to bytes
    pub fn encode(&self) -> Vec<u8> {
        self.inner.encode()
    }

    /// Get frame index
    pub fn get_index(&self) -> u16 {
        self.inner.index
    }

    /// Get total frame count
    pub fn get_total(&self) -> u16 {
        self.inner.total
    }

    /// Get payload bytes
    pub fn get_payload(&self) -> Vec<u8> {
        self.inner.payload.clone()
    }
}

// === Free Functions ===

/// Create frames from pad bytes for QR transfer
pub fn create_frames(
    pad_bytes: Vec<u8>,
    max_payload: u32,
) -> Result<Vec<std::sync::Arc<Frame>>, AshError> {
    let frames = ash_core::frame::create_frames(&pad_bytes, max_payload as usize)?;
    Ok(frames
        .into_iter()
        .map(|f| std::sync::Arc::new(Frame { inner: f }))
        .collect())
}

/// Reconstruct pad from received frames
pub fn reconstruct_pad(frames: Vec<std::sync::Arc<Frame>>) -> Result<Vec<u8>, AshError> {
    let core_frames: Vec<ash_core::Frame> = frames.iter().map(|f| f.inner.clone()).collect();
    Ok(ash_core::frame::reconstruct_pad(&core_frames)?)
}

/// Encrypt plaintext using OTP
pub fn encrypt(key: Vec<u8>, plaintext: Vec<u8>) -> Result<Vec<u8>, AshError> {
    Ok(ash_core::otp::encrypt(&key, &plaintext)?)
}

/// Decrypt ciphertext using OTP
pub fn decrypt(key: Vec<u8>, ciphertext: Vec<u8>) -> Result<Vec<u8>, AshError> {
    Ok(ash_core::otp::decrypt(&key, &ciphertext)?)
}

/// Generate 6-word mnemonic checksum
pub fn generate_mnemonic(pad_bytes: Vec<u8>) -> Vec<String> {
    ash_core::mnemonic::generate_default(&pad_bytes)
        .into_iter()
        .map(|s| s.to_string())
        .collect()
}

/// Generate mnemonic with custom word count
pub fn generate_mnemonic_with_count(pad_bytes: Vec<u8>, word_count: u32) -> Vec<String> {
    ash_core::mnemonic::generate(&pad_bytes, word_count as usize)
        .into_iter()
        .map(|s| s.to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pad_roundtrip() {
        let entropy = vec![0xAB; 65536]; // Small pad
        let pad = Pad::from_entropy(entropy, PadSize::Small).unwrap();

        assert_eq!(pad.remaining(), 65536);
        assert!(!pad.is_exhausted());

        let consumed = pad.consume(100).unwrap();
        assert_eq!(consumed.len(), 100);
        assert_eq!(pad.remaining(), 65536 - 100);
    }

    #[test]
    fn test_frame_roundtrip() {
        let frame = Frame::new(0, 1, vec![1, 2, 3, 4, 5]).unwrap();
        let encoded = frame.encode();
        let decoded = Frame::decode(encoded).unwrap();

        assert_eq!(decoded.get_index(), 0);
        assert_eq!(decoded.get_total(), 1);
        assert_eq!(decoded.get_payload(), vec![1, 2, 3, 4, 5]);
    }

    #[test]
    fn test_encrypt_decrypt() {
        let key = vec![0xDE, 0xAD, 0xBE, 0xEF];
        let plaintext = vec![0x01, 0x02, 0x03, 0x04];

        let ciphertext = encrypt(key.clone(), plaintext.clone()).unwrap();
        let decrypted = decrypt(key, ciphertext).unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_mnemonic() {
        let pad = vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE];
        let words = generate_mnemonic(pad);
        assert_eq!(words.len(), 6);
    }
}
