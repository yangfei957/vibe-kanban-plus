use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

use rand::RngCore;

/// In-memory session store with expiry tracking.
pub struct SessionStore {
    sessions: Mutex<HashMap<String, Instant>>,
    expiry: Duration,
}

impl SessionStore {
    pub fn new(expiry_secs: u64) -> Self {
        Self {
            sessions: Mutex::new(HashMap::new()),
            expiry: Duration::from_secs(expiry_secs),
        }
    }

    /// Create a new session and return the token.
    pub fn create_session(&self) -> String {
        let token = generate_token();
        let mut sessions = self.sessions.lock().unwrap();
        // Cleanup expired sessions while we're here
        let now = Instant::now();
        sessions.retain(|_, created_at| now.duration_since(*created_at) < self.expiry);
        sessions.insert(token.clone(), now);
        token
    }

    /// Check if a session token is valid (exists and not expired).
    pub fn validate_session(&self, token: &str) -> bool {
        let sessions = self.sessions.lock().unwrap();
        sessions
            .get(token)
            .is_some_and(|created_at| Instant::now().duration_since(*created_at) < self.expiry)
    }

    /// Remove a session (logout).
    pub fn remove_session(&self, token: &str) {
        let mut sessions = self.sessions.lock().unwrap();
        sessions.remove(token);
    }
}

/// Tracks failed login attempts per client IP with lockout support.
pub struct FailedAttemptTracker {
    attempts: Mutex<HashMap<String, FailedAttemptState>>,
    max_attempts: u32,
    lockout_duration: Duration,
}

struct FailedAttemptState {
    count: u32,
    last_attempt: Instant,
    locked_until: Option<Instant>,
}

impl FailedAttemptTracker {
    pub fn new(max_attempts: u32, lockout_duration_secs: u64) -> Self {
        Self {
            attempts: Mutex::new(HashMap::new()),
            max_attempts,
            lockout_duration: Duration::from_secs(lockout_duration_secs),
        }
    }

    /// Record a failed attempt. Returns (current_count, max_attempts).
    pub fn record_failure(&self, ip: &str) -> (u32, u32) {
        let mut attempts = self.attempts.lock().unwrap();
        let state = attempts
            .entry(ip.to_string())
            .or_insert(FailedAttemptState {
                count: 0,
                last_attempt: Instant::now(),
                locked_until: None,
            });

        // If previously locked and lockout expired, reset
        if let Some(locked_until) = state.locked_until
            && Instant::now() >= locked_until
        {
            state.count = 0;
            state.locked_until = None;
        }

        state.count += 1;
        state.last_attempt = Instant::now();

        if state.count >= self.max_attempts {
            state.locked_until = Some(Instant::now() + self.lockout_duration);
        }

        (state.count, self.max_attempts)
    }

    /// Check if an IP is currently locked out.
    pub fn is_locked_out(&self, ip: &str) -> bool {
        let attempts = self.attempts.lock().unwrap();
        attempts.get(ip).is_some_and(|state| {
            state
                .locked_until
                .is_some_and(|until| Instant::now() < until)
        })
    }

    /// Get remaining lockout seconds for an IP.
    pub fn lockout_remaining_secs(&self, ip: &str) -> u64 {
        let attempts = self.attempts.lock().unwrap();
        attempts
            .get(ip)
            .and_then(|state| state.locked_until)
            .map(|until| {
                let now = Instant::now();
                if until > now {
                    (until - now).as_secs()
                } else {
                    0
                }
            })
            .unwrap_or(0)
    }

    /// Reset attempts for an IP (after successful login).
    pub fn reset(&self, ip: &str) {
        let mut attempts = self.attempts.lock().unwrap();
        attempts.remove(ip);
    }
}

fn generate_token() -> String {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_create_and_validate() {
        let store = SessionStore::new(3600);
        let token = store.create_session();
        assert!(store.validate_session(&token));
        assert!(!store.validate_session("invalid_token"));
    }

    #[test]
    fn test_session_remove() {
        let store = SessionStore::new(3600);
        let token = store.create_session();
        store.remove_session(&token);
        assert!(!store.validate_session(&token));
    }

    #[test]
    fn test_failed_attempts_lockout() {
        let tracker = FailedAttemptTracker::new(3, 300);
        let ip = "192.168.1.1";

        assert!(!tracker.is_locked_out(ip));
        tracker.record_failure(ip);
        assert!(!tracker.is_locked_out(ip));
        tracker.record_failure(ip);
        assert!(!tracker.is_locked_out(ip));
        tracker.record_failure(ip); // 3rd attempt triggers lockout
        assert!(tracker.is_locked_out(ip));
    }

    #[test]
    fn test_reset_clears_attempts() {
        let tracker = FailedAttemptTracker::new(3, 300);
        let ip = "192.168.1.1";
        tracker.record_failure(ip);
        tracker.record_failure(ip);
        tracker.reset(ip);
        assert!(!tracker.is_locked_out(ip));
    }
}
