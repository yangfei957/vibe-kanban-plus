#!/usr/bin/env bash
# ============================================================================
# install.sh — vibe-kanban-plus 主安装脚本
#
# 统一入口，调度各插件的安装脚本。
#
# 用法：
#   ./scripts/install.sh <vibe-kanban 源码目录> [插件名 ...]
#
# 示例：
#   ./scripts/install.sh ~/code/vibe-kanban                 # 安装所有插件
#   ./scripts/install.sh ~/code/vibe-kanban auth-wall       # 仅安装 auth-wall
#   ./scripts/install.sh ~/code/vibe-kanban auth-wall foo   # 安装 auth-wall 和 foo
#   ./scripts/install.sh --list                             # 列出可用插件
#   ./scripts/install.sh --help                             # 显示帮助
#
# 环境变量（可选）：
#   SKIP_FRONTEND      跳过前端构建（默认：false）
#   SKIP_BUILD         跳过编译步骤，只复制源码（默认：false）
#   CARGO_TARGET_DIR   自定义 Cargo 输出目录
# ============================================================================

set -euo pipefail

# ── 颜色 ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail()  { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── 定位项目根目录 ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGINS_DIR="$PROJECT_ROOT/plugins"

# ── 发现可用插件 ────────────────────────────────────────────────────────────
# 可用插件 = plugins/ 目录下包含 install.sh 的子目录
discover_plugins() {
    local plugins=()
    if [[ -d "$PLUGINS_DIR" ]]; then
        for dir in "$PLUGINS_DIR"/*/; do
            [[ -f "${dir}install.sh" ]] && plugins+=("$(basename "$dir")")
        done
    fi
    echo "${plugins[@]}"
}

list_plugins() {
    echo -e "${BOLD}可用插件（plugins/）：${NC}"
    echo ""
    local found=false
    if [[ -d "$PLUGINS_DIR" ]]; then
        for dir in "$PLUGINS_DIR"/*/; do
            local name
            name="$(basename "$dir")"
            if [[ -f "${dir}install.sh" ]]; then
                local desc=""
                # 尝试从 Cargo.toml 读取描述
                if [[ -f "${dir}Cargo.toml" ]]; then
                    desc=$(grep -m1 '^description' "${dir}Cargo.toml" 2>/dev/null | sed 's/^description *= *"\(.*\)"/\1/' || true)
                fi
                echo -e "  ${GREEN}●${NC} ${BOLD}${name}${NC}"
                [[ -n "$desc" ]] && echo -e "    ${desc}"
                found=true
            fi
        done
    fi
    if [[ "$found" == "false" ]]; then
        echo -e "  ${YELLOW}（无可用插件）${NC}"
    fi
    echo ""
}

# ── 帮助信息 ────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}vibe-kanban-plus 插件安装脚本${NC}

${BOLD}用法:${NC}
  $0 <vibe-kanban 源码目录> [插件名 ...]
  $0 --list
  $0 --help

${BOLD}参数:${NC}
  <vibe-kanban 源码目录>    目标 Vibe Kanban 项目的路径
  [插件名 ...]              要安装的插件名称（可多个），不指定则安装全部

${BOLD}选项:${NC}
  --list, -l                列出所有可用插件
  --help, -h                显示此帮助信息

${BOLD}环境变量（可选）：${NC}
  SKIP_FRONTEND             跳过前端构建（默认：false）
  SKIP_BUILD                跳过编译步骤，只复制源码（默认：false）
  CARGO_TARGET_DIR          自定义 Cargo 输出目录

${BOLD}示例:${NC}
  $0 ~/code/vibe-kanban                     # 安装所有插件
  $0 ~/code/vibe-kanban auth-wall           # 仅安装 auth-wall
  SKIP_BUILD=true $0 ~/code/vibe-kanban     # 只复制源码，不编译

EOF
    list_plugins
    exit 0
}

# ── 参数解析 ────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage

case "${1:-}" in
    --help|-h)
        usage
        ;;
    --list|-l)
        list_plugins
        exit 0
        ;;
esac

VK_DIR="$(cd "$1" && pwd)" || fail "无法访问目录: $1"
shift

[[ ! -f "$VK_DIR/Cargo.toml" ]] && fail "在 $VK_DIR 中找不到 Cargo.toml，请确认这是 vibe-kanban 源码目录。"

CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$VK_DIR/target}"
SKIP_FRONTEND="${SKIP_FRONTEND:-false}"

