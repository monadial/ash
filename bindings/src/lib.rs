//! UniFFI bindings for ash-core.
//!
//! This crate provides Swift bindings via Mozilla's UniFFI.
//! Uses fountain codes for reliable QR ceremony transfer.

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
    #[error("Length mismatch")]
    LengthMismatch,
    #[error("CRC mismatch")]
    CrcMismatch,
    #[error("Empty payload")]
    EmptyPayload,
    #[error("Fountain block too short")]
    FountainBlockTooShort,
    #[error("Metadata too short")]
    MetadataTooShort,
    #[error("Unsupported metadata version")]
    UnsupportedMetadataVersion,
    #[error("Metadata URL too long")]
    MetadataUrlTooLong,
    #[error("Invalid metadata URL")]
    InvalidMetadataUrl,
    #[error("Pad too small for tokens")]
    PadTooSmallForTokens,
    #[error("Pad size too small")]
    PadSizeTooSmall,
    #[error("Pad size too large")]
    PadSizeTooBig,
}

impl From<ash_core::Error> for AshError {
    fn from(e: ash_core::Error) -> Self {
        match e {
            ash_core::Error::InsufficientPadBytes { .. } => AshError::InsufficientPadBytes,
            ash_core::Error::InvalidEntropySize { .. } => AshError::InvalidEntropySize,
            ash_core::Error::LengthMismatch { .. } => AshError::LengthMismatch,
            ash_core::Error::CrcMismatch { .. } => AshError::CrcMismatch,
            ash_core::Error::EmptyPayload => AshError::EmptyPayload,
            ash_core::Error::FountainBlockTooShort { .. } => AshError::FountainBlockTooShort,
            ash_core::Error::MetadataTooShort { .. } => AshError::MetadataTooShort,
            ash_core::Error::UnsupportedMetadataVersion { .. } => AshError::UnsupportedMetadataVersion,
            ash_core::Error::MetadataUrlTooLong { .. } => AshError::MetadataUrlTooLong,
            ash_core::Error::InvalidMetadataUrl => AshError::InvalidMetadataUrl,
            ash_core::Error::PadTooSmallForTokens { .. } => AshError::PadTooSmallForTokens,
            ash_core::Error::PadSizeTooSmall { .. } => AshError::PadSizeTooSmall,
            ash_core::Error::PadSizeTooBig { .. } => AshError::PadSizeTooBig,
            // Message auth errors (not exposed via FFI ceremony, but map them)
            ash_core::Error::AuthenticationFailed => AshError::CrcMismatch,
            ash_core::Error::PayloadTooLarge { .. } => AshError::EmptyPayload,
            ash_core::Error::FrameTooShort { .. } => AshError::FountainBlockTooShort,
            ash_core::Error::UnsupportedFrameVersion { .. } => AshError::UnsupportedMetadataVersion,
            ash_core::Error::InvalidMessageType { .. } => AshError::InvalidMetadataUrl,
            ash_core::Error::FrameLengthMismatch { .. } => AshError::LengthMismatch,
        }
    }
}

// === Pad Size Constants ===

/// Minimum pad size in bytes (32 KB)
pub const MIN_PAD_SIZE: u64 = ash_core::MIN_PAD_SIZE as u64;

/// Maximum pad size in bytes (1 GB)
pub const MAX_PAD_SIZE: u64 = ash_core::MAX_PAD_SIZE as u64;

/// Get minimum pad size in bytes
pub fn get_min_pad_size() -> u64 {
    MIN_PAD_SIZE
}

/// Get maximum pad size in bytes
pub fn get_max_pad_size() -> u64 {
    MAX_PAD_SIZE
}

/// Validate that a pad size is within allowed bounds
pub fn validate_pad_size(size: u64) -> bool {
    size >= MIN_PAD_SIZE && size <= MAX_PAD_SIZE
}

// === Role Enum ===

/// Role in the conversation, determining pad consumption direction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Initiator,
    Responder,
}

impl From<Role> for ash_core::Role {
    fn from(role: Role) -> Self {
        match role {
            Role::Initiator => ash_core::Role::Initiator,
            Role::Responder => ash_core::Role::Responder,
        }
    }
}

// === Pad Wrapper ===

/// Thread-safe wrapper around ash_core::Pad for FFI
pub struct Pad {
    inner: Mutex<ash_core::Pad>,
}

