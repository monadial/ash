//! Data models for ASH backend.
//!
//! All models are designed for ephemeral storage with TTL.
//! No user identity or plaintext content is ever stored.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Conversation identifier (opaque to backend)
/// Base64-encoded string derived from shared secret
pub type ConversationId = String;

/// Message sequence number for ordering
pub type SequenceNumber = u64;

/// Encrypted message blob stored temporarily
#[derive(Debug, Clone)]
pub struct StoredBlob {
    /// Unique blob ID for deduplication
    pub id: Uuid,

    /// Client-provided sequence number (optional)
    pub sequence: Option<SequenceNumber>,

    /// Encrypted ciphertext (opaque to backend)
    pub ciphertext: Vec<u8>,

    /// When the blob was received
    pub received_at: DateTime<Utc>,

    /// When the blob expires
    pub expires_at: DateTime<Utc>,
}

/// Registered device for push notifications
#[derive(Debug, Clone)]
pub struct DeviceRegistration {
    /// APNS device token
    pub device_token: String,

    /// Platform (ios, macos)
    pub platform: Platform,

    /// When the registration was created
    pub registered_at: DateTime<Utc>,

    /// When the registration expires
    pub expires_at: DateTime<Utc>,
}

/// Supported platforms for push notifications
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum Platform {
    #[default]
    Ios,
    Macos,
}

/// Burn flag for a conversation
#[derive(Debug, Clone)]
pub struct BurnFlag {
    /// When the burn was initiated
    pub burned_at: DateTime<Utc>,

    /// When the burn flag expires
    pub expires_at: DateTime<Utc>,
}

/// Cursor for pagination
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cursor {
    /// Last seen blob ID
    pub last_id: Option<Uuid>,

    /// Last seen sequence number
    pub last_sequence: Option<SequenceNumber>,

    /// Timestamp for time-based cursors
    pub since: Option<DateTime<Utc>>,
}

impl Cursor {
    pub fn empty() -> Self {
        Self {
            last_id: None,
            last_sequence: None,
            since: None,
        }
    }

    /// Encode cursor to base64 string
    pub fn encode(&self) -> String {
        let json = serde_json::to_string(self).unwrap_or_default();
        base64::Engine::encode(&base64::engine::general_purpose::URL_SAFE_NO_PAD, json)
    }

    /// Decode cursor from base64 string
    pub fn decode(s: &str) -> Option<Self> {
        let bytes = base64::Engine::decode(&base64::engine::general_purpose::URL_SAFE_NO_PAD, s).ok()?;
        serde_json::from_slice(&bytes).ok()
    }
}

// === API Request/Response Models ===

/// Register conversation request (first step after ceremony)
/// Both parties call this to register their tokens
#[derive(Debug, Deserialize)]
pub struct RegisterConversationRequest {
    /// Conversation ID (derived from pad, hex-encoded)
    pub conversation_id: ConversationId,
    /// SHA-256 hash of auth token (hex-encoded, 64 chars)
    pub auth_token_hash: String,
    /// SHA-256 hash of burn token (hex-encoded, 64 chars)
    pub burn_token_hash: String,
}

/// Register conversation response
#[derive(Debug, Serialize)]
pub struct RegisterConversationResponse {
    pub success: bool,
}

/// Register device request
#[derive(Debug, Deserialize)]
pub struct RegisterDeviceRequest {
    pub conversation_id: ConversationId,
    pub device_token: String,
    #[serde(default)]
    pub platform: Platform,
}

/// Register device response
#[derive(Debug, Serialize)]
pub struct RegisterDeviceResponse {
    pub success: bool,
}

/// Submit message request
///
/// Simplified ephemeral design - fixed 5-minute TTL.
/// Messages are stored in RAM only and deleted on ACK or expiry.
#[derive(Debug, Deserialize)]
pub struct SubmitMessageRequest {
    pub conversation_id: ConversationId,
    /// Base64-encoded ciphertext
    pub ciphertext: String,
    /// Optional client sequence number
    pub sequence: Option<SequenceNumber>,
}

/// Submit message response
#[derive(Debug, Serialize)]
pub struct SubmitMessageResponse {
    pub accepted: bool,
    pub blob_id: Uuid,
}

/// Poll messages request (query params)
#[derive(Debug, Deserialize)]
pub struct PollMessagesQuery {
    pub conversation_id: ConversationId,
    /// Cursor for pagination (base64 encoded)
    pub cursor: Option<String>,
}

/// Poll messages response
#[derive(Debug, Serialize)]
pub struct PollMessagesResponse {
    pub messages: Vec<MessageBlob>,
    /// Next cursor for pagination (base64 encoded)
    pub next_cursor: Option<String>,
    /// Whether the conversation has been burned
    pub burned: bool,
}

/// Message blob in poll response
#[derive(Debug, Clone, Serialize)]
pub struct MessageBlob {
    pub id: Uuid,
    pub sequence: Option<SequenceNumber>,
    /// Base64-encoded ciphertext
    pub ciphertext: String,
    pub received_at: DateTime<Utc>,
}

/// Burn conversation request
#[derive(Debug, Deserialize)]
pub struct BurnConversationRequest {
    pub conversation_id: ConversationId,
}

/// Burn conversation response
#[derive(Debug, Serialize)]
pub struct BurnConversationResponse {
    pub accepted: bool,
}

/// Burn status query (query params)
#[derive(Debug, Deserialize)]
pub struct BurnStatusQuery {
    pub conversation_id: ConversationId,
}

/// Burn status response
#[derive(Debug, Serialize)]
pub struct BurnStatusResponse {
    pub burned: bool,
    pub burned_at: Option<DateTime<Utc>>,
}

/// Health check response
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
    pub version: &'static str,
}

/// Error response
#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub error: String,
    pub code: &'static str,
}

// === SSE Event Models ===

/// SSE stream query parameters
#[derive(Debug, Deserialize)]
pub struct StreamQuery {
    pub conversation_id: ConversationId,
}

/// Event sent over SSE stream
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum StreamEvent {
    /// New message received
    Message(MessageBlob),
    /// Conversation has been burned
    Burned {
        burned_at: DateTime<Utc>,
    },
    /// Keep-alive ping
    Ping,
}

/// Internal broadcast event (conversation_id + event)
#[derive(Debug, Clone)]
pub struct BroadcastEvent {
    pub conversation_id: ConversationId,
    pub event: StreamEvent,
}
