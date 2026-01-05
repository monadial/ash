# ASH — Ceremony Protocol (v1)

This document defines the **ceremony protocol** for ASH version 1.

The ceremony is the process by which two devices establish a shared One-Time Pad.

This document must be read together with:
- `scope.md`
- `threat-model.md`
- `framing.md`
- `data-lifecycle.md`

---

## Purpose

The ceremony exists to:
- establish a shared secret between two devices
- do so without network involvement
- allow human verification of correctness
- prevent silent failures or partial states

---

## Core properties

The ceremony is:

1. **Offline**
   - No network communication during pad transfer
   - QR codes are the only transfer mechanism

2. **Explicit**
   - Every step requires deliberate user action
   - No automatic progression

3. **Human-verifiable**
   - Mnemonic checksum allows visual confirmation
   - Users can detect tampering or errors

4. **Atomic**
   - Either the ceremony completes fully, or it fails entirely
   - No partial states are persisted

---

## Roles

A ceremony involves exactly two participants:

### Sender (Initiator)
- Generates entropy
- Constructs the One-Time Pad
- Displays QR codes for transfer
- Displays mnemonic checksum for verification

### Receiver
- Scans QR codes from sender
- Reconstructs the pad from frames
- Computes and displays mnemonic checksum
- Confirms match with sender

---

## Ceremony flow

### Phase 0: Pad Size Selection (Sender)

Before entropy collection, the sender selects pad size:

1. User sees slider with pad size options
2. UI displays for each size:
   - Approximate message capacity
   - Estimated QR transfer duration
3. User confirms selection

See **Pad Sizing** section below for details.

---

### Phase 1: Entropy Collection (Sender)

1. User initiates new conversation
2. App collects entropy from multiple sources:
   - OS-provided randomness (primary)
   - User gesture input (required)
3. Gesture entropy collection:
   - User draws random patterns on screen
   - Touch coordinates, timing, and pressure are captured
   - Minimum gesture duration enforced
   - Visual feedback shows entropy accumulation
4. Entropy sources are mixed cryptographically
5. `core` generates One-Time Pad from mixed entropy
6. Pad is chunked into frames (see `framing.md`)
7. App displays "Ready to share" state

---

### Phase 2: Transfer

1. Sender displays first QR code frame
2. Receiver scans frame
3. Receiver validates frame integrity (CRC)
4. Receiver acknowledges scan (visual indicator)
5. Sender advances to next frame
6. Repeat until all frames transferred

**Transfer characteristics:**
- Frames must be scanned in order
- Duplicate scans are tolerated (idempotent)
- Missing frames cause ceremony failure
- No automatic frame advancement

---

### Phase 3: Verification

1. Both devices compute mnemonic checksum from pad
2. Both devices display checksum (6 words by default)
3. Users verbally confirm checksums match
4. Both users explicitly confirm match in app

**Mnemonic specification:**
- Custom 512-word wordlist (not BIP-39)
- 9 bits per word (512 = 2^9)
- 6 words = 54 bits of verification entropy
- Words are 3-7 characters, lowercase ASCII only
- Optimized for verbal clarity:
  - Distinct pronunciation across words
  - No homophones (e.g., no "night/knight")
  - Minimal confusion between similar words
  - Cross-language usability

**Verification rules:**
- Checksum is deterministic from pad bytes
- Mismatch requires ceremony restart
- No "skip verification" option

---

### Phase 3b: Settings Configuration (Sender)

Before verification, the sender configures conversation settings:

1. **Message TTL** - How long unread messages stay on server
   - 5 minutes (default, maximum ephemerality)
   - 1 hour
   - 24 hours
   - 7 days (maximum)

2. **Disappearing Messages** - How long messages display on screen
   - Off (persist until app closes)
   - 30 seconds
   - 1 minute
   - 5 minutes

These settings are encoded in ceremony metadata (frame 0).

---

### Phase 4: Activation

1. Both devices mark conversation as active
2. Pad is stored in secure storage
3. Authorization tokens derived from pad bytes
4. Client registers with backend (token hashes)
5. Ceremony state is cleared
6. Messaging becomes available

---

## Failure handling

### Failure modes

| Failure | Response |
|---------|----------|
| Frame scan error | Retry scan |
| Frame integrity failure | Abort ceremony |
| Incomplete transfer | Abort ceremony |
| Checksum mismatch | Abort ceremony |
| App backgrounded during ceremony | Abort ceremony |
| Timeout exceeded | Abort ceremony |