impl Pad {
    /// Create pad from entropy bytes.
    /// The entropy length determines the pad size (must be 32KB - 1GB).
    pub fn from_entropy(entropy: Vec<u8>) -> Result<Self, AshError> {
        let pad = ash_core::Pad::new(&entropy)?;
        Ok(Self {
            inner: Mutex::new(pad),
        })
    }

    pub fn from_bytes(bytes: Vec<u8>) -> Self {
        Self {
            inner: Mutex::new(ash_core::Pad::from_bytes(bytes)),
        }
    }

    pub fn from_bytes_with_state(bytes: Vec<u8>, consumed_front: u64, consumed_back: u64) -> Self {
        Self {
            inner: Mutex::new(ash_core::Pad::from_bytes_with_state(
                bytes,
                consumed_front as usize,
                consumed_back as usize,
            )),
        }
    }

    pub fn consume(&self, n: u32, role: Role) -> Result<Vec<u8>, AshError> {
        let mut pad = self.inner.lock().unwrap();
        Ok(pad.consume(n as usize, role.into())?)
    }

    pub fn remaining(&self) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.remaining() as u64
    }

    pub fn total_size(&self) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.total_size() as u64
    }

    pub fn consumed(&self) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.consumed() as u64
    }

    pub fn consumed_front(&self) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.consumed_front() as u64
    }

    pub fn consumed_back(&self) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.consumed_back() as u64
    }

    pub fn is_exhausted(&self) -> bool {
        let pad = self.inner.lock().unwrap();
        pad.is_exhausted()
    }

    pub fn as_bytes(&self) -> Vec<u8> {
        let pad = self.inner.lock().unwrap();
        pad.as_bytes().to_vec()
    }

    pub fn can_send(&self, length: u32, role: Role) -> bool {
        let pad = self.inner.lock().unwrap();
        pad.can_send(length as usize, role.into())
    }

    pub fn available_for_sending(&self, role: Role) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.available_for_sending(role.into()) as u64
    }

    pub fn update_peer_consumption(&self, peer_role: Role, new_consumed: u64) {
        let mut pad = self.inner.lock().unwrap();
        pad.update_peer_consumption(peer_role.into(), new_consumed as usize);
    }

    pub fn next_send_offset(&self, role: Role) -> u64 {
        let pad = self.inner.lock().unwrap();
        pad.next_send_offset(role.into()) as u64
    }

    /// Securely zero bytes at a specific offset (for forward secrecy).
    ///
    /// When a message expires, this zeros the key material used to encrypt it,
    /// preventing future decryption even if the pad is compromised.
    pub fn zero_bytes_at(&self, offset: u64, length: u64) -> bool {
        let mut pad = self.inner.lock().unwrap();
        pad.zero_bytes_at(offset as usize, length as usize)
    }
}

// === Ceremony Metadata Types ===

/// Ceremony metadata transferred via QR
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CeremonyMetadata {
    pub version: u8,
    pub ttl_seconds: u64,
    pub disappearing_messages_seconds: u32,
    pub conversation_flags: u16,
    pub relay_url: String,
}

impl From<ash_core::CeremonyMetadata> for CeremonyMetadata {
    fn from(m: ash_core::CeremonyMetadata) -> Self {
        Self {
            version: m.version,
            ttl_seconds: m.ttl_seconds,
            disappearing_messages_seconds: m.disappearing_messages_seconds,
            conversation_flags: m.conversation_flags.bits(),
            relay_url: m.relay_url,
        }
    }
}

impl From<CeremonyMetadata> for ash_core::CeremonyMetadata {
    fn from(m: CeremonyMetadata) -> Self {
        ash_core::CeremonyMetadata::with_flags(
            m.ttl_seconds,
            m.disappearing_messages_seconds,
            ash_core::ConversationFlags::from_bits(m.conversation_flags),
            m.relay_url,
        )
        .unwrap_or_default()
    }
}

// === Authorization Token Types ===

/// Authorization tokens derived from pad
#[derive(Debug, Clone)]
pub struct AuthTokens {
    pub conversation_id: String,
    pub auth_token: String,
    pub burn_token: String,
}

// === Fountain Ceremony Result ===

