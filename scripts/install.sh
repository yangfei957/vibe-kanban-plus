#!/usr/bin/env bash
# ============================================================================
# install.sh — vibe-kanban-plus 主安装脚本
#
# 统一入口，负责：
#   1. 环境检测与依赖安装（Rust nightly、Node.js、pnpm）
#   2. 前端构建
#   3. 调度各插件的 install 动作（仅复制源码）
#   4. 集中编译后端（收集所有插件的 features）
#   5. 打包成品
#   6. 调度各插件的 uninstall 动作（清理源码，避免污染 vibe-kanban）
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
SKIP_BUILD="${SKIP_BUILD:-false}"

# 确定要安装的插件列表
mapfile -t AVAILABLE_PLUGINS < <(discover_plugins | tr ' ' '\n')
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

# ── 安全网：无论脚本如何退出都清理插件源码 ──────────────────────────────────
# 正常退出时在脚本末尾显式调用 uninstall；异常退出时由此 trap 兜底清理
cleanup_on_exit() {
    for plugin in "${SELECTED_PLUGINS[@]}"; do
        local script="$PLUGINS_DIR/$plugin/install.sh"
        if [[ -f "$script" ]]; then
            bash "$script" uninstall "$VK_DIR" 2>/dev/null || true
        fi
    done
}
trap cleanup_on_exit EXIT

# ════════════════════════════════════════════════════════════════════════════
# Phase 1: 环境检测与依赖安装
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "============================================================"
echo -e "${BOLD}  vibe-kanban-plus 插件安装器${NC}"
echo "============================================================"
echo ""

info "目标源码目录: $VK_DIR"
info "待安装插件: ${SELECTED_PLUGINS[*]}"
echo ""

info "=== Phase 1: 检测编译环境 ==="

# --- Git ---
command -v git >/dev/null 2>&1 || fail "缺少 git，请先安装 git。"
ok "git: $(git --version)"

# --- Rust / Cargo ---
# 参考 vibe-kanban 的 rust-toolchain.toml：nightly-2025-12-04
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
# 参考 vibe-kanban README：Node.js >= 20
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
# 参考 vibe-kanban README：pnpm >= 8
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

# ════════════════════════════════════════════════════════════════════════════
# Phase 2: 前端构建
# ════════════════════════════════════════════════════════════════════════════
if [[ "$SKIP_FRONTEND" != "true" ]]; then
    info "=== Phase 2: 构建前端 ==="
    info "安装前端依赖..."
    (cd "$VK_DIR" && { pnpm install --frozen-lockfile 2>/dev/null || pnpm install; })
    ok "前端依赖安装完成。"
    echo ""
    info "构建前端..."
    (cd "$VK_DIR/packages/local-web" && pnpm run build)
    ok "前端构建完成。"
else
    info "=== Phase 2: 跳过前端构建（SKIP_FRONTEND=true）==="
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Phase 3: 安装所有插件源码
# ════════════════════════════════════════════════════════════════════════════
info "=== Phase 3: 安装插件源码 ==="

INSTALLED_PLUGINS=()   # 成功安装的插件列表
FAILED_PLUGINS=()      # 安装失败的插件列表

for plugin in "${SELECTED_PLUGINS[@]}"; do
    echo ""
    echo "────────────────────────────────────────────────────────────"
    info "安装插件源码: ${BOLD}$plugin${NC}"
    echo "────────────────────────────────────────────────────────────"

    PLUGIN_INSTALL_SCRIPT="$PLUGINS_DIR/$plugin/install.sh"

    if bash "$PLUGIN_INSTALL_SCRIPT" install "$VK_DIR"; then
        ok "插件 $plugin 源码安装成功！"
        INSTALLED_PLUGINS+=("$plugin")
    else
        warn "插件 $plugin 源码安装失败！"
        FAILED_PLUGINS+=("$plugin")
    fi
done
echo ""

