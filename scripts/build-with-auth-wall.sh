#!/usr/bin/env bash
# ============================================================================
# build-with-auth-wall.sh
#
# 一键编译带 auth-wall 功能的 Vibe Kanban。
#
# 用法：
#   ./build-with-auth-wall.sh /path/to/vibe-kanban
#
# 脚本流程：
#   1. 克隆 auth-wall 源码到 crates/auth-wall/
#   2. 检测并安装缺失的编译依赖（Rust nightly、Node.js、pnpm）
#   3. 编译前端 + 后端（含 auth-wall feature）
#   4. 输出成品文件路径
#   5. 清理 auth-wall 源码，保持仓库无污染
# ============================================================================

set -euo pipefail

# ── 颜色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail()  { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── 参数解析 ────────────────────────────────────────────────────────────────
AUTH_WALL_REPO="${AUTH_WALL_REPO:-https://github.com/yangfei957/vibe-kanban-plus.git}"
AUTH_WALL_BRANCH="${AUTH_WALL_BRANCH:-main}"
SKIP_FRONTEND="${SKIP_FRONTEND:-false}"

usage() {
  cat <<EOF
用法: $0 <vibe-kanban 源码目录>

环境变量（可选）：
  AUTH_WALL_REPO     auth-wall Git 仓库地址（默认：$AUTH_WALL_REPO）
  AUTH_WALL_BRANCH   auth-wall 分支（默认：$AUTH_WALL_BRANCH）
  SKIP_FRONTEND      跳过前端构建（默认：false）
  CARGO_TARGET_DIR   自定义 Cargo 输出目录

示例：
  $0 ~/code/vibe-kanban
  AUTH_WALL_BRANCH=dev $0 ~/code/vibe-kanban
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage
VK_DIR="$(cd "$1" && pwd)"
[[ ! -f "$VK_DIR/Cargo.toml" ]] && fail "在 $VK_DIR 中找不到 Cargo.toml，请确认这是 vibe-kanban 源码目录。"

AUTH_WALL_DIR="$VK_DIR/crates/auth-wall"
CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$VK_DIR/target}"

# ── 清理钩子 ────────────────────────────────────────────────────────────────
CLEANUP_NEEDED=false

cleanup() {
  if [[ "$CLEANUP_NEEDED" == "true" && -d "$AUTH_WALL_DIR/.git" ]]; then
    info "清理 auth-wall 源码..."
    rm -rf "$AUTH_WALL_DIR"
    ok "auth-wall 已从源码目录中移除，源代码保持干净。"
  fi
}

# 无论成功还是失败都执行清理
trap cleanup EXIT

# ── Step 0: 预检 ────────────────────────────────────────────────────────────
info "目标源码目录: $VK_DIR"
echo ""

# ── Step 1: 检测 & 安装依赖 ─────────────────────────────────────────────────
info "=== 步骤 1/5：检测编译环境 ==="

# --- Git ---
command -v git >/dev/null 2>&1 || fail "缺少 git，请先安装 git。"
ok "git: $(git --version)"

# --- Rust / Cargo ---
REQUIRED_TOOLCHAIN="nightly-2025-12-04"

install_rustup() {
  warn "未检测到 Rust，正在安装 rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
}

if ! command -v rustup >/dev/null 2>&1; then
  install_rustup
fi

# 确保需要的 nightly 工具链已安装
if ! rustup toolchain list | grep -q "$REQUIRED_TOOLCHAIN"; then
  warn "未检测到 $REQUIRED_TOOLCHAIN 工具链，正在安装..."
  rustup toolchain install "$REQUIRED_TOOLCHAIN" --profile default \
    --component rustfmt rustc rust-analyzer rust-src rust-std cargo
fi
ok "Rust 工具链: $REQUIRED_TOOLCHAIN"

# --- Node.js ---
MIN_NODE_MAJOR=20

