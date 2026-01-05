//! In-memory ephemeral store with TTL-based cleanup.
//!
//! All data is automatically deleted when TTL expires.
//! No persistence - data is lost on restart (by design).

use crate::config::Config;
use crate::models::*;
use chrono::Utc;
use dashmap::DashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info};
use uuid::Uuid;

/// Thread-safe in-memory store
#[derive(Clone)]
pub struct Store {
    /// Encrypted blobs per conversation
    blobs: Arc<DashMap<ConversationId, Vec<StoredBlob>>>,

    /// Burn flags per conversation
    burns: Arc<DashMap<ConversationId, BurnFlag>>,

    /// Device registrations per conversation
    devices: Arc<DashMap<ConversationId, Vec<DeviceRegistration>>>,

    /// Configuration
    config: Arc<Config>,

    /// Metrics (aggregate only, no PII)
    metrics: Arc<RwLock<StoreMetrics>>,
}

/// Aggregate metrics (no PII, no per-conversation data)
#[derive(Debug, Default)]
pub struct StoreMetrics {
    pub total_blobs_stored: u64,
    pub total_blobs_expired: u64,
    pub total_burns: u64,
    pub total_registrations: u64,
}

impl Store {
    /// Create a new empty store
    pub fn new(config: Config) -> Self {
        Self {
            blobs: Arc::new(DashMap::new()),
            burns: Arc::new(DashMap::new()),
            devices: Arc::new(DashMap::new()),
            config: Arc::new(config),
            metrics: Arc::new(RwLock::new(StoreMetrics::default())),
        }
    }

    /// Start background TTL cleanup task
    pub fn start_cleanup_task(self: Arc<Self>) {
        let store = self.clone();
        let interval = self.config.cleanup_interval;

        tokio::spawn(async move {
            let mut ticker = tokio::time::interval(interval);
            loop {
                ticker.tick().await;
                store.cleanup_expired().await;
            }
        });

        info!(
            interval_secs = interval.as_secs(),
            "Started TTL cleanup task"
        );
    }

    /// Store an encrypted blob for a conversation
    ///
    /// Uses fixed 5-minute TTL. Messages are deleted on expiry or ACK.
    pub async fn store_blob(
        &self,
        conversation_id: ConversationId,
        ciphertext: Vec<u8>,
        sequence: Option<SequenceNumber>,
    ) -> Result<Uuid, StoreError> {
        // Check if conversation is burned
        if self.is_burned(&conversation_id) {
            return Err(StoreError::ConversationBurned);
        }

        // Check ciphertext size
        if ciphertext.len() > self.config.max_ciphertext_size {
            return Err(StoreError::PayloadTooLarge);
        }

        let now = Utc::now();
        let ttl = self.config.blob_ttl;

        let blob = StoredBlob {
            id: Uuid::new_v4(),
            sequence,
            ciphertext,
            received_at: now,
            expires_at: now + chrono::Duration::from_std(ttl).unwrap(),
        };

        let blob_id = blob.id;

        // Store blob
        let mut entry = self.blobs.entry(conversation_id).or_default();
        let blobs = entry.value_mut();

        // Enforce max blobs limit
        if blobs.len() >= self.config.max_blobs_per_conversation {
            return Err(StoreError::QueueFull);
        }

        blobs.push(blob);

        // Update metrics
        {
            let mut metrics = self.metrics.write().await;
            metrics.total_blobs_stored += 1;
        }

        debug!(
            blob_id = %blob_id,
            ttl_secs = ttl.as_secs(),
            "Stored blob"
        );

        Ok(blob_id)
    }

    /// Get blobs for a conversation since a cursor
    pub fn get_blobs(
        &self,
        conversation_id: &ConversationId,
        cursor: Option<&Cursor>,
    ) -> (Vec<StoredBlob>, Option<Cursor>) {
        let now = Utc::now();

        // Check burn status
        let burned = self.is_burned(conversation_id);
        if burned {
            return (vec![], None);
        }

        let blobs = self.blobs.get(conversation_id);
        let blobs = match blobs {
            Some(ref entry) => entry.value(),
            None => return (vec![], None),
        };

        // Filter expired and apply cursor
        let filtered: Vec<StoredBlob> = blobs
            .iter()
            .filter(|b| b.expires_at > now)
            .filter(|b| {
                if let Some(cursor) = cursor {
                    if let Some(last_id) = cursor.last_id {
                        return b.id != last_id; // Skip if same as last seen
                    }
                    if let Some(since) = cursor.since {
                        return b.received_at > since;
                    }
                }
                true
            })
            .cloned()
            .collect();

        // Generate next cursor
        let next_cursor = filtered.last().map(|b| Cursor {
            last_id: Some(b.id),
            last_sequence: b.sequence,
            since: Some(b.received_at),
        });

        (filtered, next_cursor)
    }

