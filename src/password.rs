use argon2::{
    Argon2,
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString, rand_core::OsRng},
};

/// Hash a password using Argon2id with a random salt.
pub fn hash_password(password: &str) -> String {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    argon2
        .hash_password(password.as_bytes(), &salt)
        .expect("Failed to hash password")
        .to_string()
}

/// Verify a password against an Argon2 hash string.
pub fn verify_password(password: &str, hash_str: &str) -> bool {
    let parsed_hash = match PasswordHash::new(hash_str) {
        Ok(h) => h,
        Err(_) => return false,
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed_hash)
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_and_verify() {
        let password = "my_secure_password_123!";
        let hash = hash_password(password);
        assert!(verify_password(password, &hash));
        assert!(!verify_password("wrong_password", &hash));
    }

    #[test]
    fn test_empty_password() {
        let hash = hash_password("");
        assert!(verify_password("", &hash));
        assert!(!verify_password("notempty", &hash));
    }

    #[test]
    fn test_invalid_hash() {
        assert!(!verify_password("test", "not_a_valid_hash"));
    }
}