if command -v node >/dev/null 2>&1; then
  NODE_VERSION=$(node -v | sed 's/v//')
  NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
  if [[ "$NODE_MAJOR" -lt "$MIN_NODE_MAJOR" ]]; then
    warn "Node.js $NODE_VERSION 版本过低（需要 >= $MIN_NODE_MAJOR），请升级。"
    fail "Node.js 版本不满足要求。"
  fi
  ok "Node.js: v$NODE_VERSION"
else
  fail "缺少 Node.js (>= $MIN_NODE_MAJOR)，请先安装。推荐使用 nvm：https://github.com/nvm-sh/nvm"
fi

# --- pnpm ---
if ! command -v pnpm >/dev/null 2>&1; then
  warn "未检测到 pnpm，正在通过 corepack 启用..."
  if command -v corepack >/dev/null 2>&1; then
    corepack enable
    corepack prepare pnpm@latest --activate
  else
    npm install -g pnpm
  fi
fi
ok "pnpm: $(pnpm --version)"

echo ""

# ── Step 2: 克隆 auth-wall ──────────────────────────────────────────────────
info "=== 步骤 2/5：安装 auth-wall 插件 ==="

if [[ -d "$AUTH_WALL_DIR/.git" ]]; then
  warn "检测到 $AUTH_WALL_DIR 已存在（含 .git），将更新..."
  (cd "$AUTH_WALL_DIR" && git fetch origin && git checkout "$AUTH_WALL_BRANCH" && git pull origin "$AUTH_WALL_BRANCH")
else
  if [[ -d "$AUTH_WALL_DIR" ]]; then
    # 目录存在但不是 git 仓库 — 可能是旧的残留
    warn "$AUTH_WALL_DIR 已存在但非 git 仓库，将备份后重新克隆..."
    mv "$AUTH_WALL_DIR" "${AUTH_WALL_DIR}.bak.$(date +%s)"
  fi
  info "克隆 auth-wall ($AUTH_WALL_BRANCH) -> $AUTH_WALL_DIR ..."
  git clone --branch "$AUTH_WALL_BRANCH" --depth 1 "$AUTH_WALL_REPO" "$AUTH_WALL_DIR"
fi

CLEANUP_NEEDED=true

# 快速验证 auth-wall crate
[[ ! -f "$AUTH_WALL_DIR/Cargo.toml" ]] && fail "克隆的 auth-wall 中找不到 Cargo.toml。"
ok "auth-wall 插件已就位。"
echo ""

# ── Step 3: 安装前端依赖 ────────────────────────────────────────────────────
if [[ "$SKIP_FRONTEND" != "true" ]]; then
  info "=== 步骤 3/5：安装前端依赖 ==="
  (cd "$VK_DIR" && pnpm install --frozen-lockfile 2>/dev/null || pnpm install)
  ok "前端依赖安装完成。"
else
  info "=== 步骤 3/5：跳过前端构建（SKIP_FRONTEND=true）==="
fi
echo ""

# ── Step 4: 编译 ────────────────────────────────────────────────────────────
info "=== 步骤 4/5：编译 Vibe Kanban + auth-wall ==="

# 检测平台
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_LABEL="x64"   ;;
  arm64|aarch64) ARCH_LABEL="arm64" ;;
  *) ARCH_LABEL="$ARCH" ;;
esac
case "$OS" in
  linux)  OS_LABEL="linux" ;;
  darwin) OS_LABEL="macos" ;;
  *)      OS_LABEL="$OS"   ;;
esac
PLATFORM="${OS_LABEL}-${ARCH_LABEL}"
info "平台: $PLATFORM"

# 构建前端
if [[ "$SKIP_FRONTEND" != "true" ]]; then
  info "构建前端..."
  (cd "$VK_DIR/packages/local-web" && pnpm run build)
  ok "前端构建完成。"
fi

