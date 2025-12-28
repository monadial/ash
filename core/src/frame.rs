//! Frame encoding and decoding for QR code transfer.
//!
//! Frame format:
//! ```text
//! +------------------+------------------+------------------+------------------+
//! |   Frame Index    |   Total Frames   |   Payload        |   CRC-32         |
//! |   (2 bytes BE)   |   (2 bytes BE)   |   (1-1000 bytes) |   (4 bytes BE)   |
//! +------------------+------------------+------------------+------------------+
//! ```

use crate::crc;
use crate::error::{Error, Result};

/// Maximum payload size per frame (bytes).
pub const MAX_PAYLOAD_SIZE: usize = 1000;

/// Minimum frame size: header (4) + min payload (1) + CRC (4) = 9 bytes.
pub const MIN_FRAME_SIZE: usize = 9;

/// Header size: index (2) + total (2) = 4 bytes.
const HEADER_SIZE: usize = 4;

/// CRC size: 4 bytes.
const CRC_SIZE: usize = 4;

/// A frame containing a chunk of pad data.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    /// Zero-based index of this frame.
    pub index: u16,
    /// Total number of frames in the sequence.
    pub total: u16,
    /// Payload bytes (pad chunk).
    pub payload: Vec<u8>,
}

impl Frame {
    /// Create a new frame.
    ///
    /// # Errors
    ///
    /// Returns error if payload is empty or too large.
    pub fn new(index: u16, total: u16, payload: Vec<u8>) -> Result<Self> {
        if payload.is_empty() {
            return Err(Error::EmptyPayload);
        }
        if payload.len() > MAX_PAYLOAD_SIZE {
            return Err(Error::PayloadTooLarge {
                size: payload.len(),
                max: MAX_PAYLOAD_SIZE,
            });
        }
        if total == 0 {
            return Err(Error::ZeroTotalFrames);
        }
        if index >= total {
            return Err(Error::FrameIndexOutOfBounds { index, total });
        }

        Ok(Self {
            index,
            total,
            payload,
        })
    }

    /// Encode frame to bytes for QR code display.
    ///
    /// Format: [index: u16 BE][total: u16 BE][payload][crc32: u32 BE]
    pub fn encode(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(HEADER_SIZE + self.payload.len() + CRC_SIZE);

        // Header
        bytes.extend_from_slice(&self.index.to_be_bytes());
        bytes.extend_from_slice(&self.total.to_be_bytes());

        // Payload
        bytes.extend_from_slice(&self.payload);

        // CRC over header + payload
        let checksum = crc::compute(&bytes);
        bytes.extend_from_slice(&checksum.to_be_bytes());

        bytes
    }

    /// Decode frame from bytes (validates CRC).
    ///
    /// # Errors
    ///
    /// - `FrameTooShort` if less than minimum frame size
    /// - `CrcMismatch` if checksum doesn't match
    /// - `FrameIndexOutOfBounds` if index >= total
    /// - `ZeroTotalFrames` if total is 0
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        if bytes.len() < MIN_FRAME_SIZE {
            return Err(Error::FrameTooShort {
                size: bytes.len(),
                minimum: MIN_FRAME_SIZE,
            });
        }

        // Split into data and CRC
        let (data, crc_bytes) = bytes.split_at(bytes.len() - CRC_SIZE);

        // Verify CRC
        let expected_crc =
            u32::from_be_bytes([crc_bytes[0], crc_bytes[1], crc_bytes[2], crc_bytes[3]]);
        let actual_crc = crc::compute(data);

        if actual_crc != expected_crc {
            return Err(Error::CrcMismatch {
                expected: expected_crc,
                actual: actual_crc,
            });
        }

        // Parse header
        let index = u16::from_be_bytes([data[0], data[1]]);
        let total = u16::from_be_bytes([data[2], data[3]]);

        // Validate header
        if total == 0 {
            return Err(Error::ZeroTotalFrames);
        }
        if index >= total {
            return Err(Error::FrameIndexOutOfBounds { index, total });
        }

        // Extract payload
        let payload = data[HEADER_SIZE..].to_vec();
        if payload.is_empty() {
            return Err(Error::EmptyPayload);
        }

