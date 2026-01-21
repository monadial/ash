# ASH — Threat Model (v1)

This document describes the **explicit threat model** for ASH version 1.

Its purpose is to:
- make security assumptions visible
- prevent false expectations
- guide implementation decisions
- align contributors (human and AI)
- provide clarity for users and reviewers

ASH is designed to reduce risk, not eliminate it.

---

## Security philosophy

ASH assumes:
- humans make mistakes
- software systems are fallible
- infrastructure should not be trusted
- security must be understandable by users

ASH intentionally favors:
- small, auditable components
- explicit user actions
- offline-first security guarantees
- minimal reliance on third parties

ASH does **not** promise absolute security.

---

## Assets to protect

ASH aims to protect the following assets:

1. **Message confidentiality**
   - Message contents must remain unreadable to anyone except participants.

2. **Pad secrecy**
   - One-Time Pad material must never be reused.
   - Pad material must not be recoverable after burn.

3. **Conversation integrity**
   - Messages must not be silently altered without detection.

4. **User understanding**
   - Users must be able to reason about what is happening.
   - Security must not rely on invisible background behavior.

---

## Trust boundaries

ASH has **strict trust boundaries**:

### Trusted
- The shared Rust core (`ash-core`)
- The user performing the ceremony correctly
- The operating system *to a limited extent*

### Partially trusted
- The iOS application runtime
- Device secure storage (Keychain / equivalent)

### Not trusted
- Backend infrastructure
- Network transport
- Push notification services
- Other devices
- Physical environment
- Observers

---

## Attacker models

ASH considers the following attackers.

---

### 1. Network attacker (passive)

**Capabilities**
- Observes network traffic
- Records packets
- Replays messages

**Defenses**
- One-Time Pad encryption
- Encrypted blobs only
- No plaintext over network
- Backend ignorance of contents

**Residual risk**
- Metadata leakage (timing, size)

---

### 2. Network attacker (active)

**Capabilities**
- Modifies packets
- Drops packets
- Replays packets
- Forges messages

**Defenses**
- **Wegman-Carter 256-bit authentication** (information-theoretic)
- Frame integrity checks (CRC)
- Deterministic pad consumption
- Message ordering constraints

**Residual risk**
- Denial of service (not prevented)

**Note:** Message authentication uses a 256-bit Wegman-Carter MAC with dual GF(2^128)
polynomial hashing. This provides information-theoretic authentication — an attacker
cannot forge valid messages regardless of computational power. Forgery probability
is ~2^-128.

---

### 3. Backend compromise

**Capabilities**
- Full access to backend storage
- Access to logs and memory
- Ability to inject or drop messages

**Defenses**
- Backend never sees plaintext
- No keys stored on backend
- Encrypted blobs only
- Burn propagation is best-effort

**Residual risk**
- Message delay
- Message loss
- Metadata observation

ASH explicitly assumes the backend may be hostile.

---

### 4. Malicious or curious service provider

**Capabilities**
- Observes infrastructure behavior
- Inspects memory and storage
- Accesses logs

**Defenses**
- No secrets stored server-side
- No long-term storage
- No meaningful data to exfiltrate

**Residual risk**
- Traffic analysis

---

### 5. Shoulder-surfing / visual observation

**Capabilities**
- Observes screens during ceremony
- Records QR codes visually

**Defenses**
- Optional passphrase-encrypted QR frames
- Human-verifiable mnemonic checksum
- User guidance to perform ceremony privately

**Residual risk**
- Full pad compromise if ceremony is fully recorded

This is a known and accepted risk.

---

### 6. Compromised backend + delayed attack

**Capabilities**
- Records encrypted traffic
- Attempts later decryption

**Defenses**
- Information-theoretic security of OTP
- No key reuse
- No key escrow

**Residual risk**
- None, assuming pad secrecy is maintained

---

### 7. Compromised device (software)

**Capabilities**
- Malware on device
- Screen recording
- Memory inspection
- Keychain access

**Defenses**
- Best-effort memory wipe
- Limited data lifetime
- No background decryption

**Residual risk**
- Full compromise possible

ASH does **not** defend against a compromised operating system.

---

### 8. Compromised device (physical)

**Capabilities**
- Physical access to device
- Forensic tools
- Cold boot attacks

**Defenses**
- Ephemeral message lifecycle (default)
- Best-effort wipe
- Reliance on OS protections

**Residual risk**
- Partial or full recovery possible
- **Higher risk with persistent mode** — see [persistent-messages.md](persistent-messages.md)

ASH does **not** claim forensic resistance.

> **Note**: Conversations with persistent storage enabled have increased forensic exposure.
> Encrypted message blobs are stored on disk and may be recoverable until the conversation is burned.

---

### 9. Malicious conversation participant

**Capabilities**
- Screenshots
- Recording
- Copying messages
- Exporting data

**Defenses**
- None

ASH explicitly does **not** defend against a malicious participant.

Trust between participants is required.

---

## Out-of-scope threats (explicit)

ASH does **not** defend against:

- A compromised operating system
- A malicious participant
- Physical device seizure
- Advanced forensic analysis
- Network anonymity attacks
- Traffic correlation attacks
- Coercion or legal compulsion
- Side-channel attacks
- Supply-chain attacks
- Rogue OS updates

---

## Security guarantees (what ASH *does* provide)

ASH provides the following guarantees **if used correctly**:

- Message confidentiality against network and backend observers
- Information-theoretic security via One-Time Pad
- **Information-theoretic message authentication** via Wegman-Carter MAC
- **256-bit authentication tags** using dual GF(2^128) polynomial hashing
- **Traffic analysis protection** via mandatory 32-byte message padding
- Pad non-reuse enforcement by design
- Detection of accidental corruption
- Detection of message tampering or forgery
- Human-verifiable ceremony correctness
- Minimal attack surface

---

## User responsibility (important)

ASH requires users to:
- perform the ceremony carefully
- verify the mnemonic checksum
- avoid public or recorded environments
- understand that screenshots cannot be prevented
- trust conversation participants

ASH makes security *visible*, not automatic.

---

## Design consequences

This threat model explains why ASH:

- uses QR codes instead of Bluetooth
- avoids background syncing
- avoids convenience features
- avoids accounts and recovery
- avoids cloud storage
- avoids analytics

Every inconvenience is deliberate.

---

## Final note

ASH is designed to make **security tradeoffs explicit**.

If a threat is not listed here, it is **not defended against**.

Security is not a promise —  
it is a set of clearly defined limits.