# 如果没有任何插件安装成功，跳过编译
if [[ ${#INSTALLED_PLUGINS[@]} -eq 0 ]]; then
    fail "没有任何插件安装成功，终止。"
fi

# ════════════════════════════════════════════════════════════════════════════
# Phase 4: 集中编译（收集所有插件的 features 和 bins）
# ════════════════════════════════════════════════════════════════════════════
if [[ "$SKIP_BUILD" != "true" ]]; then
    info "=== Phase 4: 集中编译 ==="

    # 收集所有已安装插件的 features 和额外 bins
    ALL_FEATURES=()
    ALL_EXTRA_BINS=()

    for plugin in "${INSTALLED_PLUGINS[@]}"; do
        PLUGIN_CONF="$PLUGINS_DIR/$plugin/plugin.conf"
        if [[ -f "$PLUGIN_CONF" ]]; then
            # 在子 shell 中读取配置，避免变量污染
            CARGO_FEATURES=""
            CARGO_BINS=""
            # shellcheck source=/dev/null
            source "$PLUGIN_CONF"
            # 收集 features
            if [[ -n "$CARGO_FEATURES" ]]; then
                for f in $CARGO_FEATURES; do
                    ALL_FEATURES+=("$f")
                done
            fi
            # 收集额外 bins
            if [[ -n "$CARGO_BINS" ]]; then
                for b in $CARGO_BINS; do
                    ALL_EXTRA_BINS+=("$b")
                done
            fi
        else
            info "插件 $plugin 没有 plugin.conf，跳过编译配置收集。"
        fi
    done

    FEATURES_CSV=""
    if [[ ${#ALL_FEATURES[@]} -gt 0 ]]; then
        FEATURES_CSV=$(IFS=,; echo "${ALL_FEATURES[*]}")
        info "收集到的 features: $FEATURES_CSV"
    fi
    if [[ ${#ALL_EXTRA_BINS[@]} -gt 0 ]]; then
        info "收集到的额外 bins: ${ALL_EXTRA_BINS[*]}"
    fi
    echo ""

    # 4a. 编译 server（带所有插件 features）
    info "构建 Rust 后端 server..."
    if [[ -n "$FEATURES_CSV" ]]; then
        (cd "$VK_DIR" && cargo build --release --bin server --features "$FEATURES_CSV")
        ok "server 编译完成（features: $FEATURES_CSV）。"
    else
        (cd "$VK_DIR" && cargo build --release --bin server)
        ok "server 编译完成。"
    fi

    # 4b. 编译插件声明的额外 bins（带所有插件 features）
    for bin_name in "${ALL_EXTRA_BINS[@]}"; do
        info "构建 $bin_name..."
        if [[ -n "$FEATURES_CSV" ]]; then
            (cd "$VK_DIR" && cargo build --release --bin "$bin_name" --features "$FEATURES_CSV")
        else
            (cd "$VK_DIR" && cargo build --release --bin "$bin_name")
        fi
        ok "$bin_name 编译完成。"
    done

    # 4c. 编译 vibe-kanban 自身的其他标准 bins（不需要插件 features）
    if (cd "$VK_DIR" && cargo metadata --format-version=1 2>/dev/null | grep -q '"name":"vibe-kanban-mcp"'); then
        info "构建 vibe-kanban-mcp..."
        (cd "$VK_DIR" && cargo build --release --bin vibe-kanban-mcp) && ok "vibe-kanban-mcp 编译完成。"
    fi

    echo ""

    # ════════════════════════════════════════════════════════════════════════
    # Phase 5: 打包成品
    # ════════════════════════════════════════════════════════════════════════
    info "=== Phase 5: 打包成品 ==="

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

    # 标准 bins + 插件声明的 bins
    PACKAGE_BINS=("server" "vibe-kanban-mcp" "review" "${ALL_EXTRA_BINS[@]}")
    for bin_name in "${PACKAGE_BINS[@]}"; do
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

else
    info "=== Phase 4: 跳过编译（SKIP_BUILD=true）==="
    info "=== Phase 5: 跳过打包（SKIP_BUILD=true）==="
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# Phase 6: 清理所有插件源码（避免污染 vibe-kanban）
# ════════════════════════════════════════════════════════════════════════════
info "=== Phase 6: 清理插件源码 ==="

for plugin in "${INSTALLED_PLUGINS[@]}"; do
    PLUGIN_INSTALL_SCRIPT="$PLUGINS_DIR/$plugin/install.sh"
    bash "$PLUGIN_INSTALL_SCRIPT" uninstall "$VK_DIR" || warn "插件 $plugin 清理失败，请手动检查。"
done

ok "所有插件源码已清理，vibe-kanban 源代码保持干净。"

# 清理完成后移除 EXIT trap（不需要再兜底清理了）
trap - EXIT

echo ""

# ── 总结 ────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
ok "安装完成！成功 ${#INSTALLED_PLUGINS[@]} 个，失败 ${#FAILED_PLUGINS[@]} 个。"
echo "============================================================"

if [[ ${#FAILED_PLUGINS[@]} -gt 0 ]]; then
    warn "以下插件安装失败: ${FAILED_PLUGINS[*]}"
    exit 1
fi
