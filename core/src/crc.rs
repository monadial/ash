//! CRC-32 computation for frame integrity.
//!
//! Implements ISO 3309 / IEEE 802.3 CRC-32 from scratch.
//! No external dependencies.

/// CRC-32 polynomial (reflected form of 0x04C11DB7).
const POLYNOMIAL: u32 = 0xEDB88320;

/// Initial CRC value.
const INIT: u32 = 0xFFFFFFFF;

/// Pre-computed lookup table for CRC-32.
/// Generated at compile time for the reflected polynomial.
const CRC_TABLE: [u32; 256] = generate_table();

/// Generate the CRC lookup table at compile time.
const fn generate_table() -> [u32; 256] {
    let mut table = [0u32; 256];
    let mut i = 0u32;
    while i < 256 {
        let mut crc = i;
        let mut j = 0;
        while j < 8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ POLYNOMIAL;
            } else {
                crc >>= 1;
            }
            j += 1;
        }
        table[i as usize] = crc;
        i += 1;
    }
    table
}

/// Compute CRC-32 checksum of data.
///
/// Uses ISO 3309 polynomial (same as Ethernet/ZIP/PNG).
#[inline]
pub fn compute(data: &[u8]) -> u32 {
    let mut crc = INIT;
    for &byte in data {
        let index = ((crc ^ byte as u32) & 0xFF) as usize;
        crc = (crc >> 8) ^ CRC_TABLE[index];
    }
    crc ^ INIT // Final XOR
}

/// Verify CRC-32 checksum matches expected value.
#[inline]
pub fn verify(data: &[u8], expected: u32) -> bool {
    compute(data) == expected
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crc_known_vectors() {
        // "123456789" should produce 0xCBF43926 (standard test vector)
        let data = b"123456789";
        assert_eq!(compute(data), 0xCBF43926);
    }

    #[test]
    fn crc_empty() {
        assert_eq!(compute(&[]), 0x00000000);
    }

    #[test]
    fn crc_single_byte() {
        // Known value for single 'a' byte
        let crc = compute(b"a");
        assert_eq!(crc, 0xE8B7BE43);
    }

    #[test]
    fn crc_verify_works() {
        let data = b"test data";
        let crc = compute(data);
        assert!(verify(data, crc));
        assert!(!verify(data, crc ^ 1)); // flip one bit
    }

    #[test]
    fn crc_deterministic() {
        let data = b"deterministic test";
        let crc1 = compute(data);
        let crc2 = compute(data);
        assert_eq!(crc1, crc2);
    }

    #[test]
    fn crc_table_first_entries() {
        // Verify table generation is correct
        assert_eq!(CRC_TABLE[0], 0x00000000);
        assert_eq!(CRC_TABLE[1], 0x77073096);
        assert_eq!(CRC_TABLE[255], 0x2D02EF8D);
    }
}