# 确定要安装的插件列表
AVAILABLE_PLUGINS=($(discover_plugins))
if [[ ${#AVAILABLE_PLUGINS[@]} -eq 0 ]]; then
    fail "未发现任何可用插件。请确认 $PLUGINS_DIR 目录下有包含 install.sh 的插件子目录。"
fi

if [[ $# -gt 0 ]]; then
    # 指定了插件名称
    SELECTED_PLUGINS=("$@")
    # 验证指定的插件是否存在
    for plugin in "${SELECTED_PLUGINS[@]}"; do
        if [[ ! -f "$PLUGINS_DIR/$plugin/install.sh" ]]; then
            fail "插件 '$plugin' 不存在或缺少 install.sh。"
        fi
    done
else
    # 未指定则安装全部
    SELECTED_PLUGINS=("${AVAILABLE_PLUGINS[@]}")
fi

# ── 环境依赖检测 ────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "${BOLD}  vibe-kanban-plus 插件安装器${NC}"
echo "============================================================"
echo ""

info "目标源码目录: $VK_DIR"
info "待安装插件: ${SELECTED_PLUGINS[*]}"
echo ""

info "=== 检测编译环境 ==="

# --- Git ---
command -v git >/dev/null 2>&1 || fail "缺少 git，请先安装 git。"
ok "git: $(git --version)"

# --- Rust / Cargo ---
REQUIRED_TOOLCHAIN="nightly-2025-12-04"

if ! command -v rustup >/dev/null 2>&1; then
    warn "未检测到 Rust，正在安装 rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain none
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
fi

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
        fail "Node.js $NODE_VERSION 版本过低（需要 >= $MIN_NODE_MAJOR），请升级。"
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

# ── 前端构建 ────────────────────────────────────────────────────────────────
if [[ "$SKIP_FRONTEND" != "true" ]]; then
    info "=== 安装前端依赖 ==="
    (cd "$VK_DIR" && pnpm install --frozen-lockfile 2>/dev/null || pnpm install)
    ok "前端依赖安装完成。"
    echo ""
    info "=== 构建前端 ==="
    (cd "$VK_DIR/packages/local-web" && pnpm run build)
    ok "前端构建完成。"
else
    info "跳过前端构建（SKIP_FRONTEND=true）"
fi
echo ""

# ── 清理列表（统一在 EXIT 时清理所有已安装的插件目录） ──────────────────────
CLEANUP_DIRS=()

cleanup_all() {
    for dir in "${CLEANUP_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            info "清理 $(basename "$dir") 源码..."
            rm -rf "$dir"
            ok "$(basename "$dir") 已从源码目录中移除。"
        fi
    done
    if [[ ${#CLEANUP_DIRS[@]} -gt 0 ]]; then
        ok "所有插件源码已清理，目标仓库保持干净。"
    fi
}
trap cleanup_all EXIT

# ── 依次安装各插件 ──────────────────────────────────────────────────────────
export VKP_MANAGED=true  # 告知子脚本由主脚本管理清理
export CARGO_TARGET_DIR
export SKIP_FRONTEND

INSTALLED=0
FAILED=0

for plugin in "${SELECTED_PLUGINS[@]}"; do
    echo ""
    echo "────────────────────────────────────────────────────────────"
    info "安装插件: ${BOLD}$plugin${NC}"
    echo "────────────────────────────────────────────────────────────"

    PLUGIN_INSTALL_SCRIPT="$PLUGINS_DIR/$plugin/install.sh"

    # 记录要清理的目录
    CLEANUP_DIRS+=("$VK_DIR/crates/$plugin")

    if bash "$PLUGIN_INSTALL_SCRIPT" "$VK_DIR"; then
        ok "插件 $plugin 安装成功！"
        INSTALLED=$((INSTALLED + 1))
    else
        warn "插件 $plugin 安装失败！"
        FAILED=$((FAILED + 1))
    fi
done

echo ""

# ── 额外编译任务（非插件特定的） ────────────────────────────────────────────
if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    # 编译 MCP binary（如果存在）
    if (cd "$VK_DIR" && cargo metadata --format-version=1 2>/dev/null | grep -q '"name":"vibe-kanban-mcp"'); then
        info "构建 vibe-kanban-mcp..."
        (cd "$VK_DIR" && cargo build --release --bin vibe-kanban-mcp) && ok "vibe-kanban-mcp 编译完成。"
    fi
fi

# ── 打包成品 ────────────────────────────────────────────────────────────────
if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
    info "=== 打包成品 ==="

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)        ARCH_LABEL="x64"   ;;
        arm64|aarch64) ARCH_LABEL="arm64" ;;
        *)             ARCH_LABEL="$ARCH" ;;
    esac
    case "$OS" in
        linux)  OS_LABEL="linux" ;;
        darwin) OS_LABEL="macos" ;;
        *)      OS_LABEL="$OS"   ;;
    esac
    PLATFORM="${OS_LABEL}-${ARCH_LABEL}"
    DIST_DIR="$VK_DIR/npx-cli/dist/$PLATFORM"
    mkdir -p "$DIST_DIR"

    for bin_name in server set-password vibe-kanban-mcp review; do
        BIN_PATH="$CARGO_TARGET_DIR/release/$bin_name"
        if [[ -f "$BIN_PATH" ]]; then
            case "$bin_name" in
                server)   ZIP_NAME="vibe-kanban" ;;
                review)   ZIP_NAME="vibe-kanban-review" ;;
                *)        ZIP_NAME="$bin_name" ;;
            esac
            cp "$BIN_PATH" "$VK_DIR/$ZIP_NAME"
            (cd "$VK_DIR" && zip -q "$ZIP_NAME.zip" "$ZIP_NAME" && rm -f "$ZIP_NAME")
            mv "$VK_DIR/$ZIP_NAME.zip" "$DIST_DIR/"
        fi
    done

    echo ""
    echo "📁 成品文件位于: $DIST_DIR/"
    ls -lh "$DIST_DIR/" 2>/dev/null || true
fi

# ── 总结 ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
ok "安装完成！已安装 $INSTALLED 个插件，失败 $FAILED 个。"
echo "============================================================"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
