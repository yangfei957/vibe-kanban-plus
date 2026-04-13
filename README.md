# Vibe Kanban Plus — 插件集合

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

[Vibe Kanban](https://github.com/yangfei957/vibe-kanban) 的**插件仓库**，采用统一的插件架构管理多个可选增强插件。每个插件完全独立，不依赖 Vibe Kanban 的内部 crate，可按需安装。

---

## 目录

- [插件列表](#插件列表)
- [快速开始](#快速开始)
- [架构概览](#架构概览)
- [主安装脚本用法](#主安装脚本用法)
- [插件详情：auth-wall](#插件详情auth-wall)
- [添加新插件](#添加新插件)
- [开发指南](#开发指南)
- [许可证](#许可证)

---

## 插件列表

| 插件 | 说明 | 状态 |
|------|------|------|
| [auth-wall](plugins/auth-wall/) | 密码认证网关插件，为 Axum Web 应用提供即插即用的密码保护 | ✅ 可用 |

---

## 快速开始

```bash
# 克隆本仓库
git clone https://github.com/yangfei957/vibe-kanban-plus.git
cd vibe-kanban-plus

# 安装所有插件到 vibe-kanban
./scripts/install.sh /path/to/vibe-kanban

# 或仅安装指定插件
./scripts/install.sh /path/to/vibe-kanban auth-wall

# 列出可用插件
./scripts/install.sh --list
```

---

## 架构概览

```
vibe-kanban-plus/
├── Cargo.toml              # Workspace 根配置
├── rust-toolchain.toml     # Rust nightly 工具链
├── rustfmt.toml            # 代码格式化配置
├── LICENSE
├── README.md
├── scripts/
│   └── install.sh          # 主安装脚本（统一入口）
├── plugins/
│   └── auth-wall/          # auth-wall 插件
│       ├── Cargo.toml      # 插件 crate 配置
│       ├── plugin.conf     # 插件构建配置（features、bins）
│       ├── install.sh      # 插件安装/卸载脚本
│       └── src/
│           ├── lib.rs
│           ├── password.rs
│           ├── session.rs
│           ├── login_page.rs
│           └── bin/
│               └── set_password.rs
└── docs/
```

### 插件规范

每个插件是 `plugins/` 下的一个子目录，包含以下文件：

| 文件 | 必需 | 说明 |
|------|------|------|
| `install.sh` | ✅ | 插件安装/卸载脚本，支持 `install` 和 `uninstall` 两个子命令 |
| `plugin.conf` | 推荐 | 声明插件需要的 Cargo features 和额外 bins |
| `Cargo.toml` | 推荐 | Rust crate 配置（如果插件包含 Rust 代码） |
| `src/` | 推荐 | 源代码目录 |

### 安装流程

```
用户执行 scripts/install.sh
    │
    ├── Phase 1: 环境检测与依赖安装
    │   ├── Git
    │   ├── Rust nightly-2025-12-04（自动安装）
    │   ├── Node.js >= 20
    │   └── pnpm（自动安装）
    │
    ├── Phase 2: 前端构建（可跳过）
    │   ├── pnpm install
    │   └── pnpm run build
    │
    ├── Phase 3: 安装插件源码
    │   └── 调用 plugins/<name>/install.sh install <VK_DIR>
    │       └── 复制源码到 vibe-kanban/crates/<name>/
    │
    ├── Phase 4: 集中编译（可跳过）
    │   ├── 从 plugin.conf 收集 features 和 bins
    │   ├── cargo build --release --bin server --features <all>
    │   ├── cargo build --release --bin <extra-bins> --features <all>
    │   └── cargo build --release --bin vibe-kanban-mcp（如存在）
    │
    ├── Phase 5: 打包成品
    │   └── zip 到 npx-cli/dist/<platform>/
    │
    └── Phase 6: 清理插件源码
        └── 调用 plugins/<name>/install.sh uninstall <VK_DIR>
            └── 移除 vibe-kanban/crates/<name>/，保持源码干净
```

### 职责分离

| 角色 | 职责 |
|------|------|
| **主脚本** `scripts/install.sh` | 环境检测、前端构建、集中编译、打包、统一调度插件安装/卸载 |
| **插件脚本** `plugins/<name>/install.sh` | 仅负责自身源码的复制（install）和清理（uninstall） |
| **插件配置** `plugins/<name>/plugin.conf` | 声明插件需要的编译参数（features、bins） |

---

## 主安装脚本用法

```bash
# 显示帮助
./scripts/install.sh --help

# 列出可用插件
./scripts/install.sh --list

# 安装所有插件
./scripts/install.sh /path/to/vibe-kanban

# 仅安装指定插件
./scripts/install.sh /path/to/vibe-kanban auth-wall

# 安装多个指定插件
./scripts/install.sh /path/to/vibe-kanban auth-wall another-plugin

# 跳过前端构建
SKIP_FRONTEND=true ./scripts/install.sh /path/to/vibe-kanban

# 只复制源码，不编译
SKIP_BUILD=true ./scripts/install.sh /path/to/vibe-kanban auth-wall
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SKIP_FRONTEND` | `false` | 跳过前端构建 |
| `SKIP_BUILD` | `false` | 跳过编译步骤，只复制源码 |
| `CARGO_TARGET_DIR` | `<源码目录>/target` | 自定义 Cargo 输出目录 |

---

## 插件详情：auth-wall

一个为基于 Axum 的 Web 应用提供的**即插即用密码认证网关**插件。

### 功能特性

- 对所有页面和 API 请求进行密码认证拦截
- 独立 HTML 登录页面，不依赖前端框架
- Argon2id 密码哈希（当前密码学最佳实践）
- 基于 IP 的暴力破解防护（限速 + 锁定）
- HTTP Cookie 会话管理
- 以 Cargo feature 方式集成，不启用时零影响
- 未设置密码时自动放行（优雅降级）

### 安装后设置密码

```bash
# 运行密码设置工具（交互式）
target/release/set-password

# 启动带认证的服务
target/release/server
```

### 配置参考

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `AUTH_WALL_PASSWORD_FILE` | `<data_dir>/auth_wall_password.hash` | 密码哈希文件路径 |
| `AUTH_WALL_MAX_ATTEMPTS` | `5` | 锁定前最大失败尝试次数 |
| `AUTH_WALL_LOCKOUT_SECS` | `300` | 锁定持续时间（秒） |
| `AUTH_WALL_SESSION_SECS` | `86400` | 会话有效期（秒），默认 24 小时 |
| `AUTH_WALL_SECURE_COOKIE` | `false` | HTTPS 环境设为 `true` |

### API 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/auth-wall/login` | HTML 登录页面 |
| `POST` | `/auth-wall/api/login` | 验证密码并创建会话 |
| `POST` | `/auth-wall/api/logout` | 销毁会话并清除 Cookie |
| `GET` | `/auth-wall/api/status` | 查询认证状态 |

### 集成到其他 Axum 项目

```toml
[dependencies]
auth-wall = { git = "https://github.com/yangfei957/vibe-kanban-plus.git" }
```

```rust
use auth_wall::{AuthWallConfig, AuthWallState, auth_wall_routes, auth_wall_middleware};

let config = AuthWallConfig {
    password_hash_path: "/path/to/password.hash".into(),
    ..Default::default()
};
let auth_state = AuthWallState::new(config);

let app = Router::new()
    .route("/", get(index))
    .merge(auth_wall_routes(auth_state.clone()))
    .layer(axum::middleware::from_fn_with_state(
        auth_state,
        auth_wall_middleware,
    ));
```

---

## 添加新插件

1. 在 `plugins/` 下创建新目录，例如 `plugins/my-plugin/`
2. 创建 `plugins/my-plugin/install.sh`（必需），支持 `install` 和 `uninstall` 两个子命令
3. 创建 `plugins/my-plugin/plugin.conf`（推荐），声明编译参数
4. 如果包含 Rust 代码，创建 `Cargo.toml` 并在根 `Cargo.toml` 的 `workspace.members` 中注册
5. 主安装脚本会自动发现 `plugins/` 下所有包含 `install.sh` 的子目录

### install.sh 模板

```bash
#!/usr/bin/env bash
set -euo pipefail

[[ $# -lt 2 ]] && { echo "用法: $0 {install|uninstall} <vibe-kanban 源码目录>"; exit 1; }
ACTION="$1"
VK_DIR="$(cd "$2" && pwd)"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$VK_DIR/crates/my-plugin"

case "$ACTION" in
    install)
        mkdir -p "$TARGET_DIR"
        cp -r "$PLUGIN_DIR/src" "$TARGET_DIR/"
        cp "$PLUGIN_DIR/Cargo.toml" "$TARGET_DIR/"
        echo "✅ my-plugin 已安装到 $TARGET_DIR"
        ;;
    uninstall)
        rm -rf "$TARGET_DIR"
        echo "✅ my-plugin 已从 $VK_DIR 中清理"
        ;;
    *)
        echo "未知动作: $ACTION"; exit 1
        ;;
esac
```

### plugin.conf 模板

```bash
# 添加到 cargo build 的 feature flags（空格分隔）
CARGO_FEATURES="my-plugin"

# 需要编译的额外二进制文件（空格分隔）
CARGO_BINS="my-tool"

# 插件安装到 vibe-kanban 的目标目录（相对于 VK_DIR）
INSTALL_DIR="crates/my-plugin"
```

---

## 开发指南

### 构建所有插件

```bash
cargo build
```

### 测试所有插件

```bash
cargo test
```

### 格式化

```bash
cargo fmt
```

---

## 许可证

[Apache License 2.0](LICENSE)
