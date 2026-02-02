# Encryption Self-Classification Report

## Submission Information

**To:** crypt@bis.gov, enc@nsa.gov

**Subject:** ENC Self-Classification Report for Mass Market Encryption - ASH Messaging Application

**Date:** [INSERT DATE]

**Submission Type:** Mass Market Self-Classification (Section 742.15(b)(1))

---

## Part 1: Company Information

**Company/Developer Name:** [YOUR COMPANY NAME]

**Address:** [YOUR ADDRESS]

**Contact Name:** [YOUR NAME]

**Contact Email:** [YOUR EMAIL]

**Contact Phone:** [YOUR PHONE]

---

## Part 2: Product Information

**Product Name:** ASH

**Version:** 1.0

**Product Type:** Mobile Application (iOS)

**ECCN:** 5D992.c (Mass market encryption software)

**Product Website/URL:** [YOUR WEBSITE OR APP STORE URL]

---

## Part 3: Product Description

### 3.1 General Description

ASH is a secure messaging application for iOS that enables private, ephemeral communication between two individuals. The application is designed for personal use between trusted parties who meet in person to establish a secure communication channel.

### 3.2 Primary Function

The primary function of ASH is to provide confidential text messaging between two users. Users exchange cryptographic key material in person through a QR code scanning process (called a "ceremony"), then use this key material to encrypt and decrypt messages sent through a relay server.

### 3.3 Target Market

- General consumers
- Individuals seeking private personal communication
- Not designed for government, military, or enterprise use

### 3.4 Distribution

- Apple App Store (iOS)
- Available to the general public
- No restrictions on who may download

---

## Part 4: Encryption Details

### 4.1 Encryption Algorithm

**Algorithm Name:** One-Time Pad (OTP) / Vernam Cipher

**Type:** Symmetric stream cipher

**Operation:** XOR (exclusive-or) of plaintext with random key bytes

**Implementation:**
```
ciphertext[i] = plaintext[i] XOR key[i]
plaintext[i] = ciphertext[i] XOR key[i]
```

### 4.2 Key Length

**Key Length:** Variable, equal to message length

**Effective Security:** Information-theoretic (unbreakable when used correctly)

**Note:** While the key length is unlimited, the XOR operation has zero computational complexity. Security depends entirely on key secrecy, not algorithmic strength.

### 4.3 Key Generation

- Keys are generated locally on user devices
- Uses iOS SecRandomCopyBytes (OS-provided cryptographically secure random number generator)
- Key material is generated during in-person "ceremony" between two users
- Typical key sizes: 64KB, 256KB, or 1MB (user-selectable)

### 4.4 Key Exchange

- **Method:** In-person QR code scanning
- **No network transmission:** Keys are NEVER sent over any network
- **Physical proximity required:** Both users must be in the same location
- **Visual verification:** Users verify key integrity via spoken mnemonic checksum

### 4.5 Key Storage

- Stored in iOS Keychain with hardware-backed protection
- Encrypted at rest by iOS Data Protection
- Accessible only to the ASH application

### 4.6 Key Destruction

- Pad bytes are zeroed immediately after each use
- Expired message key segments are permanently overwritten with zeros
- "Burn" function destroys all remaining key material
- No key recovery or escrow mechanism exists
- Destruction is irreversible

### 4.7 Message Authentication

**Algorithm:** Wegman-Carter MAC with polynomial hashing

**Hash Function:** Polynomial evaluation over GF(2^128)

**Tag Size:** 256 bits (32 bytes)

**Purpose:** Message integrity and authenticity verification (not confidentiality)

**Key Material:** 64 bytes per message from the one-time pad

### 4.8 QR Code Obfuscation (Optional)

**Algorithm:** XOR with passphrase-derived key

**Purpose:** Prevent casual visual observation during key ceremony

**Usage:** Only during in-person key exchange, not for message transmission

---

## Part 5: Encryption Architecture

### 5.1 Data Flow