/// Result of fountain ceremony decoding
#[derive(Debug, Clone)]
pub struct FountainCeremonyResult {
    pub metadata: CeremonyMetadata,
    pub pad: Vec<u8>,
    pub blocks_used: u32,
}

// === Fountain Frame Generator ===

/// Thread-safe fountain frame generator for QR display
pub struct FountainFrameGenerator {
    inner: Mutex<ash_core::frame::FountainFrameGenerator>,
}

impl FountainFrameGenerator {
    /// Generate the next QR frame bytes
    pub fn next_frame(&self) -> Vec<u8> {
        let mut gen = self.inner.lock().unwrap();
        gen.next_frame()
    }

    /// Generate a specific block by index
    pub fn generate_frame(&self, index: u32) -> Vec<u8> {
        let gen = self.inner.lock().unwrap();
        gen.generate_frame(index)
    }

    /// Number of source blocks (minimum needed)
    pub fn source_count(&self) -> u32 {
        let gen = self.inner.lock().unwrap();
        gen.source_count() as u32
    }

    /// Block size in bytes
    pub fn block_size(&self) -> u32 {
        let gen = self.inner.lock().unwrap();
        gen.block_size() as u32
    }

    /// Total data size being transferred
    pub fn total_size(&self) -> u32 {
        let gen = self.inner.lock().unwrap();
        gen.total_size() as u32
    }
}

// === Fountain Frame Receiver ===

/// Thread-safe fountain frame receiver for QR scanning
pub struct FountainFrameReceiver {
    inner: Mutex<ash_core::frame::FountainFrameReceiver>,
}

impl FountainFrameReceiver {
    /// Create a new receiver.
    /// Passphrase is required and must match the sender's passphrase.
    pub fn new(passphrase: String) -> Self {
        let receiver = ash_core::frame::FountainFrameReceiver::new(&passphrase);
        Self {
            inner: Mutex::new(receiver),
        }
    }

    /// Add a scanned frame, returns true if complete
    pub fn add_frame(&self, frame_bytes: Vec<u8>) -> Result<bool, AshError> {
        let mut receiver = self.inner.lock().unwrap();
        Ok(receiver.add_frame(&frame_bytes)?)
    }

    /// Check if decoding is complete
    pub fn is_complete(&self) -> bool {
        let receiver = self.inner.lock().unwrap();
        receiver.is_complete()
    }

    /// Get decoding progress (0.0 to 1.0)
    pub fn progress(&self) -> f64 {
        let receiver = self.inner.lock().unwrap();
        receiver.progress()
    }

    /// Number of blocks received (including duplicates)
    pub fn blocks_received(&self) -> u32 {
        let receiver = self.inner.lock().unwrap();
        receiver.blocks_received() as u32
    }

    /// Number of unique blocks received (excluding duplicates)
    pub fn unique_blocks_received(&self) -> u32 {
        let receiver = self.inner.lock().unwrap();
        receiver.unique_blocks_received() as u32
    }

    /// Number of source blocks needed
    pub fn source_count(&self) -> u32 {
        let receiver = self.inner.lock().unwrap();
        receiver.source_count() as u32
    }

    /// Get the decoded result (None if not complete)
    pub fn get_result(&self) -> Option<FountainCeremonyResult> {
        let receiver = self.inner.lock().unwrap();
        receiver.get_result().map(|r| FountainCeremonyResult {
            metadata: r.metadata.into(),
            pad: r.pad,
            blocks_used: r.blocks_used as u32,
        })
    }
}

// === Free Functions ===

