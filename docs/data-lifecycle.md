# ASH — Data Lifecycle (v1)

This document defines the **lifecycle of all sensitive data** in ASH version 1.

Its purpose is to:
- make data lifetime explicit
- prevent accidental persistence
- guide implementation decisions
- support security review and auditing
- align with the threat model

If a piece of data is not documented here, it must be treated as **not allowed**.

---

## Core principle

ASH follows a single governing rule:

> **Data exists only as long as it is actively needed, and no longer.**

Persistence is the exception, not the default.

---

## Data categories

ASH handles a small number of clearly defined data categories:

1. Entropy
2. One-Time Pad (Pad material)
3. Plaintext messages
4. Encrypted blobs
5. Metadata
6. Device tokens
7. Logs and diagnostics

Each category has a distinct lifecycle.

---

## 1. Entropy

### Description
Raw unpredictable input used to generate the One-Time Pad.

Sources may include:
- OS-provided randomness
- user-generated entropy (e.g., touch gestures)

---

### Lifecycle
- Generated in memory only
- Mixed immediately into pad generation
- Never persisted
- Never reused
- Discarded immediately after pad creation

---

### Destruction
- Memory overwritten where possible
- References dropped immediately

---

### Notes
Entropy must never:
- be logged
- be serialized
- cross process boundaries
- be reused across ceremonies

---

## 2. One-Time Pad (Pad Material)

### Description
The shared random byte sequence used for OTP encryption and decryption.

---

### Lifecycle
- Created during ceremony
- Stored only on participating devices
- Never transmitted after ceremony
- Consumed sequentially
- Cannot be regenerated or recovered

---

### Storage
- Stored encrypted at rest on device (Keychain / secure storage)
- Loaded into memory only when needed
- Scoped per conversation

---

### Consumption
- Pad bytes are consumed strictly once
- Consumption is monotonic
- No rewinding, skipping, or reuse allowed

---

### Destruction
Pad material is destroyed when:
- fully consumed
- conversation is burned
- app is uninstalled
- device storage is wiped

Destruction is best-effort and irreversible by design.

---

## 3. Plaintext Messages

### Description
Decrypted message content displayed to the user.

---

### Lifecycle
- Exists only in memory
- Created only after successful decryption
- Displayed for a limited time
- Never persisted to disk

---

### Visibility
- Displayed only when conversation is open
- Removed automatically after:
  - read
  - timeout
  - backgrounding
  - burn

---

### Destruction
- Memory overwritten where possible
- References dropped immediately
- UI state cleared

---

### Notes
Plaintext messages must never:
- be written to disk
- be cached
- appear in logs
- be indexed
- be backed up

---

## 4. Encrypted Blobs

### Description
Ciphertext produced by OTP encryption.

---

### Lifecycle (Client)
- Created when sending a message
- Held briefly in memory
- Sent to backend
- Discarded after successful send

---

### Lifecycle (Backend)
- Stored ephemerally
- Associated with conversation ID
- TTL-limited
- Deleted automatically on expiry or burn

---

### Storage limits
- Size-limited per blob
- Count-limited per conversation

---

### Destruction
- Automatic TTL expiry
- Immediate deletion on burn

---

### Notes
Encrypted blobs:
- may be duplicated
- may be lost
- may arrive out of order
Clients must tolerate this.

---

## 5. Metadata

### Description
Non-content data required for routing or operation.

Examples:
- conversation ID
- cursors
- timestamps
- sequence numbers

---

### Lifecycle
- Stored only as long as required for operation
- TTL-limited on backend
- Scoped to a single conversation

---

### Restrictions
Metadata must:
- not encode identity
- not encode message content
- not enable long-term correlation

---

## 6. Device Tokens (Push Notifications)

### Description
Platform-specific tokens used for silent push notifications.

---

### Lifecycle
- Registered explicitly by the client
- Stored ephemerally on backend
- Associated with conversation only

---

### Storage
- TTL-limited
- Deleted on burn
- Deleted on expiry

---

### Restrictions
Device tokens must:
- not be reused across conversations
- not be logged
- not be treated as identity

---

## 7. Logs and Diagnostics

### Description
Operational data used for debugging and monitoring.

---

### Allowed
- Aggregate counters
- Error rates
- Latency histograms
- Health metrics

---

### Explicitly disallowed
Logs must never contain:
- plaintext messages
- encrypted blobs
- pad material
- entropy
- conversation IDs (in full)
- device tokens

---

### Retention
- Minimal retention
- No long-term storage
- No analytics pipelines

---

## Burn lifecycle (cross-cutting)

### Burn definition
Burn is the irreversible destruction of all conversation state.

---

### Effects of burn

On device:
- Pad material wiped
- Plaintext removed
- Encrypted blobs deleted
- UI state reset

On backend:
- Encrypted blobs deleted
- Burn flag set (TTL-limited)
- Device tokens removed

---

### Propagation
- Best-effort
- Delivered immediately if online
- Delivered on next connection if offline

---

## Failure and crash scenarios

ASH assumes crashes can happen.

Rules:
- Plaintext must not survive crashes
- Pad state must be consistent
- Partial writes must not lead to reuse
- On restart, conservative behavior is required

If uncertainty exists, the conversation must be invalidated.

---

## Backups and OS behavior

### iOS
- App data may be backed up by iCloud or iTunes
- Sensitive data must be stored with `kSecAttrAccessible` flags that exclude backup
- Keychain items must use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- No plaintext or pad material in standard app containers

---

### Platform requirements
The iOS app must:
- Exclude all sensitive data from backup
- Use Keychain for secure storage
- Fail safely if secure storage is unavailable

Note: Android requirements will be defined when Android support is added.

---

## Final note

Data lifecycle is a **security-critical** aspect of ASH.

If a data category is not listed here, it must not exist.

If a lifecycle is unclear, the conservative interpretation is:
> **Do not store it. Do not persist it. Delete it immediately.**