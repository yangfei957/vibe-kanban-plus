# Auth Wall — Vibe Kanban 密码认证插件

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

一个为基于 [Axum](https://github.com/tokio-rs/axum) 的 Web 应用提供的**即插即用密码认证网关**插件。
设计为 [Vibe Kanban](https://github.com/yangfei957/vibe-kanban) 的可选安全层，**完全独立**，不依赖 Vibe Kanban 的任何内部 crate。

---

## 目录

- [需求文档](#需求文档)
- [架构概览](#架构概览)
- [部署文档](#部署文档)
- [配置参考](#配置参考)
- [API 接口](#api-接口)
- [开发指南](#开发指南)
- [许可证](#许可证)

---

## 需求文档

### 1. 背景与目标

Vibe Kanban 默认以本地无认证模式运行，适合个人单机使用。当部署到服务器或公网环境时，需要一个轻量级密码保护层来防止未授权访问。

**核心需求：**

| 编号 | 需求 | 优先级 |
|------|------|--------|
| R-01 | 对所有页面和 API 请求进行密码认证拦截 | P0 |
| R-02 | 提供独立的 HTML 登录页面，不依赖前端框架 | P0 |
| R-03 | 密码使用安全的哈希算法存储，禁止明文 | P0 |
| R-04 | 支持基于 IP 的暴力破解防护（限速+锁定） | P0 |
| R-05 | 通过 HTTP Cookie 维护登录会话 | P0 |
| R-06 | 以 Cargo feature 方式集成，不启用时零影响 | P0 |
| R-07 | 未设置密码时自动放行（优雅降级） | P1 |
| R-08 | 所有参数可通过环境变量配置 | P1 |
| R-09 | 支持 HTTPS 环境下的 Secure Cookie | P2 |
| R-10 | 完全独立于 Vibe Kanban，可在其他 Axum 项目中复用 | P1 |

### 2. 功能规格

#### 2.1 密码管理

- **无注册功能**：密码只能通过 `set-password` CLI 工具离线设置
- **哈希算法**：Argon2id（当前密码学最佳实践）
- **存储方式**：密码哈希写入本地文件（默认路径 `<data_dir>/auth_wall_password.hash`）
- **更新流程**：运行 `set-password` → 输入新密码 → 确认 → 写入哈希文件 → 重启服务生效

#### 2.2 认证流程

```
用户请求
    │
    ▼
┌──────────────┐    是     ┌─────────────┐
│ 路径以         │─────────→│ 直接放行     │
│ /auth-wall/  │          └─────────────┘
│ 开头？        │
└──────┬───────┘
       │ 否
       ▼
┌──────────────┐    否     ┌─────────────┐
│ 密码已配置？  │─────────→│ 直接放行     │
└──────┬───────┘          └─────────────┘
       │ 是
       ▼
┌──────────────┐    是     ┌─────────────┐
│ Cookie 有效？ │─────────→│ 直接放行     │
└──────┬───────┘          └─────────────┘
       │ 否
       ▼
┌──────────────┐   /api/*  ┌──────────────┐
│ 请求类型？    │─────────→│ 返回 401     │
└──────┬───────┘          └──────────────┘
       │ 页面请求
       ▼
┌──────────────────────┐
│ 302 重定向到登录页面  │
│ /auth-wall/login     │
└──────────────────────┘
```

#### 2.3 暴力破解防护

- 按客户端 IP 追踪失败尝试次数
- 超过阈值（默认 5 次）后锁定该 IP
- 锁定期间（默认 5 分钟）拒绝所有登录尝试，返回 `429 Too Many Requests`
- 登录成功后自动重置计数器

#### 2.4 会话管理

- 基于内存的会话存储（服务重启后会话失效，需重新登录）
- 会话令牌：32 字节随机 hex 字符串
- Cookie 属性：`HttpOnly`、`SameSite=Strict`、`Path=/`
- 可选 `Secure` 标记（HTTPS 环境启用）
- 默认会话有效期：24 小时

### 3. 非功能需求

| 类别 | 要求 |
|------|------|
| **安全性** | Argon2id 哈希；HttpOnly + SameSite=Strict Cookie；IP 限速锁定 |
| **性能** | 中间件开销 < 1ms（仅内存 HashMap 查找） |
| **可用性** | 未配置密码时自动放行，不影响正常使用 |
| **独立性** | 零内部依赖，可独立编译、测试和发布 |
| **兼容性** | 需要 Rust nightly (edition 2024)；Axum 0.8+ |

---

## 架构概览

```
vibe-kanban-plus/
├── Cargo.toml              # 独立 crate 配置（无 workspace 依赖）
├── rust-toolchain.toml     # Rust nightly 工具链
├── rustfmt.toml            # 代码格式化配置
├── LICENSE                 # Apache-2.0
├── README.md               # 本文件
└── src/
    ├── lib.rs              # 公共 API：AuthWallConfig / AuthWallState /
    │                       #   auth_wall_routes() / auth_wall_middleware()
    ├── password.rs          # Argon2id 密码哈希与验证
    ├── session.rs           # SessionStore + FailedAttemptTracker
    ├── login_page.rs        # 嵌入式 HTML 登录页面
    └── bin/
        └── set_password.rs  # 密码设置 CLI 工具
```

### 模块职责

| 模块 | 职责 |
|------|------|
| `lib.rs` | 定义配置结构体、共享状态、路由注册、认证中间件 |
| `password.rs` | Argon2id 密码哈希生成与验证 |
| `session.rs` | 内存会话存储（创建/验证/删除）、IP 失败尝试追踪与锁定 |
| `login_page.rs` | 纯 HTML/CSS/JS 登录页面，深色主题，无外部依赖 |
| `set_password.rs` | 交互式 CLI，引导用户设置/更新密码 |

### 对外公共 API

```rust
// 配置
pub struct AuthWallConfig { ... }
pub struct AuthWallState { ... }

// 路由 — 在你的 Router 上合并
pub fn auth_wall_routes(state: AuthWallState) -> Router;

// 中间件 — 用 axum::middleware::from_fn_with_state 包装
pub async fn auth_wall_middleware(
    State(state): State<AuthWallState>,
    req: Request<Body>,
    next: Next,
) -> Response;

// 密码工具
pub fn hash_password(password: &str) -> String;
pub fn verify_password(password: &str, hash_str: &str) -> bool;
```

---

## 部署文档

### 方式一：集成到 Vibe Kanban（推荐）

#### 前置条件

- Rust nightly (>= nightly-2025-12-04)
- Vibe Kanban 源码

#### 步骤 1：添加 Git 依赖

在 Vibe Kanban 的 `crates/server/Cargo.toml` 中：

```toml
[dependencies]
auth-wall = { git = "https://github.com/yangfei957/vibe-kanban-plus.git", optional = true }

[features]
auth-wall = ["dep:auth-wall"]
```

#### 步骤 2：集成中间件

在服务器路由代码中添加（已通过 `#[cfg(feature = "auth-wall")]` 条件编译）：

```rust
#[cfg(feature = "auth-wall")]
let app = {
    let auth_state = auth_wall_state();
    app.merge(auth_wall::auth_wall_routes(auth_state.clone()))
        .layer(axum::middleware::from_fn_with_state(
            auth_state,
            auth_wall::auth_wall_middleware,
        ))
};
```

#### 步骤 3：设置密码

```bash
# 编译并运行密码设置工具
cargo run --bin set-password

# 交互式输入：
# Enter new password: ********
# Confirm password: ********
# ✅ Password has been set successfully!
```

#### 步骤 4：启动服务

```bash
# 启用 auth-wall feature 编译并运行
cargo run --bin server --features auth-wall
```

#### 步骤 5：验证

1. 打开浏览器访问 `http://localhost:<port>`
2. 应自动跳转到 `/auth-wall/login` 登录页面
3. 输入密码登录后跳转回主页面

---

### 方式二：集成到其他 Axum 项目

#### 步骤 1：添加依赖

```toml
[dependencies]
auth-wall = { git = "https://github.com/yangfei957/vibe-kanban-plus.git" }
```

#### 步骤 2：集成代码

```rust
use auth_wall::{AuthWallConfig, AuthWallState, auth_wall_routes, auth_wall_middleware};

let config = AuthWallConfig {
    password_hash_path: "/path/to/password.hash".into(),
    ..Default::default()
};
let auth_state = AuthWallState::new(config);

let app = Router::new()
    .route("/", get(index))
    // ... 你的其他路由
    .merge(auth_wall_routes(auth_state.clone()))
    .layer(axum::middleware::from_fn_with_state(
        auth_state,
        auth_wall_middleware,
    ));
```

#### 步骤 3：设置密码

```bash
cargo run --bin set-password
```

---

### 方式三：Docker 部署

```dockerfile
FROM rust:nightly AS builder
WORKDIR /app
COPY . .
RUN cargo build --release --bin server --features auth-wall
RUN cargo build --release --bin set-password

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/server /usr/local/bin/
COPY --from=builder /app/target/release/set-password /usr/local/bin/
ENV AUTH_WALL_PASSWORD_FILE=/data/auth_wall_password.hash
VOLUME /data
EXPOSE 8080
CMD ["server"]
```

```bash
# 构建
docker build -t vibe-kanban .

# 首次设置密码
docker run -it -v vibe-data:/data vibe-kanban set-password

# 运行
docker run -d -p 8080:8080 -v vibe-data:/data vibe-kanban
```

---

### 方式四：反向代理 + HTTPS（生产环境）

配合 Caddy 或 Nginx 使用时，启用 Secure Cookie：

```bash
export AUTH_WALL_SECURE_COOKIE=true
cargo run --bin server --features auth-wall
```

Caddy 配置示例：

```caddyfile
yourdomain.com {
    reverse_proxy localhost:8080
}
```

---

## 配置参考

所有配置通过**环境变量**设置：

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `AUTH_WALL_PASSWORD_FILE` | `<data_dir>/auth_wall_password.hash` | 密码哈希文件路径 |
| `AUTH_WALL_MAX_ATTEMPTS` | `5` | 锁定前最大失败尝试次数 |
| `AUTH_WALL_LOCKOUT_SECS` | `300` | 锁定持续时间（秒） |
| `AUTH_WALL_SESSION_SECS` | `86400` | 会话有效期（秒），默认 24 小时 |
| `AUTH_WALL_SECURE_COOKIE` | `false` | 是否设置 Cookie 的 Secure 标记（HTTPS 环境设为 `true`） |

> **注意：** `<data_dir>` 在不同操作系统上的默认路径：
> - **Linux**: `~/.local/share/ai.bloop.vibe-kanban/`
> - **macOS**: `~/Library/Application Support/ai.bloop.vibe-kanban/`
> - **Windows**: `C:\Users\<user>\AppData\Roaming\bloop\vibe-kanban\data\`

---

## API 接口

| 方法 | 路径 | 说明 | 认证 |
|------|------|------|------|
| `GET` | `/auth-wall/login` | 返回 HTML 登录页面 | ❌ 不需要 |
| `POST` | `/auth-wall/api/login` | 验证密码并创建会话 | ❌ 不需要 |
| `POST` | `/auth-wall/api/logout` | 销毁会话并清除 Cookie | ❌ 不需要 |
| `GET` | `/auth-wall/api/status` | 查询认证状态 | ❌ 不需要 |

### POST `/auth-wall/api/login`

**请求体：**
```json
{ "password": "your_password" }
```

**成功响应（200）：**
```json
{ "success": true, "message": "Login successful" }
```
附带 `Set-Cookie: auth_wall_session=<token>; Path=/; HttpOnly; SameSite=Strict; Max-Age=86400`

**失败响应（401）：**
```json
{ "success": false, "message": "Invalid password. 1 of 5 attempts used." }
```

**锁定响应（429）：**
```json
{ "success": false, "message": "Too many failed attempts. Please try again in 285 seconds." }
```

---

## 开发指南

### 构建

```bash
cargo build
```

### 测试

```bash
cargo test
```

### 格式化

```bash
cargo fmt
```

### 作为独立仓库发布

此仓库完全独立，不依赖 Vibe Kanban 的任何内部 crate。
可直接 `git clone` 后独立编译、测试、修改。

---

## 许可证

[Apache License 2.0](LICENSE)
