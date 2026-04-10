use std::{
    io::{self, Write},
    path::PathBuf,
};

use auth_wall::{hash_password, verify_password};

fn read_password(prompt: &str) -> String {
    eprint!("{}", prompt);
    io::stderr().flush().unwrap();
    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .expect("Failed to read input");
    input.trim().to_string()
}

fn get_password_path() -> PathBuf {
    // Check environment variable first, then fall back to default asset dir
    if let Ok(path) = std::env::var("AUTH_WALL_PASSWORD_FILE") {
        return PathBuf::from(path);
    }

    // Try to use the same directory as vibe-kanban data
    let proj_dirs = directories::ProjectDirs::from("ai", "bloop", "vibe-kanban");
    match proj_dirs {
        Some(dirs) => {
            let data_dir = dirs.data_dir().to_path_buf();
            if !data_dir.exists() {
                std::fs::create_dir_all(&data_dir).expect("Failed to create data directory");
            }
            data_dir.join("auth_wall_password.hash")
        }
        None => PathBuf::from("auth_wall_password.hash"),
    }
}

fn main() {
    let path = get_password_path();

    println!("╔══════════════════════════════════════════╗");
    println!("║     Vibe Kanban — Auth Wall Setup        ║");
    println!("╚══════════════════════════════════════════╝");
    println!();

    // Check if password already exists
    if path.exists() {
        let existing = std::fs::read_to_string(&path).unwrap_or_default();
        if !existing.trim().is_empty() {
            println!("⚠  A password is already configured at:");
            println!("   {}", path.display());
            println!();

            let confirm = read_password("Do you want to update it? (yes/no): ");
            if confirm.to_lowercase() != "yes" {
                println!("Aborted.");
                return;
            }
            println!();
        }
    }

    loop {
        let password = read_password("Enter new password: ");
        if password.is_empty() {
            println!("❌ Password cannot be empty. Try again.");
            continue;
        }
        if password.len() < 6 {
            println!("❌ Password must be at least 6 characters. Try again.");
            continue;
        }

        let confirm = read_password("Confirm password: ");
        if password != confirm {
            println!("❌ Passwords do not match. Try again.");
            println!();
            continue;
        }

        let hash = hash_password(&password);

        // Verify our hash works before saving
        assert!(
            verify_password(&password, &hash),
            "Hash verification failed — this should not happen"
        );

        // Ensure parent directory exists
        if let Some(parent) = path.parent()
            && !parent.exists()
        {
            std::fs::create_dir_all(parent).expect("Failed to create directory");
        }

        std::fs::write(&path, &hash).expect("Failed to write password hash file");
        println!();
        println!("✅ Password has been set successfully!");
        println!("   Hash file: {}", path.display());
        println!();
        println!("ℹ  Restart Vibe Kanban for the auth wall to take effect.");
        break;
    }
}
