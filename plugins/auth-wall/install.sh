#!/usr/bin/env bash
# ============================================================================
# auth-wall/install.sh
#
# 将 auth-wall 插件安装到目标 Vibe Kanban 项目中。
#
# 用法（由主安装脚本 scripts/install.sh 调用）：
#   ./plugins/auth-wall/install.sh <vibe-kanban 源码目录>
#
# 流程：
#   1. 将 auth-wall 源码复制到 <vibe-kanban>/crates/auth-wall/
#   2. 编译后端（含 auth-wall feature）
#   3. 编译 set-password 工具
# ============================================================================

set -euo pipefail

# ── 颜色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ️  [auth-wall] $*${NC}"; }
ok()    { echo -e "${GREEN}✅ [auth-wall] $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  [auth-wall] $*${NC}"; }
fail()  { echo -e "${RED}❌ [auth-wall] $*${NC}"; exit 1; }

# ── 参数 ────────────────────────────────────────────────────────────────────
[[ $# -lt 1 ]] && fail "用法: $0 <vibe-kanban 源码目录>"
VK_DIR="$(cd "$1" && pwd)"

# 当前插件源码所在目录
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_WALL_DIR="$VK_DIR/crates/auth-wall"
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$VK_DIR/target}"

# ── 注册清理钩子 ────────────────────────────────────────────────────────────
# 注意：如果由主安装脚本调用，清理由主脚本统一管理
# 这里也提供独立运行时的清理
if [[ "${VKP_MANAGED:-false}" != "true" ]]; then
    cleanup() {
        if [[ -d "$AUTH_WALL_DIR" ]]; then
            info "清理 auth-wall 源码..."
            rm -rf "$AUTH_WALL_DIR"
            ok "auth-wall 已从源码目录中移除，源代码保持干净。"
        fi
    }
    trap cleanup EXIT
fi

# ── Step 1: 复制源码 ────────────────────────────────────────────────────────
info "=== 安装 auth-wall 插件 ==="

[[ ! -f "$PLUGIN_DIR/Cargo.toml" ]] && fail "在 $PLUGIN_DIR 中找不到 Cargo.toml，插件源码不完整。"

if [[ -d "$AUTH_WALL_DIR" ]]; then
    warn "$AUTH_WALL_DIR 已存在，将备份后重新复制..."
    mv "$AUTH_WALL_DIR" "${AUTH_WALL_DIR}.bak.$(date +%s)"
fi

mkdir -p "$AUTH_WALL_DIR"
info "复制 auth-wall 源码 -> $AUTH_WALL_DIR ..."
cp "$PLUGIN_DIR/Cargo.toml" "$AUTH_WALL_DIR/"
cp -r "$PLUGIN_DIR/src" "$AUTH_WALL_DIR/"

# 复制工具链配置（如果插件目录或项目根有）
PROJECT_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
[[ -f "$PROJECT_ROOT/rust-toolchain.toml" ]] && cp "$PROJECT_ROOT/rust-toolchain.toml" "$AUTH_WALL_DIR/"
[[ -f "$PROJECT_ROOT/rustfmt.toml" ]] && cp "$PROJECT_ROOT/rustfmt.toml" "$AUTH_WALL_DIR/"

# 验证
[[ ! -f "$AUTH_WALL_DIR/Cargo.toml" ]] && fail "复制的 auth-wall 中找不到 Cargo.toml。"
ok "auth-wall 插件源码已就位。"

# ── Step 2: 编译 ────────────────────────────────────────────────────────────
# 仅在非 SKIP_BUILD 模式下编译
if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    info "构建 Rust 后端（带 auth-wall feature）..."
    (cd "$VK_DIR" && cargo build --release --bin server --features auth-wall)
    ok "server 编译完成（含 auth-wall）。"

    info "构建 set-password 密码设置工具..."
    (cd "$VK_DIR" && cargo build --release --bin set-password --features auth-wall)
    ok "set-password 编译完成。"
fi

ok "auth-wall 插件安装完成！"
