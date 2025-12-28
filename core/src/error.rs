//! Error types for ash-core.
//!
//! All errors are explicit and designed for clear FFI boundary communication.
//! No external dependencies - implements std::error::Error manually.

use std::error::Error as StdError;
use std::fmt;

/// Result type alias for ash-core operations.
pub type Result<T> = std::result::Result<T, Error>;

/// Errors that can occur during ash-core operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// Not enough bytes remaining in the pad for the requested operation.
    InsufficientPadBytes {
        /// Number of bytes requested.
        needed: usize,
        /// Number of bytes available.
        available: usize,
    },

    /// Entropy provided does not match expected pad size.
    InvalidEntropySize {
        /// Actual entropy size provided.
        size: usize,
        /// Expected entropy size for the pad.
        expected: usize,
    },

    /// Attempted to consume from an already exhausted pad.
    PadExhausted,

    /// Key and data lengths don't match for OTP operation.
    LengthMismatch {
        /// Length of the pad slice.
        pad_len: usize,
        /// Length of the data.
        data_len: usize,
    },

    /// Frame data is too short to be valid.
    FrameTooShort {
        /// Actual frame size.
        size: usize,
        /// Minimum required size.
        minimum: usize,
    },

    /// CRC checksum verification failed.
    CrcMismatch {
        /// Expected CRC value.
        expected: u32,
        /// Actual computed CRC value.
        actual: u32,
    },

    /// Frame index exceeds total frame count.
    FrameIndexOutOfBounds {
        /// Frame index that was out of bounds.
        index: u16,
        /// Total number of frames.
        total: u16,
    },

    /// Frames have inconsistent total counts.
    FrameCountMismatch {
        /// Expected total frame count.
        expected: u16,
        /// Actual total frame count found.
        actual: u16,
    },

    /// Some frames are missing from the sequence.
    MissingFrames {
        /// List of missing frame indices.
        missing: Vec<u16>,
    },

    /// Same frame index appears more than once.
    DuplicateFrame {
        /// The duplicated frame index.
        index: u16,
    },

    /// Payload cannot be empty.
    EmptyPayload,

    /// Payload exceeds maximum allowed size.
    PayloadTooLarge {
        /// Actual payload size.
        size: usize,
        /// Maximum allowed size.
        max: usize,
    },

    /// No frames were provided for reconstruction.
    NoFrames,

    /// Total frame count cannot be zero.
    ZeroTotalFrames,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::InsufficientPadBytes { needed, available } => {
                write!(
                    f,
                    "insufficient pad bytes: needed {}, available {}",
                    needed, available
                )
            }
            Error::InvalidEntropySize { size, expected } => {
                write!(
                    f,
                    "invalid entropy size: got {}, expected {}",
                    size, expected
                )
            }
            Error::PadExhausted => write!(f, "pad already exhausted"),
            Error::LengthMismatch { pad_len, data_len } => {
                write!(
                    f,
                    "length mismatch: pad slice has {} bytes, data has {} bytes",
                    pad_len, data_len
                )
            }
            Error::FrameTooShort { size, minimum } => {
                write!(
                    f,
                    "frame too short: got {} bytes, minimum is {}",
                    size, minimum
                )
            }
            Error::CrcMismatch { expected, actual } => {
                write!(
                    f,
                    "CRC mismatch: expected {:#010x}, got {:#010x}",
                    expected, actual
                )
            }
            Error::FrameIndexOutOfBounds { index, total } => {
                write!(
                    f,
                    "frame index out of bounds: index {} >= total {}",
                    index, total
                )
            }
            Error::FrameCountMismatch { expected, actual } => {
                write!(
                    f,
                    "frame count mismatch: expected {}, got {}",
                    expected, actual
                )
            }
            Error::MissingFrames { missing } => {
                write!(f, "missing frames: {:?}", missing)
            }
            Error::DuplicateFrame { index } => {
                write!(f, "duplicate frame at index {}", index)
            }
            Error::EmptyPayload => write!(f, "empty payload not allowed"),
            Error::PayloadTooLarge { size, max } => {
                write!(
                    f,
                    "payload too large: {} bytes exceeds maximum {}",
                    size, max
                )
            }
            Error::NoFrames => write!(f, "no frames provided"),
            Error::ZeroTotalFrames => {
                write!(f, "invalid total frame count: cannot be zero")
            }
        }
    }
}

impl StdError for Error {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_display_messages() {
        let err = Error::InsufficientPadBytes {
            needed: 100,
            available: 50,
        };
        assert_eq!(
            err.to_string(),
            "insufficient pad bytes: needed 100, available 50"
        );

        let err = Error::CrcMismatch {
            expected: 0xDEADBEEF,
            actual: 0xCAFEBABE,
        };
        assert!(err.to_string().contains("0xdeadbeef"));
        assert!(err.to_string().contains("0xcafebabe"));
    }

    #[test]
    fn error_implements_std_error() {
        let err = Error::PadExhausted;
        let _: &dyn StdError = &err;
    }
}
