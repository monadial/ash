//! # ASH Backend
//!
//! Minimal untrusted message relay for ephemeral encrypted messaging.
//!
//! ## Design Principles
//!
//! - **No plaintext content**: All message content is end-to-end encrypted
//! - **No user identity**: Backend has no concept of users, only conversation IDs
//! - **No long-term storage**: RAM-only with fixed 5-minute TTL
//! - **Best-effort delivery**: Messages may expire before delivery
//! - **Minimal logging**: No PII ever logged
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────┐     ┌─────────────┐
//! │   Client A  │────▶│   Backend   │◀────│   Client B  │
//! └─────────────┘     └─────────────┘     └─────────────┘
//!                            │
//!                     ┌──────┴──────┐
//!                     │             │
//!                 In-Memory      APNS
//!                   Store      (silent)
//! ```
//!
//! ## API Overview
//!
//! | Endpoint | Method | Description |
//! |----------|--------|-------------|
//! | `/health` | GET | Health check |
//! | `/v1/conversations` | POST | Register conversation |
//! | `/v1/register` | POST | Register device for push |
//! | `/v1/messages` | POST | Submit encrypted message |
//! | `/v1/messages` | GET | Poll for messages |
//! | `/v1/messages/ack` | POST | Acknowledge receipt |
//! | `/v1/messages/stream` | GET | SSE real-time stream |
//! | `/v1/burn` | POST | Burn conversation |
//! | `/v1/burn` | GET | Check burn status |

pub mod apns;
pub mod auth;
pub mod config;
pub mod expiry;
pub mod handlers;
pub mod models;
pub mod store;

pub use config::Config;
pub use handlers::AppState;
pub use store::Store;
