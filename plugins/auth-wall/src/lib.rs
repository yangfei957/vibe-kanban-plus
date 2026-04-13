mod login_page;
mod password;
mod session;

use std::{path::PathBuf, sync::Arc};

use axum::{
    Json, Router,
    body::Body,
    extract::State,
    http::{Request, StatusCode, header},
    middleware::Next,
    response::{Html, IntoResponse, Response},
    routing::{get, post},
};
pub use password::{hash_password, verify_password};
use serde::{Deserialize, Serialize};
pub use session::SessionStore;

/// Configuration for the auth-wall plugin.
#[derive(Clone)]
pub struct AuthWallConfig {
    /// Path to the file storing the argon2 password hash.
    pub password_hash_path: PathBuf,
    /// Max consecutive failed login attempts before lockout.
    pub max_failed_attempts: u32,
    /// Lockout duration in seconds after exceeding max attempts.
    pub lockout_duration_secs: u64,
    /// Session expiry in seconds (default: 24 hours).
    pub session_expiry_secs: u64,
    /// Whether to set the Secure flag on cookies (disable for plain HTTP / localhost).
    pub secure_cookie: bool,
}

impl Default for AuthWallConfig {
    fn default() -> Self {
        Self {
            password_hash_path: PathBuf::from("auth_wall_password.hash"),
            max_failed_attempts: 5,
            lockout_duration_secs: 300, // 5 minutes
            session_expiry_secs: 86400, // 24 hours
            secure_cookie: false,       // default off for localhost usage
        }
    }
}

/// Shared state for the auth-wall plugin.
#[derive(Clone)]
pub struct AuthWallState {
    pub config: AuthWallConfig,
    pub sessions: Arc<SessionStore>,
    pub failed_attempts: Arc<session::FailedAttemptTracker>,
}

impl AuthWallState {
    pub fn new(config: AuthWallConfig) -> Self {
        Self {
            sessions: Arc::new(SessionStore::new(config.session_expiry_secs)),
            failed_attempts: Arc::new(session::FailedAttemptTracker::new(
                config.max_failed_attempts,
                config.lockout_duration_secs,
            )),
            config,
        }
    }

    /// Check if a password file exists and has content.
    pub fn is_password_configured(&self) -> bool {
        self.config.password_hash_path.exists()
            && std::fs::read_to_string(&self.config.password_hash_path)
                .map(|s| !s.trim().is_empty())
                .unwrap_or(false)
    }

    /// Read the stored password hash from disk.
    fn read_password_hash(&self) -> Option<String> {
        std::fs::read_to_string(&self.config.password_hash_path)
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    }
}

// ── API types ──────────────────────────────────────────────

#[derive(Deserialize)]
struct LoginRequest {
    password: String,
}

#[derive(Serialize)]
struct LoginResponse {
    success: bool,
    message: String,
}

#[derive(Serialize)]
struct StatusResponse {
    authenticated: bool,
    password_configured: bool,
}

// ── Auth-wall routes ───────────────────────────────────────

/// Returns a Router containing the auth-wall API endpoints and login page.
/// These routes are NOT protected by the auth-wall middleware themselves.
pub fn auth_wall_routes(state: AuthWallState) -> Router {
    Router::new()
        .route("/auth-wall/login", get(login_page_handler))
        .route("/auth-wall/api/login", post(login_handler))
        .route("/auth-wall/api/logout", post(logout_handler))
        .route("/auth-wall/api/status", get(status_handler))
        .with_state(state)
}

async fn login_page_handler() -> impl IntoResponse {
    Html(login_page::LOGIN_PAGE_HTML)
}