/// Create a fountain frame generator for ceremony.
/// Passphrase is required for encrypting the QR frames.
pub fn create_fountain_generator(
    metadata: CeremonyMetadata,
    pad_bytes: Vec<u8>,
    block_size: u32,
    passphrase: String,
) -> Result<std::sync::Arc<FountainFrameGenerator>, AshError> {
    let core_metadata: ash_core::CeremonyMetadata = metadata.into();
    let generator = ash_core::frame::create_fountain_ceremony(
        &core_metadata,
        &pad_bytes,
        block_size as usize,
        &passphrase,
    )?;
    Ok(std::sync::Arc::new(FountainFrameGenerator {
        inner: Mutex::new(generator),
    }))
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

/// Validate passphrase meets requirements
pub fn validate_passphrase(passphrase: String) -> bool {
    ash_core::passphrase::validate_passphrase(&passphrase).is_ok()
}

/// Get minimum passphrase length
pub fn get_min_passphrase_length() -> u32 {
    ash_core::passphrase::MIN_PASSPHRASE_LENGTH as u32
}

/// Get maximum passphrase length
pub fn get_max_passphrase_length() -> u32 {
    ash_core::passphrase::MAX_PASSPHRASE_LENGTH as u32
}

/// Derive conversation ID from pad bytes
pub fn derive_conversation_id(pad_bytes: Vec<u8>) -> Result<String, AshError> {
    Ok(ash_core::auth::derive_conversation_id(&pad_bytes)?)
}

/// Derive auth token from pad bytes
pub fn derive_auth_token(pad_bytes: Vec<u8>) -> Result<String, AshError> {
    Ok(ash_core::auth::derive_auth_token(&pad_bytes)?)
}

/// Derive burn token from pad bytes
pub fn derive_burn_token(pad_bytes: Vec<u8>) -> Result<String, AshError> {
    Ok(ash_core::auth::derive_burn_token(&pad_bytes)?)
}

/// Derive all tokens at once
pub fn derive_all_tokens(pad_bytes: Vec<u8>) -> Result<AuthTokens, AshError> {
    let (conversation_id, auth_token, burn_token) =
        ash_core::auth::derive_all_tokens(&pad_bytes)?;
    Ok(AuthTokens {
        conversation_id,
        auth_token,
        burn_token,
    })
}

/// Securely zero a byte array using volatile writes.
/// This prevents the compiler from optimizing away the zeroing.
pub fn secure_zero_bytes(mut data: Vec<u8>) {
    // Use volatile writes to prevent optimization (same pattern as pad.rs)
    for byte in data.iter_mut() {
        // SAFETY: We're writing to valid, aligned memory that we own
        unsafe {
            std::ptr::write_volatile(byte, 0);
        }
    }
    // Compiler fence to prevent reordering
    std::sync::atomic::compiler_fence(std::sync::atomic::Ordering::SeqCst);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pad_roundtrip() {
        // Use minimum pad size (32KB)
        let entropy = vec![0xAB; MIN_PAD_SIZE as usize];
        let pad = Pad::from_entropy(entropy).unwrap();

        assert_eq!(pad.remaining(), MIN_PAD_SIZE);
        assert!(!pad.is_exhausted());

        let consumed = pad.consume(100, Role::Initiator).unwrap();
        assert_eq!(consumed.len(), 100);
        assert_eq!(pad.remaining(), MIN_PAD_SIZE - 100);
    }

    #[test]
    fn test_pad_size_validation() {
        // Too small
        let small_entropy = vec![0xAB; 1000];
        assert!(Pad::from_entropy(small_entropy).is_err());

        // Valid minimum
        let min_entropy = vec![0xAB; MIN_PAD_SIZE as usize];
        assert!(Pad::from_entropy(min_entropy).is_ok());
    }

    #[test]
    fn test_fountain_generator_receiver() {
        let metadata = CeremonyMetadata {
            version: 1,
            ttl_seconds: 300,
            disappearing_messages_seconds: 0,
            conversation_flags: 0x000B, // Default: new message + expiring + delivery failed
            relay_url: "https://relay.test".to_string(),
        };
        let pad = vec![0x42; 2000];
        let passphrase = "test-passphrase".to_string();

        let generator = create_fountain_generator(metadata, pad.clone(), 256, passphrase.clone()).unwrap();
        let receiver = FountainFrameReceiver::new(passphrase);

        assert!(!receiver.is_complete());
        assert_eq!(receiver.progress(), 0.0);

        // Add frames until complete
        while !receiver.is_complete() {
            let frame = generator.next_frame();
            receiver.add_frame(frame).unwrap();
        }

        assert!(receiver.is_complete());
        let result = receiver.get_result().unwrap();
        assert_eq!(result.pad, pad);
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

    #[test]
    fn test_pad_size_constants() {
        assert_eq!(get_min_pad_size(), 32 * 1024);
        assert_eq!(get_max_pad_size(), 1024 * 1024 * 1024);
        assert!(validate_pad_size(32 * 1024));
        assert!(validate_pad_size(1024 * 1024));
        assert!(!validate_pad_size(1000));
    }
}
