# Persistent Messages

This document describes the **optional persistent message storage** feature in ASH and its security implications.

---

## Overview

By default, ASH messages are **ephemeral** — they exist only in memory and are never written to disk. This provides the strongest forward secrecy guarantees.

The **persistent messages** feature is an **opt-in** setting configured during the ceremony that allows messages to be stored locally as encrypted blobs. This enables asynchronous messaging but introduces trade-offs.

---

## How It Works

### Local Storage (iOS)

When enabled:
- Messages are stored in SwiftData (SQLite-backed) in the app's container
- Messages are stored as **encrypted blobs** — never plaintext
- Storage is automatically deleted when:
  - The conversation is burned
  - The app is uninstalled (iOS default behavior)

### Backend Retention

When persistent mode is enabled:
- Undelivered messages are held on the relay server for up to **7 days**
- After 7 days, messages are automatically purged
- This is shown in the UI during ceremony configuration

---

## Security Implications

### What Changes

| Aspect | Ephemeral Mode | Persistent Mode |
|--------|----------------|-----------------|
| Message lifetime | In-memory only | Stored on disk |
| Forward secrecy | Strongest | Reduced |
| Attack surface | Minimal | Larger |
| Offline access | None | Possible |
| Backend retention | 48h max | 7 days max |

### Trade-offs

**Advantages of persistent mode:**
- Messages survive app restarts
- Supports truly asynchronous communication
- Messages available even if recipient is offline for days

**Disadvantages of persistent mode:**
- Encrypted blobs on disk can be forensically recovered
- Device compromise exposes message history
- Longer backend retention window
- Slightly larger attack surface

### Key Material Security

Even with persistent messages enabled:
- **Pad (key material) remains in Keychain only** — never written to disk outside secure enclave
- Messages are stored as ciphertext — without the pad, they are unreadable
- Burning still destroys the pad immediately, making stored blobs irrecoverable

---

## User Guidance

### When to use persistent mode

Consider enabling if:
- You and your contact have different schedules
- Network connectivity is unreliable
- You need message history within a session

### When to avoid persistent mode

Keep ephemeral (default) if:
- You prioritize forward secrecy above convenience
- Device compromise is a significant threat
- You're in a high-risk environment

---

## Technical Details

### iOS Implementation

- **Storage**: SwiftData with `ModelContainer` (no CloudKit sync)
- **Location**: App's Documents directory (deleted with app)
- **Model**: `PersistedMessage` stores encrypted content as `Data`
- **Repository**: `SwiftDataMessageRepository` implements `MessageRepository`

### Backend Implementation

- **Config**: `BLOB_PERSISTENT_TTL_SECS` defaults to 604800 (7 days)
- **Flag**: `persistent: true` in submit message request
- **Behavior**: Overrides `extended_ttl` for maximum retention

---

## Security Guarantees

What is **preserved** in persistent mode:
- OTP encryption (mathematically unbreakable)
- Key material never leaves Keychain
- Burn destroys pad making recovery impossible
- No plaintext ever touches disk

What is **reduced** in persistent mode:
- Forward secrecy (historical messages recoverable until pad is burned)
- Plausible deniability (encrypted blobs exist)
- Time window for attacks (7 days vs 48 hours)

---

## Recommendations

1. **Choose at ceremony time** — the setting is per-conversation and immutable
2. **Both parties see the same setting** — it's agreed upon during key exchange
3. **Consider your threat model** — ephemeral is more secure, persistent is more convenient
4. **Burn when done** — destroying the conversation destroys all stored messages