# 构建 Rust 后端（含 auth-wall feature）
info "构建 Rust 后端（带 auth-wall）..."
export VK_SHARED_API_BASE="${VK_SHARED_API_BASE:-https://api.vibekanban.com}"
export VITE_VK_SHARED_API_BASE="${VITE_VK_SHARED_API_BASE:-https://api.vibekanban.com}"
(cd "$VK_DIR" && cargo build --release --bin server --features auth-wall)
ok "server 编译完成。"

# 编译 set-password 工具
info "构建 set-password 密码设置工具..."
(cd "$VK_DIR" && cargo build --release --bin set-password --features auth-wall)
ok "set-password 编译完成。"

# 编译 MCP binary
info "构建 vibe-kanban-mcp..."
(cd "$VK_DIR" && cargo build --release --bin vibe-kanban-mcp)
ok "vibe-kanban-mcp 编译完成。"

echo ""

# ── Step 5: 打包 & 输出 ─────────────────────────────────────────────────────
info "=== 步骤 5/5：打包成品 ==="

DIST_DIR="$VK_DIR/npx-cli/dist/$PLATFORM"
mkdir -p "$DIST_DIR"

# server
SERVER_BIN="$CARGO_TARGET_DIR/release/server"
if [[ -f "$SERVER_BIN" ]]; then
  cp "$SERVER_BIN" "$VK_DIR/vibe-kanban"
  (cd "$VK_DIR" && zip -q vibe-kanban.zip vibe-kanban && rm -f vibe-kanban)
  mv "$VK_DIR/vibe-kanban.zip" "$DIST_DIR/"
fi

# set-password
SET_PW_BIN="$CARGO_TARGET_DIR/release/set-password"
if [[ -f "$SET_PW_BIN" ]]; then
  cp "$SET_PW_BIN" "$VK_DIR/set-password"
  (cd "$VK_DIR" && zip -q set-password.zip set-password && rm -f set-password)
  mv "$VK_DIR/set-password.zip" "$DIST_DIR/"
fi

# vibe-kanban-mcp
MCP_BIN="$CARGO_TARGET_DIR/release/vibe-kanban-mcp"
if [[ -f "$MCP_BIN" ]]; then
  cp "$MCP_BIN" "$VK_DIR/vibe-kanban-mcp"
  (cd "$VK_DIR" && zip -q vibe-kanban-mcp.zip vibe-kanban-mcp && rm -f vibe-kanban-mcp)
  mv "$VK_DIR/vibe-kanban-mcp.zip" "$DIST_DIR/"
fi

# review
REVIEW_BIN="$CARGO_TARGET_DIR/release/review"
if [[ -f "$REVIEW_BIN" ]]; then
  cp "$REVIEW_BIN" "$VK_DIR/vibe-kanban-review"
  (cd "$VK_DIR" && zip -q vibe-kanban-review.zip vibe-kanban-review && rm -f vibe-kanban-review)
  mv "$VK_DIR/vibe-kanban-review.zip" "$DIST_DIR/"
fi

echo ""
echo "============================================================"
ok "构建完成！"
echo "============================================================"
echo ""
echo "📁 成品文件位于:"
echo "   $DIST_DIR/"
echo ""
ls -lh "$DIST_DIR/" 2>/dev/null || true
echo ""
echo "📍 二进制文件（未打包）:"
echo "   server:         $CARGO_TARGET_DIR/release/server"
echo "   set-password:   $CARGO_TARGET_DIR/release/set-password"
echo "   vibe-kanban-mcp: $CARGO_TARGET_DIR/release/vibe-kanban-mcp"
echo ""
echo "🔐 使用方式："
echo "   1. 设置密码:  $CARGO_TARGET_DIR/release/set-password"
echo "   2. 启动服务:  $CARGO_TARGET_DIR/release/server"
echo "   3. 打开浏览器访问即可看到登录页面"
echo ""

# cleanup 函数会在 EXIT 时自动运行，移除 crates/auth-wall/
info "源码清理将在退出时自动执行..."
