# ASH — v1 Scope Definition

This document defines the **explicit scope** of ASH version 1.

Its purpose is to:
- prevent scope creep
- preserve security guarantees
- align contributors (human or AI)
- act as a reference during reviews and decisions

If something is **not listed here**, it is **out of scope**.

---

## What ASH *is*

ASH is a secure, ephemeral messaging application designed for **high-security, low-frequency communication**.

ASH prioritizes:
- correctness over convenience
- human-verifiable security
- minimal trust in infrastructure
- deliberate user actions
- clarity over speed

ASH is **not** designed for everyday chat.

---

## Core principles (non-negotiable)

- One-Time Pad (OTP) only  
- No key escrow  
- No key recovery  
- No crypto agility  
- No silent background behavior  
- No hidden persistence  
- No reliance on backend trust  

If any feature weakens these principles, it is out of scope.

---

## In scope for v1

### Shared Rust Core (`ash-core`)

The shared Rust core is the **single source of truth** for ASH’s security model.

It is used by:
- the iOS application
- the backend (where applicable)
- tests and verification tools

The shared core is responsible for:
- One-Time Pad generation and consumption
- Strict enforcement of pad non-reuse
- OTP encryption and decryption
- Ceremony rules (chunking, ordering, invariants)
- Frame encoding and decoding with integrity checks
- Human-verifiable mnemonic checksum generation
- Deterministic, testable behavior across platforms
- Best-effort memory wipe utilities

The shared core must **never**:
- access the network
- access OS randomness directly
- store data on disk
- contain UI logic
- contain platform-specific code
- make policy decisions
- include analytics or logging

The shared core must remain:
- small
- auditable
- deterministic
- stable once reviewed

---

### Ceremony (conversation creation)

- Offline device-to-device ceremony
- QR code–based transfer of random pad bytes
- Chunked frame transfer with integrity validation
- Human-verifiable mnemonic checksum
- Restart-only failure handling (no partial recovery)

The ceremony must:
- be explicit
- be visible to the user
- require deliberate participation

---

### Messaging

- One-to-one conversations only
- Text messages
- One-shot location messages
- Ephemeral message lifecycle
- Automatic message disappearance after read / time
- Manual “burn” action that irreversibly wipes conversation state

---

### iOS Application (SwiftUI)

- SwiftUI-based iOS application
- Thin orchestration layer around shared Rust core
- Clear, minimal UI
- Limited visible message history
- Dynamic Type and accessibility support
- Reduced motion support
- Explicit user actions (no background automation)

The iOS app must **never**:
- reimplement cryptography
- modify security logic
- bypass the shared core
- invent alternative checksums or encryption
- silently persist decrypted data

---

### Backend (Rust relay)

The backend is a **dumb relay with a clock**.

It exists only to:
- relay encrypted message blobs
- relay burn signals
- notify devices via silent push notifications

The backend:
- does not decrypt data
- does not understand message contents
- does not identify users
- does not authenticate identities
- does not store data long-term

Backend characteristics:
- implemented in Rust
- stateless or ephemeral storage only
- strict TTL-based cleanup
- HTTPS only
- minimal API surface

The backend must **never**:
- store plaintext
- perform cryptographic operations on messages
- enforce business logic
- track users or behavior
- provide guarantees beyond best-effort delivery

---

### Website

- Static website only
- Educational and explanatory content
- Explanation of ceremony and security model
- Ethical use statement
- Privacy posture
- No analytics
- No tracking
- No user accounts
- No interactivity beyond simple demos

---

## Explicitly out of scope for v1

### Messaging & social features
- Group chats
- Channels
- Threads
- Reactions
- Media messages (images, video, audio)
- Stickers, emojis beyond system defaults

---

### Accounts & identity
- User accounts
- Phone number registration
- Email login
- Contacts integration
- Identity recovery
- Username systems

---

### Cryptography & transport
- End-to-end encryption other than OTP
- Key exchange protocols
- Key derivation functions
- Cloud key storage
- Bluetooth-based pairing
- Wi-Fi Direct pairing
- Background syncing

---

### Platform & ecosystem
- Android application
- Web application
- Desktop application
- VisionOS / watchOS support
- External plugins
- SDKs for third parties

---

### Infrastructure & scale
- Multi-region backend
- High availability guarantees
- Load balancing
- Analytics pipelines
- Crash reporting SDKs
- User metrics or tracking

---

### Product & business
- Monetization
- Subscriptions
- Ads
- Growth features
- Marketing campaigns
- Virality mechanics

---

## Non-goals (important clarification)

ASH does **not** aim to:
- be convenient
- be fast
- be social
- be anonymous at the network level
- defeat a compromised operating system
- defeat a physically compromised device
- provide plausible deniability against a determined forensic adversary

ASH aims to:
> reduce attack surface, reduce mistakes, and make security properties understandable to humans.

---

## Change policy

- This document may only be changed deliberately.
- Any change requires:
  - a written rationale
  - explicit acknowledgment of tradeoffs
  - review of security impact

Silent scope expansion is not allowed.

---

## Final note

If a future feature conflicts with this document,  
**this document wins**.

ASH succeeds by doing **less**, not more.