        Ok(Self {
            index,
            total,
            payload,
        })
    }
}

/// Create frames from pad bytes.
///
/// Chunks the pad into frames suitable for QR code transfer.
///
/// # Arguments
///
/// * `pad_bytes` - The full pad to chunk
/// * `max_payload` - Maximum bytes per frame payload (default: 1000)
///
/// # Returns
///
/// Vector of frames in order (0 to N-1).
pub fn create_frames(pad_bytes: &[u8], max_payload: usize) -> Result<Vec<Frame>> {
    if pad_bytes.is_empty() {
        return Err(Error::EmptyPayload);
    }

    let max_payload = max_payload.min(MAX_PAYLOAD_SIZE);
    let total_frames = pad_bytes.len().div_ceil(max_payload);

    if total_frames > u16::MAX as usize {
        return Err(Error::PayloadTooLarge {
            size: pad_bytes.len(),
            max: MAX_PAYLOAD_SIZE * u16::MAX as usize,
        });
    }

    let total = total_frames as u16;
    let mut frames = Vec::with_capacity(total_frames);

    for (i, chunk) in pad_bytes.chunks(max_payload).enumerate() {
        let frame = Frame::new(i as u16, total, chunk.to_vec())?;
        frames.push(frame);
    }

    Ok(frames)
}

