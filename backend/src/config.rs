//! Configuration for ASH backend server.
//!
//! Simplified ephemeral design - RAM-only storage with fixed 5-minute TTL.
//! All configuration is loaded from environment variables.
//! No secrets are logged.

use std::time::Duration;

/// Fixed message TTL in seconds (5 minutes)
pub const MESSAGE_TTL_SECS: u64 = 300;

/// Server configuration
#[derive(Debug, Clone)]
pub struct Config {
    /// Server bind address
    pub bind_addr: String,

    /// Server port
    pub port: u16,

    // === TTL Configuration ===
    /// Fixed TTL for encrypted message blobs (5 minutes)
    pub blob_ttl: Duration,

    /// TTL for burn flags (default: 5 minutes)
    pub burn_ttl: Duration,

    /// TTL for device tokens (default: 24 hours)
    pub device_token_ttl: Duration,

    // === Limits ===
    /// Maximum ciphertext size in bytes (default: 8KB)
    pub max_ciphertext_size: usize,

    /// Maximum queued blobs per conversation (default: 50)
    pub max_blobs_per_conversation: usize,

    /// TTL cleanup interval (default: 10 seconds)
    pub cleanup_interval: Duration,

    // === APNS Configuration ===
    /// APNS team ID
    pub apns_team_id: Option<String>,

    /// APNS key ID
    pub apns_key_id: Option<String>,

    /// Path to APNS private key (.p8 file)
    pub apns_key_path: Option<String>,

    /// APNS bundle ID (app identifier)
    pub apns_bundle_id: Option<String>,

    /// Use APNS sandbox (development) environment
    pub apns_sandbox: bool,
}

impl Config {
    /// Load configuration from environment variables
    pub fn from_env() -> Self {
        Self {
            bind_addr: std::env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0".to_string()),
            port: std::env::var("PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8080),

            // Fixed 5-minute TTL for all messages
            blob_ttl: Duration::from_secs(MESSAGE_TTL_SECS),
            burn_ttl: Duration::from_secs(
                std::env::var("BURN_TTL_SECS")
                    .ok()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(300), // 5 minutes
            ),
            device_token_ttl: Duration::from_secs(
                std::env::var("DEVICE_TOKEN_TTL_SECS")
                    .ok()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(24 * 3600), // 24 hours
            ),

            // Limits
            max_ciphertext_size: std::env::var("MAX_CIPHERTEXT_SIZE")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(8 * 1024), // 8KB
            max_blobs_per_conversation: std::env::var("MAX_BLOBS_PER_CONVERSATION")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(50),
            cleanup_interval: Duration::from_secs(
                std::env::var("CLEANUP_INTERVAL_SECS")
                    .ok()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(10),
            ),

            // APNS
            apns_team_id: std::env::var("APNS_TEAM_ID").ok(),
            apns_key_id: std::env::var("APNS_KEY_ID").ok(),
            apns_key_path: std::env::var("APNS_KEY_PATH").ok(),
            apns_bundle_id: std::env::var("APNS_BUNDLE_ID").ok(),
            apns_sandbox: std::env::var("APNS_SANDBOX")
                .map(|v| v == "true" || v == "1")
                .unwrap_or(true), // Default to sandbox for safety
        }
    }

    /// Check if APNS is configured
    pub fn apns_configured(&self) -> bool {
        self.apns_team_id.is_some()
            && self.apns_key_id.is_some()
            && self.apns_key_path.is_some()
            && self.apns_bundle_id.is_some()
    }
}

impl Default for Config {
    fn default() -> Self {
        Self::from_env()
    }
}
