//! ASH Backend - Minimal Untrusted Message Relay
//!
//! A privacy-first ephemeral message relay that:
//! - Stores encrypted blobs in RAM only (fixed 5-minute TTL)
//! - Propagates burn signals for conversation destruction
//! - Sends silent push notifications via APNS
//!
//! # Security Properties
//!
//! - No plaintext content ever touches the server
//! - No user identity - only opaque conversation IDs
//! - No long-term storage - data deleted on ACK or expiry
//! - Best-effort delivery - no guaranteed message persistence

mod apns;
mod auth;
mod config;
mod expiry;
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

/// Maximum request body size (16 KiB).
const MAX_BODY_SIZE: usize = 16 * 1024;

#[tokio::main]
async fn main() {
    // Load environment variables from .env file if present
    let _ = dotenvy::dotenv();

    // Initialize structured logging
    init_tracing();

    // Load and validate configuration
    let config = Config::from_env();
    log_startup_info(&config);

    // Initialize core components
    let store = Arc::new(Store::new(config.clone()));
    store.clone().start_cleanup_task();

    let apns = apns::create_client(&config).await;
    let state = AppState::new(store, apns.clone());

    // Start background workers
    let expiry_worker = Arc::new(expiry::ExpiryWorker::new(state.clone(), apns));
    expiry_worker.start();

    // Build and serve the application
    let app = build_router(state);
    serve(app, &config).await;
}

/// Initialize tracing with environment-based log levels.
fn init_tracing() {
    use tracing_subscriber::{fmt, prelude::*, EnvFilter};

    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("ash_backend=debug,tower_http=info")),
        )
        .init();
}

/// Log startup configuration (no secrets).
fn log_startup_info(config: &Config) {
    info!(
        bind_addr = %config.bind_addr,
        port = config.port,
        storage = "memory",
        blob_ttl_secs = config.blob_ttl.as_secs(),
        max_ciphertext_size = config.max_ciphertext_size,
        apns_enabled = config.apns_configured(),
        "Starting ASH backend"
    );
}

/// Build the Axum router with all endpoints and middleware.
fn build_router(state: AppState) -> Router {
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

/// Bind to address and serve the application.
async fn serve(app: Router, config: &Config) {
    let bind_addr = format!("{}:{}", config.bind_addr, config.port);

    let listener = tokio::net::TcpListener::bind(&bind_addr)
        .await
        .expect("Failed to bind to address");

    info!(addr = %bind_addr, "Server listening");

    axum::serve(listener, app).await.expect("Server error");
}