```
┌─────────────┐                              ┌─────────────┐
│   User A    │                              │   User B    │
│   Device    │                              │   Device    │
└──────┬──────┘                              └──────┬──────┘
       │                                            │
       │  1. In-person key exchange (QR codes)      │
       │◄──────────────────────────────────────────►│
       │                                            │
       │  2. Keys stored locally (never transmitted)│
       │                                            │
       │         ┌─────────────────┐                │
       │         │  Relay Server   │                │
       │         │  (untrusted)    │                │
       │         └────────┬────────┘                │
       │                  │                         │
       │  3. Encrypted    │   3. Encrypted          │
       │     blobs only   │      blobs only         │
       └──────────────────┴─────────────────────────┘
```

### 5.2 Network Transmission

- Only encrypted message blobs are transmitted over the network
- Relay server cannot decrypt any data
- Relay server does not possess any key material
- Standard HTTPS/TLS (iOS-provided) used for transport security

### 5.3 Components

| Component | Encryption Used | Key Source |
|-----------|-----------------|------------|
| Message encryption | XOR (OTP) | Local pad |
| Message authentication | Wegman-Carter MAC | Local pad |
| Network transport | TLS 1.3 | iOS-managed |
| Key ceremony (optional) | XOR | Passphrase-derived |

---

## Part 6: Source Code

### 6.1 Encryption Source Code Location

The encryption implementation is contained in the following open-source files:

- `core/src/otp.rs` - One-Time Pad XOR encryption/decryption
- `core/src/mac.rs` - Wegman-Carter message authentication
- `core/src/gf128.rs` - Galois field arithmetic for MAC
- `core/src/poly_hash.rs` - Polynomial hashing for MAC
- `core/src/pad.rs` - Key material management and destruction

### 6.2 Third-Party Encryption Libraries

**None.** ASH implements its own encryption using only:
- Basic XOR operation (built-in language operator)
- iOS SecRandomCopyBytes for random number generation
- iOS Keychain for secure storage

No third-party cryptographic libraries are used.

---

## Part 7: Cryptographic Interfaces

### 7.1 Object Code Interfaces

The application does not provide any programming interfaces (APIs) that would allow other software to utilize its encryption capabilities.

### 7.2 User Interfaces

Users interact with encryption through:
- Message compose/view screens (encryption/decryption happens automatically)
- Key ceremony screens (QR code display/scanning)
- Burn button (key destruction)

Users cannot directly access cryptographic functions or export encrypted data in a programmatic way.

---

## Part 8: Export Exemption Justification

ASH qualifies for Mass Market classification (ECCN 5D992.c) under EAR Section 742.15(b) because:

1. **Generally available to the public:** Distributed through the Apple App Store with no purchase restrictions

2. **Consumer-oriented:** Designed for personal messaging between individuals, not for commercial, government, or military applications

3. **No customization:** The encryption functionality cannot be modified or customized by users or third parties

4. **Standard installation:** Installed via standard App Store process, no special configuration required

5. **No key escrow:** The application does not support key escrow, key recovery, or any form of exceptional access

6. **Encryption is ancillary:** The encryption serves to protect personal communications, which is an ancillary function common in consumer messaging applications

7. **Symmetric only:** Uses symmetric encryption (XOR) with no asymmetric/public-key cryptography

---

## Part 9: Certifications

I certify that:

1. The information provided in this self-classification report is accurate and complete to the best of my knowledge.

2. This product will be exported in accordance with the Export Administration Regulations (EAR).

3. This product is not designed or modified for military or intelligence applications.

4. This product does not contain, and is not designed to use, any encryption algorithm that provides a digital security level exceeding the equivalent of 56-bit symmetric encryption, except as permitted under License Exception ENC.

5. I understand that the Bureau of Industry and Security may request additional information regarding this classification.

---

**Submitted by:**

Name: [YOUR NAME]

Title: [YOUR TITLE]

Company: [YOUR COMPANY]

Date: [DATE]

Signature: _______________________

---

## Attachments

1. Product screenshots (optional)
2. Technical documentation: `docs/export-compliance.md`
3. Threat model documentation: `docs/threat-model.md`
