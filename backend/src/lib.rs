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

use axum::{
    http::{header, Method},
    routing::{get, post},
    Router,
};
use tower_http::{
    cors::{Any, CorsLayer},
    limit::RequestBodyLimitLayer,
    trace::TraceLayer,
};

/// Maximum request body size (16 KiB).
pub const MAX_BODY_SIZE: usize = 16 * 1024;

/// Build the Axum router with all endpoints and middleware.
pub fn build_router(state: AppState) -> Router {
    Router::new()
        // Health check (unauthenticated)
        .route("/health", get(handlers::health))
        // API v1 endpoints
        .route("/v1/conversations", post(handlers::register_conversation))
        .route("/v1/register", post(handlers::register_device))
        .route("/v1/messages", post(handlers::submit_message))
        .route("/v1/messages", get(handlers::poll_messages))
        .route("/v1/messages/ack", post(handlers::ack_messages))
        .route("/v1/messages/stream", get(handlers::message_stream))
        .route("/v1/burn", post(handlers::burn_conversation))
        .route("/v1/burn", get(handlers::burn_status))
        // Middleware stack (order matters: first added = outermost)
        .layer(RequestBodyLimitLayer::new(MAX_BODY_SIZE))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods([Method::GET, Method::POST])
                .allow_headers([header::CONTENT_TYPE, header::AUTHORIZATION]),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