    /// Register a device for push notifications
    pub async fn register_device(
        &self,
        conversation_id: ConversationId,
        device_token: String,
        platform: Platform,
    ) -> Result<(), StoreError> {
        // Check if conversation is burned
        if self.is_burned(&conversation_id) {
            return Err(StoreError::ConversationBurned);
        }

        let now = Utc::now();
        let expires_at = now
            + chrono::Duration::from_std(self.config.device_token_ttl).unwrap();

        let registration = DeviceRegistration {
            device_token: device_token.clone(),
            platform,
            registered_at: now,
            expires_at,
        };

        let mut entry = self.devices.entry(conversation_id).or_default();
        let devices = entry.value_mut();

        // Remove existing registration with same token (refresh)
        devices.retain(|d| d.device_token != device_token);

        // Add new registration
        devices.push(registration);

        // Update metrics
        {
            let mut metrics = self.metrics.write().await;
            metrics.total_registrations += 1;
        }

        debug!("Registered device for push notifications");

        Ok(())
    }

    /// Get device tokens for a conversation
    pub fn get_device_tokens(&self, conversation_id: &ConversationId) -> Vec<DeviceRegistration> {
        let now = Utc::now();

        self.devices
            .get(conversation_id)
            .map(|entry| {
                entry
                    .value()
                    .iter()
                    .filter(|d| d.expires_at > now)
                    .cloned()
                    .collect()
            })
            .unwrap_or_default()
    }

    /// Burn a conversation (delete all data, set burn flag)
    pub async fn burn(&self, conversation_id: ConversationId) {
        // Remove all blobs immediately
        self.blobs.remove(&conversation_id);

        // Set burn flag with TTL
        let now = Utc::now();
        let burn_flag = BurnFlag {
            burned_at: now,
            expires_at: now + chrono::Duration::from_std(self.config.burn_ttl).unwrap(),
        };
        self.burns.insert(conversation_id, burn_flag);

        // Update metrics
        {
            let mut metrics = self.metrics.write().await;
            metrics.total_burns += 1;
        }

        debug!("Burned conversation");
    }

    /// Check if a conversation is burned
    pub fn is_burned(&self, conversation_id: &ConversationId) -> bool {
        let now = Utc::now();
        self.burns
            .get(conversation_id)
            .map(|entry| entry.expires_at > now)
            .unwrap_or(false)
    }

    /// Get burn status for a conversation
    pub fn get_burn_status(&self, conversation_id: &ConversationId) -> Option<BurnFlag> {
        let now = Utc::now();
        self.burns
            .get(conversation_id)
            .filter(|entry| entry.expires_at > now)
            .map(|entry| entry.value().clone())
    }

    /// Clean up expired data
    async fn cleanup_expired(&self) {
        let now = Utc::now();
        let mut expired_blobs = 0u64;

        // Clean up expired blobs
        for mut entry in self.blobs.iter_mut() {
            let before = entry.value().len();
            entry.value_mut().retain(|b| b.expires_at > now);
            let after = entry.value().len();
            expired_blobs += (before - after) as u64;
        }

        // Remove empty blob entries
        self.blobs.retain(|_, v| !v.is_empty());

        // Clean up expired burn flags
        self.burns.retain(|_, v| v.expires_at > now);

        // Clean up expired device registrations
        for mut entry in self.devices.iter_mut() {
            entry.value_mut().retain(|d| d.expires_at > now);
        }
        self.devices.retain(|_, v| !v.is_empty());

        // Update metrics
        if expired_blobs > 0 {
            let mut metrics = self.metrics.write().await;
            metrics.total_blobs_expired += expired_blobs;
            debug!(expired_blobs, "Cleaned up expired data");
        }
    }

    /// Get aggregate metrics (no PII)
    pub async fn get_metrics(&self) -> StoreMetrics {
        let metrics = self.metrics.read().await;
        StoreMetrics {
            total_blobs_stored: metrics.total_blobs_stored,
            total_blobs_expired: metrics.total_blobs_expired,
            total_burns: metrics.total_burns,
            total_registrations: metrics.total_registrations,
        }
    }
}

/// Store errors
#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("conversation has been burned")]
    ConversationBurned,

    #[error("payload too large")]
    PayloadTooLarge,

    #[error("message queue full")]
    QueueFull,

    #[error("database error: {0}")]
    DatabaseError(String),
}
