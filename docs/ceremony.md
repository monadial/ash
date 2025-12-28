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
2. Both devices display checksum (e.g., 4-6 words)
3. Users verbally confirm checksums match
4. Both users explicitly confirm match in app

**Mnemonic wordlist:**
- Custom wordlist (not BIP-39)
- Optimized for verbal clarity
- Distinct pronunciation across words
- Minimal confusion between similar words

**Verification rules:**
- Checksum is deterministic from pad bytes
- Mismatch requires ceremony restart
- No "skip verification" option

---

### Phase 4: Activation

1. Both devices mark conversation as active
2. Pad is stored in secure storage
3. Conversation ID is generated
4. Ceremony state is cleared
5. Messaging becomes available

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

- Visual observation of QR codes
- Compromised devices
- Malicious participants
- Coerced participation

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

### Size options (v1 recommended)

| Size | Capacity | Frames | Transfer time |
|------|----------|--------|---------------|
| Small (64 KB) | ~50 short messages | ~65 frames | ~1-2 min |
| Medium (256 KB) | ~200 short messages | ~260 frames | ~4-5 min |
| Large (1 MB) | ~800 short messages | ~1000 frames | ~15-20 min |

**Notes:**
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
