//! ASH Backend - Minimal Untrusted Message Relay
//!
//! This server provides:
//! - Ephemeral encrypted blob storage (RAM only, fixed 5-minute TTL)
//! - Burn signal propagation
//! - Silent push notifications (APNS)
//!
//! Design principles:
//! - No plaintext content
//! - No user identity
//! - No long-term storage (RAM only, messages deleted on ACK or expiry)
//! - Best-effort delivery
//! - Minimal logging (no PII)

mod apns;
mod auth;
mod config;
mod handlers;
mod models;
mod store;

use axum::{
    http::{header, Method},
    routing::{get, post},
    Router,
};
use config::Config;
use handlers::AppState;
use std::sync::Arc;
use store::Store;
use tower_http::{
    cors::{Any, CorsLayer},
    limit::RequestBodyLimitLayer,
    trace::TraceLayer,
};
use tracing::info;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

#[tokio::main]
async fn main() {
    // Load environment variables from .env file if present
    let _ = dotenvy::dotenv();

    // Initialize logging (no PII in logs)
    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("ash_backend=debug,tower_http=info")),
        )
        .init();

    // Load configuration
    let config = Config::from_env();

    info!(
        bind_addr = %config.bind_addr,
        port = config.port,
        storage = "memory",
        blob_ttl_secs = config.blob_ttl.as_secs(),
        max_ciphertext_size = config.max_ciphertext_size,
        apns_enabled = config.apns_configured(),
        "Starting ASH backend (ephemeral mode)"
    );

    // Initialize in-memory storage
    let store = Arc::new(Store::new(config.clone()));

    // Start TTL cleanup task
    store.clone().start_cleanup_task();

    // Initialize APNS client
    let apns = apns::create_client(&config).await;

    // Create app state with broadcast channel for SSE
    let state = AppState::new(store, apns);

    // Build router
    let app = Router::new()
        // Health check
        .route("/health", get(handlers::health))
        // API v1
        .route("/v1/conversations", post(handlers::register_conversation))
        .route("/v1/register", post(handlers::register_device))
        .route("/v1/messages", post(handlers::submit_message))
        .route("/v1/messages", get(handlers::poll_messages))
        .route("/v1/messages/stream", get(handlers::message_stream))
        .route("/v1/burn", post(handlers::burn_conversation))
        .route("/v1/burn", get(handlers::burn_status))
        // Middleware
        .layer(RequestBodyLimitLayer::new(16 * 1024)) // 16KB max body
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods([Method::GET, Method::POST])
                .allow_headers([header::CONTENT_TYPE]),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    // Bind and serve
    let bind_addr = format!("{}:{}", config.bind_addr, config.port);
    let listener = tokio::net::TcpListener::bind(&bind_addr)
        .await
        .expect("Failed to bind to address");

    info!(addr = %bind_addr, "Server listening");

    axum::serve(listener, app)
        .await
        .expect("Server error");
}
