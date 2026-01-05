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

## Message Mode: Ephemeral Only

ASH has a **single message mode**: ephemeral.

There is no "persistent" mode. This is intentional:
- Simplicity reduces attack surface
- High-security users shouldn't want message history
- If you need history, ASH is not the right tool

### Server TTL (Configurable)

Message TTL on the server is **configurable during ceremony**:

| Setting | Default | Range | Notes |
|---------|---------|-------|-------|
| Message TTL | 5 minutes | 5 min – 7 days | Set during ceremony |
| Burn flag TTL | 5 minutes | Fixed | Allows late clients to learn of burn |
| Device token TTL | 24 hours | Fixed | Must re-register periodically |
| Auth tokens | Until restart | N/A | Lost on server restart |

**TTL options (configured at ceremony):**

| Option | Duration | Use Case |
|--------|----------|----------|
| 5 minutes | 300s | Maximum ephemerality (default) |
| 1 hour | 3,600s | Short conversations |
| 24 hours | 86,400s | Async communication |
| 7 days | 604,800s | Maximum (for busy schedules) |

**Important warnings:**
- Server restart = all unread messages AND auth tokens lost
- Messages not ACKed within TTL are deleted
- Clients must re-register after server restart

### Server Restart Handling

When the server restarts, **all RAM data is lost**:

| Data | Effect | Client Action |
|------|--------|---------------|
| Unread messages | Lost permanently | User is warned at ceremony |
| Auth token hashes | Lost | Must re-register conversation |
| Burn token hashes | Lost | Must re-register conversation |
| Device tokens | Lost | Must re-register device |
| Burn flags | Lost | Conversation appears active |

**Re-registration flow:**

```
Client                          Server (after restart)
  │                                    │
  │  POST /v1/messages                 │
  │  Authorization: Bearer <auth_token>│
  ├───────────────────────────────────►│
  │◄─── 404 NOT_FOUND ─────────────────│
  │     {"error": "Conversation not registered",
  │      "code": "CONVERSATION_NOT_FOUND"}│
  │                                    │
  │  ┌─────────────────────────────────┤
  │  │ Step 1: Re-register conversation│
  │  └─────────────────────────────────┤
  │  POST /v1/conversations            │
  │  {                                 │
  │    "conversation_id": "...",       │
  │    "auth_token_hash": "sha256(auth_token)",
  │    "burn_token_hash": "sha256(burn_token)"
  │  }                                 │
  ├───────────────────────────────────►│
  │◄─── 200 OK ────────────────────────│
  │                                    │
  │  ┌─────────────────────────────────┤
  │  │ Step 2: Re-register device      │
  │  └─────────────────────────────────┤
  │  POST /v1/register                 │
  │  Authorization: Bearer <auth_token>│
  │  {                                 │
  │    "conversation_id": "...",       │
  │    "device_token": "<apns_token>", │
  │    "platform": "ios"               │
  │  }                                 │
  ├───────────────────────────────────►│
  │◄─── 200 OK ────────────────────────│
  │                                    │
  │  (retry original request)          │
  │                                    │
```

**What gets re-registered:**

| Endpoint | Data | Purpose |
|----------|------|---------|
| `POST /v1/conversations` | auth_token_hash, burn_token_hash | API authentication + burn capability |
| `POST /v1/register` | device_token, platform | Push notifications (APNS) |

**Client responsibilities:**
- Detect "conversation not found" errors (HTTP 404)
- Re-register conversation with **both** auth and burn token hashes
- Re-register device for push notifications
- Retry failed requests after re-registration
- Can re-register proactively on app launch (idempotent)

**Why no persistence?**
- Auth token hashes could be persisted to disk
- Intentionally not done for maximum security
- Server restart = clean slate
- Acceptable tradeoff for high-security use case

---

### Disappearing Messages (Client-side)

Separate from server TTL, clients can configure how long messages display on screen:

| Option | Duration | Effect |
|--------|----------|--------|
| Off | 0 | Messages visible until app closes |
| 30 seconds | 30s | Message disappears after viewing |
| 1 minute | 60s | Message disappears after viewing |
| 5 minutes | 300s | Message disappears after viewing |

This is configured during ceremony and stored in ceremony metadata.

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
- **Wiped when app closes** (no local persistence)

---

### Lifecycle (Backend) - RAM Only

```
Message arrives → stored in RAM → held until ACK or TTL
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
              Client ACK           TTL expires         Server restart
            (msg displayed)        (5 min)
                    │                    │                    │
                    ▼                    ▼                    ▼
               DELETE              DELETE                 LOST
         + delivery report
           via SSE
```

**Key behaviors:**
- Stored in RAM only (no disk persistence)
- Associated with conversation ID
- Deleted immediately when client ACKs (message displayed)
- Fallback: 5-minute TTL if no ACK received
- Real-time delivery via SSE to connected clients
- Delivery reports broadcast to sender when ACK received
- Polling fallback for disconnected clients
- **Server restart = all unread messages lost** (users warned at ceremony)
- Background cleanup runs every 10 seconds

---

### Storage limits
- Size-limited per blob
- Count-limited per conversation
- Limited by server RAM

---

### Destruction triggers
1. **Client ACK** - message displayed on recipient's screen (immediate deletion + delivery report)
2. **TTL expiry** - message stored for 5 minutes without ACK (automatic cleanup)
3. **Burn signal** - conversation burned (immediate deletion of all messages)
4. **Server restart** - all RAM cleared (data lost)

---

### Notes
Encrypted blobs:
- may be duplicated
- may be lost (especially on server restart)
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