/// Reconstruct pad from frames.
///
/// # Arguments
///
/// * `frames` - Frames to reassemble (order doesn't matter)
///
/// # Errors
///
/// - `NoFrames` if frames is empty
/// - `FrameCountMismatch` if frames have inconsistent total counts
/// - `MissingFrames` if any frames are missing
/// - `DuplicateFrame` if a frame index appears twice
pub fn reconstruct_pad(frames: &[Frame]) -> Result<Vec<u8>> {
    if frames.is_empty() {
        return Err(Error::NoFrames);
    }

    // All frames must agree on total count
    let total = frames[0].total;
    for frame in frames {
        if frame.total != total {
            return Err(Error::FrameCountMismatch {
                expected: total,
                actual: frame.total,
            });
        }
    }

    // Sort frames by index and check for duplicates/missing
    let mut sorted: Vec<_> = frames.iter().collect();
    sorted.sort_by_key(|f| f.index);

    // Check for duplicates
    for window in sorted.windows(2) {
        if window[0].index == window[1].index {
            return Err(Error::DuplicateFrame {
                index: window[0].index,
            });
        }
    }

    // Check for missing frames
    let indices: std::collections::HashSet<u16> = frames.iter().map(|f| f.index).collect();
    let missing: Vec<u16> = (0..total).filter(|i| !indices.contains(i)).collect();

    if !missing.is_empty() {
        return Err(Error::MissingFrames { missing });
    }

    // Reconstruct pad
    let mut pad = Vec::new();
    for frame in sorted {
        pad.extend_from_slice(&frame.payload);
    }

    Ok(pad)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frame_new_valid() {
        let frame = Frame::new(0, 5, vec![1, 2, 3]).unwrap();
        assert_eq!(frame.index, 0);
        assert_eq!(frame.total, 5);
        assert_eq!(frame.payload, vec![1, 2, 3]);
    }

    #[test]
    fn frame_new_empty_payload() {
        let result = Frame::new(0, 1, vec![]);
        assert!(matches!(result, Err(Error::EmptyPayload)));
    }

    #[test]
    fn frame_new_payload_too_large() {
        let payload = vec![0; MAX_PAYLOAD_SIZE + 1];
        let result = Frame::new(0, 1, payload);
        assert!(matches!(result, Err(Error::PayloadTooLarge { .. })));
    }

    #[test]
    fn frame_new_index_out_of_bounds() {
        let result = Frame::new(5, 5, vec![1]);
        assert!(matches!(result, Err(Error::FrameIndexOutOfBounds { .. })));
    }

    #[test]
    fn frame_new_zero_total() {
        let result = Frame::new(0, 0, vec![1]);
        assert!(matches!(result, Err(Error::ZeroTotalFrames)));
    }

    #[test]
    fn frame_encode_decode_roundtrip() {
        let frame = Frame::new(3, 10, vec![0xDE, 0xAD, 0xBE, 0xEF]).unwrap();
        let encoded = frame.encode();
        let decoded = Frame::decode(&encoded).unwrap();
        assert_eq!(frame, decoded);
    }

    #[test]
    fn frame_decode_crc_mismatch() {
        let frame = Frame::new(0, 1, vec![1, 2, 3]).unwrap();
        let mut encoded = frame.encode();
        // Corrupt a byte
        encoded[5] ^= 0xFF;
        let result = Frame::decode(&encoded);
        assert!(matches!(result, Err(Error::CrcMismatch { .. })));
    }

    #[test]
    fn frame_decode_too_short() {
        let result = Frame::decode(&[0, 1, 2, 3, 4, 5, 6, 7]); // 8 bytes < 9 minimum
        assert!(matches!(result, Err(Error::FrameTooShort { .. })));
    }

    #[test]
    fn create_frames_basic() {
        let pad = vec![0u8; 2500]; // 2.5 KB
        let frames = create_frames(&pad, 1000).unwrap();

        assert_eq!(frames.len(), 3);
        assert_eq!(frames[0].index, 0);
        assert_eq!(frames[0].total, 3);
        assert_eq!(frames[0].payload.len(), 1000);
        assert_eq!(frames[1].payload.len(), 1000);
        assert_eq!(frames[2].payload.len(), 500);
    }

    #[test]
    fn create_frames_empty() {
        let result = create_frames(&[], 1000);
        assert!(matches!(result, Err(Error::EmptyPayload)));
    }

    #[test]
    fn reconstruct_pad_basic() {
        let original: Vec<u8> = (0..250).collect();
        let frames = create_frames(&original, 100).unwrap();
        let reconstructed = reconstruct_pad(&frames).unwrap();
        assert_eq!(original, reconstructed);
    }

    #[test]
    fn reconstruct_pad_out_of_order() {
        let original: Vec<u8> = (0..250).collect();
        let mut frames = create_frames(&original, 100).unwrap();

        // Shuffle frames
        frames.reverse();

        let reconstructed = reconstruct_pad(&frames).unwrap();
        assert_eq!(original, reconstructed);
    }

    #[test]
    fn reconstruct_pad_missing_frame() {
        let original = vec![0u8; 300];
        let mut frames = create_frames(&original, 100).unwrap();

        // Remove middle frame
        frames.remove(1);

        let result = reconstruct_pad(&frames);
        assert!(matches!(result, Err(Error::MissingFrames { missing }) if missing == vec![1]));
    }

    #[test]
    fn reconstruct_pad_duplicate_frame() {
        let original = vec![0u8; 200];
        let mut frames = create_frames(&original, 100).unwrap();

        // Duplicate first frame
        frames.push(frames[0].clone());

        let result = reconstruct_pad(&frames);
        assert!(matches!(result, Err(Error::DuplicateFrame { index: 0 })));
    }

    #[test]
    fn reconstruct_pad_count_mismatch() {
        let frames = vec![
            Frame::new(0, 3, vec![1]).unwrap(),
            Frame::new(1, 2, vec![2]).unwrap(), // Different total
        ];

        let result = reconstruct_pad(&frames);
        assert!(matches!(result, Err(Error::FrameCountMismatch { .. })));
    }

    #[test]
    fn full_roundtrip() {
        // Simulate complete ceremony transfer
        let original_pad: Vec<u8> = (0..=255).cycle().take(5000).collect();

        // Sender creates frames
        let frames = create_frames(&original_pad, MAX_PAYLOAD_SIZE).unwrap();

        // Simulate QR encoding/decoding
        let encoded: Vec<Vec<u8>> = frames.iter().map(|f| f.encode()).collect();
        let decoded: Vec<Frame> = encoded.iter().map(|b| Frame::decode(b).unwrap()).collect();

        // Receiver reconstructs pad
        let reconstructed = reconstruct_pad(&decoded).unwrap();

        assert_eq!(original_pad, reconstructed);
    }
}