### Abort behavior

On any abort:
- All partial state is discarded
- No pad material is persisted
- User is returned to initial state
- Ceremony must restart from beginning

---

## Timeouts

Ceremonies have time limits to prevent stale state:

| Phase | Recommended timeout |
|-------|---------------------|
| Frame display idle | 5 minutes |
| Total ceremony duration | 15 minutes |
| Verification confirmation | 5 minutes |

Timeouts are enforced by the app, not `ash-core`.

---

## Security considerations

### What the ceremony protects against

- Network eavesdropping (offline transfer)
- Backend compromise (pad never touches network)
- Man-in-the-middle (human verification)
- Accidental corruption (integrity checks)

### What the ceremony does NOT protect against

- Visual observation of QR codes (mitigated by optional passphrase)
- Compromised devices
- Malicious participants
- Coerced participation

---

## Optional passphrase protection

QR frame payloads can optionally be encrypted with a verbally-shared passphrase.

### Purpose

- Protects against casual visual observation (shoulder-surfing)
- Adds additional layer beyond physical proximity
- **NOT** a replacement for performing the ceremony privately

### How it works

1. Before ceremony, participants verbally agree on a passphrase
2. Sender enters passphrase before generating QR codes
3. Frame payloads are XOR'd with a derived key stream
4. Frame headers (index, total) remain unencrypted for progress tracking
5. Receiver enters same passphrase to decrypt frames

### Passphrase requirements

- 4-64 printable ASCII characters
- Should be spoken, not typed from shared source
- Should be memorable but unpredictable
- Different passphrases per frame index (prevents replay)

### Security note

Passphrase encryption uses simple XOR with CRC-32 chaining for key expansion.
This is designed for convenience against casual observation, not cryptographic security.
The ceremony should still be performed in a private setting.

---

## UX requirements

The ceremony UI must:
- Clearly indicate current phase
- Show progress through frames
- Display errors prominently
- Prevent accidental dismissal
- Support accessibility (VoiceOver)
- Work in various lighting conditions

---

## Implementation notes

### For `ash-core`

- Provide frame generation API
- Provide frame validation API
- Provide mnemonic generation API
- Enforce frame ordering
- Reject invalid frames

### For mobile apps

- Handle camera permissions
- Manage QR scanning lifecycle
- Display frames at appropriate size
- Handle app lifecycle interruptions
- Persist nothing until ceremony completes

---

## Pad sizing

### Overview

Pad size determines:
- How many messages can be exchanged
- How long the QR transfer takes

Users select pad size before entropy collection via a slider.

---

### Size options (v1)

| Size | Bytes | Capacity | Frames (~900B payload) | Transfer time |
|------|-------|----------|------------------------|---------------|
| Tiny (32 KB) | 32,768 | ~25 short messages | ~37 frames | ~30-45 sec |
| Small (64 KB) | 65,536 | ~50 short messages | ~74 frames | ~1-2 min |
| Medium (256 KB) | 262,144 | ~200 short messages | ~295 frames | ~5 min |
| Large (512 KB) | 524,288 | ~400 short messages | ~590 frames | ~10 min |
| Huge (1 MB) | 1,048,576 | ~800 short messages | ~1179 frames | ~20 min |

**Notes:**
- Frame counts include 1 metadata frame + data frames
- Frame counts assume ~890 byte effective payload (900 max - 10 byte overhead)
- Capacity assumes average message size of ~1 KB (text + overhead)
- Transfer time assumes ~1 second per frame scan
- Location messages consume more pad bytes than text

---

### UI guidance

The pad size selector should display:
- Human-readable size label
- Approximate message count
- Estimated transfer duration
- Clear indication that larger = longer ceremony

Example UI text:
> "Medium (256 KB): About 200 messages. Transfer takes ~5 minutes."

---

### Trade-offs

| Smaller pad | Larger pad |
|-------------|------------|
| Faster ceremony | Slower ceremony |
| Fewer messages | More messages |
| More frequent re-ceremony | Less frequent re-ceremony |
| Lower visual exposure risk | Higher visual exposure risk |

---

## Final note

The ceremony is the **foundation of ASH's security model**.

A compromised ceremony means a compromised conversation.

Every ceremony step exists for a reason.
Removing or bypassing steps is not allowed.