async fn login_handler(
    State(state): State<AuthWallState>,
    headers: axum::http::HeaderMap,
    Json(req): Json<LoginRequest>,
) -> Response {
    let client_ip = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();

    // Check lockout
    if state.failed_attempts.is_locked_out(&client_ip) {
        let remaining = state.failed_attempts.lockout_remaining_secs(&client_ip);
        tracing::warn!("Auth-wall: login attempt from locked-out IP: {}", client_ip);
        return (
            StatusCode::TOO_MANY_REQUESTS,
            Json(LoginResponse {
                success: false,
                message: format!(
                    "Too many failed attempts. Please try again in {} seconds.",
                    remaining
                ),
            }),
        )
            .into_response();
    }

    // Check password configured
    let stored_hash = match state.read_password_hash() {
        Some(h) => h,
        None => {
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(LoginResponse {
                    success: false,
                    message: "Password not configured. Please run `set-password` first."
                        .to_string(),
                }),
            )
                .into_response();
        }
    };

    // Verify password
    if verify_password(&req.password, &stored_hash) {
        state.failed_attempts.reset(&client_ip);
        let token = state.sessions.create_session();
        tracing::info!("Auth-wall: successful login from {}", client_ip);

        let secure_flag = if state.config.secure_cookie {
            "; Secure"
        } else {
            ""
        };
        let cookie_value = format!(
            "auth_wall_session={}; Path=/; HttpOnly; SameSite=Strict; Max-Age={}{}",
            token, state.config.session_expiry_secs, secure_flag
        );
        let mut response = (
            StatusCode::OK,
            Json(LoginResponse {
                success: true,
                message: "Login successful".to_string(),
            }),
        )
            .into_response();
        response
            .headers_mut()
            .insert(header::SET_COOKIE, cookie_value.parse().unwrap());
        response
    } else {
        let (attempts, max) = state.failed_attempts.record_failure(&client_ip);
        tracing::warn!(
            "Auth-wall: failed login from {} ({}/{})",
            client_ip,
            attempts,
            max
        );
        (
            StatusCode::UNAUTHORIZED,
            Json(LoginResponse {
                success: false,
                message: format!("Invalid password. {} of {} attempts used.", attempts, max),
            }),
        )
            .into_response()
    }
}

async fn logout_handler(
    State(state): State<AuthWallState>,
    headers: axum::http::HeaderMap,
) -> impl IntoResponse {
    if let Some(token) = extract_session_token(&headers) {
        state.sessions.remove_session(&token);
    }
    let secure_flag = if state.config.secure_cookie {
        "; Secure"
    } else {
        ""
    };
    let clear_cookie = format!(
        "auth_wall_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0{}",
        secure_flag
    );
    let mut response = (
        StatusCode::OK,
        Json(LoginResponse {
            success: true,
            message: "Logged out".to_string(),
        }),
    )
        .into_response();
    response
        .headers_mut()
        .insert(header::SET_COOKIE, clear_cookie.parse().unwrap());
    response
}

async fn status_handler(
    State(state): State<AuthWallState>,
    headers: axum::http::HeaderMap,
) -> impl IntoResponse {
    let authenticated = extract_session_token(&headers)
        .map(|t| state.sessions.validate_session(&t))
        .unwrap_or(false);
    Json(StatusResponse {
        authenticated,
        password_configured: state.is_password_configured(),
    })
}

// ── Middleware ──────────────────────────────────────────────

/// Axum middleware that checks authentication on every request.
/// Requests to `/auth-wall/*` are always allowed through.
/// Unauthenticated requests get redirected to the login page.
pub async fn auth_wall_middleware(
    State(state): State<AuthWallState>,
    req: Request<Body>,
    next: Next,
) -> Response {
    let path = req.uri().path().to_string();

    // Always allow auth-wall routes through
    if path.starts_with("/auth-wall/") {
        return next.run(req).await;
    }

    // Allow static assets needed by the login page (favicon, etc.)
    // but only if they don't need protection
    if path == "/favicon.ico" {
        return next.run(req).await;
    }

    // If no password is configured, allow everything through
    if !state.is_password_configured() {
        return next.run(req).await;
    }

    // Check session cookie
    let authenticated = req
        .headers()
        .get(header::COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(|cookies| parse_cookie(cookies, "auth_wall_session"))
        .map(|token| state.sessions.validate_session(&token))
        .unwrap_or(false);

    if authenticated {
        return next.run(req).await;
    }

    // For API requests, return 401
    if path.starts_with("/api/") {
        return (StatusCode::UNAUTHORIZED, "Authentication required").into_response();
    }

    // For page requests, redirect to login
    Response::builder()
        .status(StatusCode::FOUND)
        .header(header::LOCATION, "/auth-wall/login")
        .body(Body::empty())
        .unwrap()
}

// ── Helpers ────────────────────────────────────────────────

fn extract_session_token(headers: &axum::http::HeaderMap) -> Option<String> {
    headers
        .get(header::COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(|cookies| parse_cookie(cookies, "auth_wall_session"))
}

fn parse_cookie(cookie_header: &str, name: &str) -> Option<String> {
    cookie_header.split(';').find_map(|pair| {
        let pair = pair.trim();
        if let Some(value) = pair.strip_prefix(name) {
            let value = value.trim_start_matches('=');
            Some(value.to_string())
        } else {
            None
        }
    })
}
