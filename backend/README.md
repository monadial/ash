# ASH Backend

Minimal untrusted message relay server for ASH secure messaging.

## Design Principles

- **No plaintext** - Backend never receives, stores, or emits plaintext message content
- **No identity** - No user accounts, usernames, phone numbers, or profiles
- **No long-term storage** - All data is TTL-expired automatically
- **Best-effort delivery** - Loss, delay, and duplication are acceptable
- **Minimal logging** - No ciphertext, conversation IDs, or device tokens in logs

## API Endpoints

### Health Check
```
GET /health
```
Returns server status and version.

### Register Device (Push Notifications)
```
POST /v1/register
Content-Type: application/json

{
  "conversation_id": "uuid",
  "device_token": "apns-token",
  "platform": "ios"  // optional, default: "ios"
}
```

### Submit Message
```
POST /v1/messages
Content-Type: application/json

{
  "conversation_id": "uuid",
  "ciphertext": "base64-encoded-ciphertext",
  "sequence": 1,  // optional
  "extended_ttl": false  // optional, for delayed reading
}
```

### Poll Messages
```
GET /v1/messages?conversation_id=uuid&cursor=optional-cursor
```

### Burn Conversation
```
POST /v1/burn
Content-Type: application/json

{
  "conversation_id": "uuid"
}
```

### Check Burn Status
```
GET /v1/burn?conversation_id=uuid
```

## Configuration

Set via environment variables (or `.env` file):

| Variable | Default | Description |
|----------|---------|-------------|
| `BIND_ADDR` | `0.0.0.0` | Server bind address |
| `PORT` | `8080` | Server port |
| `BLOB_TTL_SECS` | `30` | Message blob TTL |
| `BLOB_EXTENDED_TTL_SECS` | `172800` | Extended TTL (48 hours) |
| `BURN_TTL_SECS` | `300` | Burn flag TTL |
| `DEVICE_TOKEN_TTL_SECS` | `86400` | Device token TTL |
| `MAX_CIPHERTEXT_SIZE` | `8192` | Max message size (8KB) |
| `MAX_BLOBS_PER_CONVERSATION` | `50` | Max queued messages |

### APNS Configuration (Optional)

| Variable | Description |
|----------|-------------|
| `APNS_TEAM_ID` | Apple Developer Team ID |
| `APNS_KEY_ID` | APNS Key ID |
| `APNS_KEY_PATH` | Path to AuthKey.p8 file |
| `APNS_BUNDLE_ID` | App bundle identifier |
| `APNS_SANDBOX` | Use sandbox environment (default: true) |

## Running

```bash
# Development
cargo run

# Production
cargo build --release
./target/release/ash-backend
```

## Docker

```dockerfile
FROM rust:1.75-slim as builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
COPY --from=builder /app/target/release/ash-backend /usr/local/bin/
EXPOSE 8080
CMD ["ash-backend"]
```

## Security Notes

- All endpoints require HTTPS in production (TLS termination at load balancer)
- No authentication required - access is based on possession of conversation ID
- Rate limiting should be configured at the infrastructure level
- No ciphertext or PII is logged
