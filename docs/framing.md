# ASH — Frame Format (v1)

This document defines the **frame format** used for QR code transfer during the ceremony.

This document must be read together with:
- `ceremony.md`
- `architecture.md`

---

## Purpose

Frames exist to:
- chunk large pad data into scannable QR codes
- provide integrity verification per chunk
- enable ordered reconstruction
- detect corruption or tampering

---

## Design constraints

Frames are designed with the following constraints:

1. **QR code capacity**
   - Binary mode QR codes have limited capacity
   - Version and error correction affect size
   - Target: reliable scanning on mobile devices

2. **Integrity**
   - Each frame must be independently verifiable
   - Corruption must be detectable

3. **Ordering**
   - Frames must be reassembled in correct order
   - Missing or duplicate frames must be detectable

4. **Simplicity**
   - Format must be trivial to implement
   - No compression or encoding complexity

---

## Frame structure

Each frame contains:

```
+------------------+------------------+------------------+------------------+
|   Frame Index    |   Total Frames   |   Payload        |   CRC            |
|   (2 bytes)      |   (2 bytes)      |   (N bytes)      |   (4 bytes)      |
+------------------+------------------+------------------+------------------+
```

### Field definitions

| Field | Size | Description |
|-------|------|-------------|
| Frame Index | 2 bytes | Zero-based index of this frame (big-endian) |
| Total Frames | 2 bytes | Total number of frames in sequence (big-endian) |
| Payload | Variable | Pad bytes for this chunk |
| CRC | 4 bytes | CRC-32 of preceding bytes (big-endian) |

---

## Frame constraints

### Size limits

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Max payload per frame | 1000 bytes | QR code capacity with margin |
| Min payload per frame | 1 byte | Edge case handling |
| Max total frames | 65535 | 2-byte index limit |

### Ordering

- Frame index starts at 0
- Frames must be sequential (0, 1, 2, ...)
- Gaps are not allowed
- Final frame index must equal (total frames - 1)

---

## CRC specification

- Algorithm: CRC-32 (ISO 3309, polynomial 0x04C11DB7)
- Input: all bytes preceding CRC field
- Output: 4 bytes, big-endian
- Purpose: detect accidental corruption

**Note:** CRC provides error detection, not authentication.
A malicious actor could forge valid CRCs.
Security relies on the ceremony being performed privately.

---

## QR code encoding

Frames are encoded as QR codes using:

| Parameter | Value |
|-----------|-------|
| Mode | Binary (byte mode) |
| Error correction | Level M (15% recovery) |
| Version | Auto (based on data size) |
| Encoding | Raw bytes (no base64) |

---

## Frame generation (sender)

1. Receive pad bytes from `ash-core`
2. Calculate number of frames needed
3. For each chunk:
   - Assign frame index
   - Set total frame count
   - Copy payload bytes
   - Compute CRC-32
   - Encode as QR code

### Pseudocode

```
function generate_frames(pad_bytes, max_payload_size):
    frames = []
    total = ceil(len(pad_bytes) / max_payload_size)

    for i in range(total):
        start = i * max_payload_size
        end = min(start + max_payload_size, len(pad_bytes))
        payload = pad_bytes[start:end]

        header = encode_u16_be(i) + encode_u16_be(total)
        crc = crc32(header + payload)

        frame = header + payload + encode_u32_be(crc)
        frames.append(frame)

    return frames
```

---

## Frame validation (receiver)

1. Decode QR code to raw bytes
2. Extract header (first 4 bytes)
3. Extract CRC (last 4 bytes)
4. Compute CRC of header + payload
5. Compare computed CRC with extracted CRC
6. Validate frame index and total frames
7. Store payload if valid

### Validation checks

| Check | Failure response |
|-------|------------------|
| CRC mismatch | Reject frame, allow retry |
| Frame too short | Reject frame |
| Index out of bounds | Reject frame |
| Total frames mismatch | Abort ceremony |
| Duplicate frame | Accept (idempotent) |

---

## Pad reconstruction

After all frames received:

1. Sort frames by index
2. Verify no gaps (0 to N-1 present)
3. Concatenate payloads in order
4. Pass reconstructed pad to `ash-core`

---

## Error handling

### Recoverable errors

- Single frame scan failure → retry scan
- Duplicate frame → ignore duplicate

### Non-recoverable errors

- CRC failure on retry → abort
- Missing frame after all displayed → abort
- Total frames changes mid-ceremony → abort

---

## Implementation notes

### For `ash-core`

- Provide frame chunking function
- Provide frame validation function
- Provide CRC-32 implementation
- Return clear error types

### For mobile apps

- Use platform QR libraries
- Handle camera focus and lighting
- Provide visual feedback per frame
- Track received frame indices
- Display progress (e.g., "3 of 12")

---

## Future considerations (out of scope for v1)

- Fountain codes for out-of-order scanning
- Animated QR codes for faster transfer
- Compression for larger pads

These are explicitly **not implemented in v1**.

---

## Final note

The frame format is intentionally simple.

Complexity in framing adds attack surface and implementation risk.

Any change to frame format requires:
- security review
- version negotiation strategy
- backwards compatibility plan
