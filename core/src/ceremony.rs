//! Ceremony metadata for QR transfer.
//!
//! Contains conversation settings that are transferred alongside the pad
//! during the ceremony. Metadata is encoded in frame 0 of the QR stream.
//!
//! Simplified ephemeral design:
//! - Messages stored in server RAM only
//! - Fixed 5-minute TTL (deleted on ACK or expiry)
//! - Immediate burn only
//! - Configurable disappearing messages (client-side display TTL)

use crate::error::{Error, Result};

/// Maximum relay URL length in bytes.
const MAX_RELAY_URL_LEN: usize = 256;

/// Default message TTL in seconds (5 minutes).
pub const DEFAULT_TTL_SECONDS: u64 = 300;

/// Ceremony metadata transferred via QR frame 0.
///
/// Contains settings agreed upon during ceremony:
/// - Server TTL (how long messages stay on relay)
/// - Disappearing messages (how long messages show on screen)
/// - Relay URL
///
/// Binary format (v1):
/// ```text
/// [version: u8][ttl: u64 BE][disappearing: u32 BE][url_len: u16 BE][url: bytes]
/// ```
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CeremonyMetadata {
    /// Protocol version (always 1)
    pub version: u8,

    /// Message TTL in seconds (how long messages stay on relay)
    /// Default: 300 (5 minutes)
    pub ttl_seconds: u64,

    /// Disappearing messages timeout in seconds (client-side display TTL)
    /// 0 = off (messages persist on screen)
    /// Otherwise: seconds until message disappears from UI after viewing
    pub disappearing_messages_seconds: u32,

    /// Relay server URL (e.g., `https://relay.ash.app`)
    pub relay_url: String,
}

impl Default for CeremonyMetadata {
    fn default() -> Self {
        Self {
            version: 1,
            ttl_seconds: DEFAULT_TTL_SECONDS,
            disappearing_messages_seconds: 0, // Off by default
            relay_url: String::new(),
        }
    }
}

impl CeremonyMetadata {
    /// Create new ceremony metadata.
    ///
    /// # Arguments
    ///
    /// * `ttl_seconds` - Message TTL in seconds (default 300, max 604800)
    /// * `disappearing_messages_seconds` - Display TTL in seconds (0 = off)
    /// * `relay_url` - Relay server URL
    ///
    /// # Errors
    ///
    /// Returns error if relay URL is too long.
    pub fn new(ttl_seconds: u64, disappearing_messages_seconds: u32, relay_url: String) -> Result<Self> {
        if relay_url.len() > MAX_RELAY_URL_LEN {
            return Err(Error::MetadataUrlTooLong {
                len: relay_url.len(),
                max: MAX_RELAY_URL_LEN,
            });
        }

        // Cap TTL to 7 days max, use default if 0
        let ttl_seconds = if ttl_seconds == 0 {
            DEFAULT_TTL_SECONDS
        } else {
            ttl_seconds.min(604800)
        };

        Ok(Self {
            version: 1,
            ttl_seconds,
            disappearing_messages_seconds,
            relay_url,
        })
    }

    /// Encode metadata to bytes for frame payload.
    ///
    /// Binary format:
    /// ```text
    /// [version: u8][ttl: u64 BE][disappearing: u32 BE][url_len: u16 BE][url: bytes]
    /// ```
    pub fn encode(&self) -> Vec<u8> {
        let url_bytes = self.relay_url.as_bytes();
        let mut bytes = Vec::with_capacity(1 + 8 + 4 + 2 + url_bytes.len());

        // Version
        bytes.push(self.version);

        // TTL (8 bytes, big-endian)
        bytes.extend_from_slice(&self.ttl_seconds.to_be_bytes());

        // Disappearing messages (4 bytes, big-endian)
        bytes.extend_from_slice(&self.disappearing_messages_seconds.to_be_bytes());

        // URL length (2 bytes, big-endian)
        bytes.extend_from_slice(&(url_bytes.len() as u16).to_be_bytes());

        // URL bytes
        bytes.extend_from_slice(url_bytes);

        bytes
    }

