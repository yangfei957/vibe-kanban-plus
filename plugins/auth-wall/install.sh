#!/usr/bin/env bash
# ============================================================================
# auth-wall/install.sh
#
# auth-wall 插件的安装 / 卸载脚本。
#
# 用法（由主安装脚本 scripts/install.sh 调用）：
#   ./plugins/auth-wall/install.sh install   <vibe-kanban 源码目录>
#   ./plugins/auth-wall/install.sh uninstall <vibe-kanban 源码目录>
#
# install   — 将 auth-wall 源码复制到 <vibe-kanban>/crates/auth-wall/
# uninstall — 从 <vibe-kanban>/crates/auth-wall/ 移除插件源码
#
# 注意：编译由主安装脚本统一执行，此脚本只负责源码的安装与清理。
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

# ── 参数解析 ────────────────────────────────────────────────────────────────
usage() { fail "用法: $0 {install|uninstall} <vibe-kanban 源码目录>"; }
[[ $# -lt 2 ]] && usage

ACTION="$1"
VK_DIR="$(cd "$2" && pwd)" || fail "无法访问目录: $2"

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_WALL_DIR="$VK_DIR/crates/auth-wall"

# ── install ─────────────────────────────────────────────────────────────────
do_install() {
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

    # 复制工具链配置（如果项目根有）
    PROJECT_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
    [[ -f "$PROJECT_ROOT/rust-toolchain.toml" ]] && cp "$PROJECT_ROOT/rust-toolchain.toml" "$AUTH_WALL_DIR/"
    [[ -f "$PROJECT_ROOT/rustfmt.toml" ]] && cp "$PROJECT_ROOT/rustfmt.toml" "$AUTH_WALL_DIR/"

    # 验证
    [[ ! -f "$AUTH_WALL_DIR/Cargo.toml" ]] && fail "复制的 auth-wall 中找不到 Cargo.toml。"
    ok "auth-wall 插件源码已安装到 $AUTH_WALL_DIR"
}

# ── uninstall ───────────────────────────────────────────────────────────────
do_uninstall() {
    if [[ -d "$AUTH_WALL_DIR" ]]; then
        info "清理 auth-wall 源码..."
        rm -rf "$AUTH_WALL_DIR"
        ok "auth-wall 已从 $VK_DIR 中移除，源代码保持干净。"
    else
        info "auth-wall 目录不存在，无需清理。"
    fi
}

# ── 执行 ────────────────────────────────────────────────────────────────────
case "$ACTION" in
    install)   do_install   ;;
    uninstall) do_uninstall ;;
    *)         usage        ;;
esac
