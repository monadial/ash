# ASH — Architecture (v1)

This document describes the **system architecture** of ASH version 1.

Its purpose is to:
- define clear component boundaries
- document data and trust flows
- prevent architectural drift
- support security review and onboarding

This document must be read together with:
- `scope.md`
- `threat-model.md`

---

## Architectural goals

ASH is designed to achieve the following goals:

1. **Security through simplicity**
   - Fewer components, fewer assumptions.
2. **Explicit trust boundaries**
   - Every component has clearly defined responsibilities.
3. **Human-verifiable correctness**
   - Users can confirm critical steps themselves.
4. **Offline-first guarantees**
   - Security does not depend on network availability.
5. **Minimal infrastructure trust**
   - Backend compromise must not reveal message contents.

---

## System overview

ASH consists of four primary subsystems:

┌────────────┐
│   Users    │
└─────┬──────┘
      │
┌─────▼──────┐
│ iOS App    │  (SwiftUI)
└─────┬──────┘
      │  FFI boundary
┌─────▼──────┐
│ ash-core   │  (Shared Rust Core)
└─────┬──────┘
      │
┌─────▼──────┐
│ Backend    │  (Rust Relay)
└────────────┘

Each subsystem is intentionally constrained.

---

## Shared Rust Core (`ash-core`)

### Purpose

`ash-core` is the **cryptographic and procedural authority** of ASH.

All security-sensitive behavior is defined here.  
All other components must treat it as **authoritative**.

---

### Responsibilities

The shared core is responsible for:

- One-Time Pad (OTP) creation and management
- Enforcing strict pad single-use semantics
- OTP encryption and decryption
- Ceremony rules (chunk sizing, ordering, invariants)
- Frame encoding and decoding
- Frame integrity validation
- Mnemonic checksum generation
- Deterministic behavior across platforms
- Best-effort memory wiping

---

### Explicit non-responsibilities

`ash-core` must never:

- access the network
- perform file or database I/O
- access OS randomness directly
- contain platform-specific code
- store data persistently
- include UI logic
- log sensitive data
- make policy or UX decisions

---

### Design characteristics

- Small public API surface
- Minimal dependencies
- Deterministic outputs
- Extensive invariant tests
- Rare, deliberate changes

Once reviewed, changes to `ash-core` are expected to be exceptional.

---

## iOS Application (SwiftUI)

### Purpose

The iOS application is a **presentation and orchestration layer**.

It exists to:
- interact with the user
- manage UI state
- invoke `ash-core` correctly
- enforce UX constraints

---

### Responsibilities

The iOS app is responsible for:

- Rendering ceremony UI
- Displaying QR codes
- Scanning and validating QR frames
- Managing message display lifecycle
- Handling app foreground/background transitions
- Temporarily storing encrypted blobs
- Calling shared core APIs

---

### Explicit non-responsibilities

The iOS app must never:

- reimplement cryptographic logic
- alter OTP behavior
- bypass the shared core
- invent alternate checksums
- persist decrypted messages
- perform silent background actions

---

## Ceremony Architecture

### Purpose

The ceremony establishes a **shared One-Time Pad** between two devices.

It is:
- offline
- explicit
- human-verifiable
- restart-only on failure

---

### Ceremony flow

1. Sender gathers entropy
2. Sender constructs pad
3. Pad is chunked into frames
4. Frames are encoded and displayed as QR codes
5. Receiver scans frames
6. Frames are decoded and validated
7. Pad is reconstructed
8. Both devices compute mnemonic checksum
9. Users visually verify checksum
10. Conversation becomes active

---

### Failure handling

- Any error aborts the ceremony
- Partial state is discarded
- No recovery or resume is supported

This avoids ambiguous states.

---

## Messaging Architecture

### Overview

Messages are encrypted and decrypted using the shared pad.

There is **no key negotiation** after the ceremony.

---

### Sending a message

1. User composes message
2. App requests pad slice from `ash-core`
3. Message is OTP-encrypted
4. Pad bytes are consumed
5. Encrypted blob is sent to backend

---

### Receiving a message

1. Encrypted blob is received
2. App requests pad slice from `ash-core`
3. Blob is OTP-decrypted
4. Plaintext is displayed briefly
5. Plaintext is discarded

---

### Message lifecycle

- Plaintext exists only in memory
- Display duration is limited
- Messages are removed automatically
- Burn action wipes all remaining state

---

## Backend Architecture (Rust Relay)

### Purpose

The backend is a **stateless or ephemeral relay**.

It is intentionally simple and untrusted.

---

### Responsibilities

The backend is responsible for:

- Accepting encrypted message blobs
- Temporarily storing encrypted blobs
- Relaying encrypted blobs to recipients
- Propagating burn signals
- Sending silent push notifications (APNS)
- Enforcing TTL-based deletion

---

### Explicit non-responsibilities

The backend must never:

- decrypt messages
- inspect payload contents
- identify users
- authenticate identities
- store data long-term
- provide delivery guarantees
- implement business logic

---

## Infrastructure Architecture

### Characteristics

- Single region deployment (v1)
- HTTPS only
- No analytics
- No load balancing (initially)
- Manual deployments

Infrastructure is considered untrusted.

---

## Website Architecture

### Purpose

The website provides **documentation and education only**.

---

### Characteristics

- Static content only
- No user interaction
- No tracking or analytics
- No accounts
- HTTPS only

---

## Trust boundaries

| Component  | Trust level |
|-----------|-------------|
| ash-core  | Trusted |
| iOS App  | Partially trusted |
| Backend  | Untrusted |
| Network  | Untrusted |
| Website  | Untrusted |
| User     | Trusted (with responsibility) |

---

## Architectural consequences

This architecture deliberately avoids:

- background synchronization
- convenience features
- user accounts
- key recovery
- cloud storage
- analytics and tracking

All constraints are intentional.

---

## Final note

ASH’s architecture is intentionally **narrow and opinionated**.

Security emerges not from complexity,  
but from **clear boundaries, explicit flows, and deliberate limits**.

Any change that violates these principles  
must trigger architectural review before implementation.