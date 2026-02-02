# ASH Export Compliance Documentation

This document describes ASH's use of encryption for Apple App Store export compliance requirements.

## Summary

**Does this app use encryption?** Yes

**App Uses Non-Exempt Encryption:** Yes

ASH uses encryption that qualifies for the export exemption under **Category 5, Part 2, Note 4** of the Wassenaar Arrangement.

## Encryption Technologies Used

### 1. One-Time Pad (OTP) Encryption

**Algorithm:** XOR cipher with pre-shared random key material

**Purpose:** Message confidentiality between conversation participants

**Implementation:**
- Plaintext is XORed with random key bytes of equal length
- Key material is generated locally on user devices
- Each key byte is used exactly once (enforced by design)
- No key is ever transmitted over the network

**Standard:** One-Time Pad is a well-established cryptographic technique published by Gilbert Vernam (1917) and proven information-theoretically secure by Claude Shannon (1949). The XOR operation is a fundamental bitwise operation, not a proprietary algorithm.

### 2. Wegman-Carter Message Authentication Code (MAC)

**Algorithm:** Polynomial hashing over GF(2^128) with one-time masking

**Purpose:** Message integrity and authenticity verification

**Implementation:**
- 256-bit authentication tags using dual polynomial hashes
- Hash keys and masks come from the one-time pad
- Provides information-theoretic authentication (not encryption)

**Standard:** Wegman-Carter authentication is a published construction (1981) accepted by the cryptographic community. It uses standard finite field arithmetic.

### 3. QR Frame Obfuscation

**Algorithm:** XOR cipher with passphrase-derived key

**Purpose:** Optional visual protection during key ceremony (prevents casual observation of QR codes)

**Implementation:**
- Simple XOR with a key derived from a user-spoken passphrase
- Used only during the in-person key exchange ceremony
- Not used for message transmission

## Exemption Justification

ASH qualifies for export exemption because:

1. **Personal use:** The encryption is used solely for personal, private communication between individuals who have met in person.

2. **No key escrow:** There is no key recovery, key escrow, or backdoor capability. Users control all key material.

3. **Authentication only over network:** Messages sent over the network are encrypted with keys that never traverse the network. The relay server only sees opaque encrypted blobs.

4. **Standard algorithms:** XOR (exclusive-or) is a fundamental binary operation available in all computing systems. Polynomial arithmetic over finite fields is standard mathematics.

5. **Not designed for:**
   - Government or military use
   - Critical infrastructure
   - Commercial sale of encryption services

## Technical Details

### Key Material Generation
- Random bytes generated using OS-provided secure random (`SecRandomCopyBytes` on iOS)
- Keys are generated locally during an in-person "ceremony" between users
- Keys are transferred via QR codes during physical proximity (no network transmission)

### Key Storage
- Key material stored in iOS Keychain with hardware-backed encryption
- Keys are destroyed ("burned") when conversation is deleted

### Key Destruction
- Pad bytes are zeroed immediately after use for encryption/decryption
- When messages expire (TTL), associated pad segments are permanently zeroed
- When a conversation is "burned," all remaining pad material is overwritten with zeros
- No key recovery mechanism exists - destroyed keys cannot be recovered

### Network Data
- Only encrypted message blobs are transmitted over the network
- The relay server cannot decrypt any data
- No encryption keys are ever transmitted over the network

## Classification

**ECCN:** 5D992 (Mass market encryption software with symmetric key length ≤ 56 bits effective, or using authentication-only algorithms)

**Note:** While OTP technically uses unlimited key length, each XOR operation is equivalent to a stream cipher with no computational complexity. The algorithm provides no protection against a key-holder, only against third parties without key access.

## Contact

For questions about this export compliance documentation, contact the app developer.

---

*Last updated: February 2026*