    /// Decode metadata from bytes.
    ///
    /// # Errors
    ///
    /// Returns error if bytes are malformed or too short.
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        // Minimum size: version(1) + ttl(8) + disappearing(4) + url_len(2) = 15 bytes
        if bytes.len() < 15 {
            return Err(Error::MetadataTooShort {
                size: bytes.len(),
                minimum: 15,
            });
        }

        let version = bytes[0];

        if version != 1 {
            return Err(Error::UnsupportedMetadataVersion { version });
        }

        let ttl_seconds = u64::from_be_bytes([
            bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8],
        ]);

        let disappearing_messages_seconds = u32::from_be_bytes([
            bytes[9], bytes[10], bytes[11], bytes[12],
        ]);

        let url_len = u16::from_be_bytes([bytes[13], bytes[14]]) as usize;

        if bytes.len() < 15 + url_len {
            return Err(Error::MetadataTooShort {
                size: bytes.len(),
                minimum: 15 + url_len,
            });
        }

        let relay_url = String::from_utf8(bytes[15..15 + url_len].to_vec())
            .map_err(|_| Error::InvalidMetadataUrl)?;

        Ok(Self {
            version: 1,
            ttl_seconds,
            disappearing_messages_seconds,
            relay_url,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metadata_roundtrip() {
        let metadata = CeremonyMetadata::new(300, 30, "https://relay.ash.app".to_string()).unwrap();

        let encoded = metadata.encode();
        let decoded = CeremonyMetadata::decode(&encoded).unwrap();

        assert_eq!(metadata, decoded);
    }

    #[test]
    fn metadata_with_disappearing_messages() {
        let metadata = CeremonyMetadata::new(300, 1800, "https://relay.ash.app".to_string()).unwrap();

        assert_eq!(metadata.disappearing_messages_seconds, 1800); // 30 minutes

        let encoded = metadata.encode();
        let decoded = CeremonyMetadata::decode(&encoded).unwrap();

        assert_eq!(decoded.disappearing_messages_seconds, 1800);
    }

    #[test]
    fn metadata_defaults() {
        let metadata = CeremonyMetadata::default();
        assert_eq!(metadata.version, 1);
        assert_eq!(metadata.ttl_seconds, DEFAULT_TTL_SECONDS);
        assert_eq!(metadata.disappearing_messages_seconds, 0); // Off by default
        assert!(metadata.relay_url.is_empty());
    }

    #[test]
    fn metadata_ttl_capped() {
        // TTL should be capped to 7 days
        let metadata = CeremonyMetadata::new(999999999, 0, String::new()).unwrap();
        assert_eq!(metadata.ttl_seconds, 604800); // 7 days
    }

    #[test]
    fn metadata_ttl_default_on_zero() {
        let metadata = CeremonyMetadata::new(0, 0, String::new()).unwrap();
        assert_eq!(metadata.ttl_seconds, DEFAULT_TTL_SECONDS);
    }

    #[test]
    fn metadata_url_too_long() {
        let long_url = "x".repeat(300);
        let result = CeremonyMetadata::new(60, 0, long_url);
        assert!(matches!(result, Err(Error::MetadataUrlTooLong { .. })));
    }

    #[test]
    fn metadata_decode_too_short() {
        let result = CeremonyMetadata::decode(&[1, 0, 0, 0]);
        assert!(matches!(result, Err(Error::MetadataTooShort { .. })));
    }

    #[test]
    fn metadata_unsupported_version() {
        let mut encoded = CeremonyMetadata::default().encode();
        encoded[0] = 99; // Invalid version
        let result = CeremonyMetadata::decode(&encoded);
        assert!(matches!(result, Err(Error::UnsupportedMetadataVersion { .. })));
    }
}
