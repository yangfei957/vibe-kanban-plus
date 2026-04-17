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

# ── Cargo.toml 补丁辅助 ──────────────────────────────────────────────────────
# 用于在 do_uninstall 时精确定位并删除本插件添加的行
PATCH_MARKER="# vibe-kanban-plus:auth-wall"

# 在 workspace Cargo.toml 的 members 数组中添加 crates/auth-wall
patch_workspace_add() {
    local workspace_toml="$1"
    # 若已存在则跳过
    if grep -q '"crates/auth-wall"' "$workspace_toml" 2>/dev/null; then
        info "workspace 已包含 crates/auth-wall，跳过添加。"
        return 0
    fi
    python3 - "$workspace_toml" "$PATCH_MARKER" <<'PYEOF'
import sys, re
toml_path, marker = sys.argv[1], sys.argv[2]
with open(toml_path) as f:
    content = f.read()
# 在 members = [...] 数组的末尾 ] 之前插入新成员
match = re.search(r'(members\s*=\s*\[)(.*?)(\])', content, re.DOTALL)
if not match:
    sys.exit(1)
new_line = f'    "crates/auth-wall", {marker}\n'
insert_pos = match.start(3)
content = content[:insert_pos] + new_line + content[insert_pos:]
with open(toml_path, 'w') as f:
    f.write(content)
PYEOF
    ok "已将 crates/auth-wall 添加到 workspace members。"
}

# 从 workspace Cargo.toml 中删除本插件添加的成员行
patch_workspace_remove() {
    local workspace_toml="$1"
    if grep -q "$PATCH_MARKER" "$workspace_toml" 2>/dev/null; then
        sed -i.bak "/$PATCH_MARKER/d" "$workspace_toml" && rm -f "${workspace_toml}.bak"
        info "已从 workspace members 移除 crates/auth-wall。"
    fi
}

# 找到 server crate 的 Cargo.toml（在 $VK_DIR/crates 下查找 name = "server"）
find_server_cargo() {
    find "$VK_DIR/crates" -name "Cargo.toml" 2>/dev/null | while IFS= read -r toml; do
        if grep -qE '^name\s*=\s*"server"' "$toml" 2>/dev/null; then
            echo "$toml"
            return
        fi
    done
}

# 在 server Cargo.toml 中添加 auth-wall 可选依赖与 feature
patch_server_cargo_add() {
    local server_toml="$1"
    # 若已存在则跳过
    if grep -q 'auth-wall.*optional' "$server_toml" 2>/dev/null; then
        info "server Cargo.toml 已含 auth-wall optional dep，跳过添加。"
        return 0
    fi
    local server_dir rel_path
    server_dir="$(dirname "$server_toml")"
    rel_path="$(python3 -c "import os; print(os.path.relpath('$AUTH_WALL_DIR', '$server_dir'))")"

    python3 - "$server_toml" "$rel_path" "$PATCH_MARKER" <<'PYEOF'
import sys, re
toml_path, rel_path, marker = sys.argv[1], sys.argv[2], sys.argv[3]
with open(toml_path) as f:
    content = f.read()

dep_line  = f'auth-wall = {{ path = "{rel_path}", optional = true }} {marker}\n'
feat_line = f'auth-wall = ["dep:auth-wall"] {marker}\n'

# --- 添加到 [dependencies] 节 ---
dep_match = re.search(r'^\[dependencies\]', content, re.MULTILINE)
if dep_match:
    insert = dep_match.end() + 1          # 跳过 \n
    content = content[:insert] + dep_line + content[insert:]
else:
    content += f'\n[dependencies]\n{dep_line}'

# --- 添加到 [features] 节 ---
feat_match = re.search(r'^\[features\]', content, re.MULTILINE)
if feat_match:
    insert = feat_match.end() + 1
    content = content[:insert] + feat_line + content[insert:]
else:
    # 在 [dependencies] 前插入 [features] 节
    dep_match2 = re.search(r'^\[dependencies\]', content, re.MULTILINE)
    if dep_match2:
        content = content[:dep_match2.start()] + f'[features]\n{feat_line}\n' + content[dep_match2.start():]
    else:
        content += f'\n[features]\n{feat_line}'

with open(toml_path, 'w') as f:
    f.write(content)
PYEOF
    ok "已在 server Cargo.toml 中添加 auth-wall 可选依赖与 feature。"
}

# 从 server Cargo.toml 删除本插件添加的行
patch_server_cargo_remove() {
    local server_toml="$1"
    if grep -q "$PATCH_MARKER" "$server_toml" 2>/dev/null; then
        sed -i.bak "/$PATCH_MARKER/d" "$server_toml" && rm -f "${server_toml}.bak"
        info "已从 server Cargo.toml 移除 auth-wall dep/feature。"
    fi
}

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

    # ── 修补目标项目的 Cargo.toml ────────────────────────────────────────────
    info "修补 $VK_DIR/Cargo.toml（添加 workspace 成员）..."
    patch_workspace_add "$VK_DIR/Cargo.toml" \
        || warn "未能自动修补 workspace Cargo.toml，请手动将 \"crates/auth-wall\" 加入 members 列表。"

    info "查找 server crate 的 Cargo.toml..."
    SERVER_CARGO="$(find_server_cargo)"
    if [[ -n "$SERVER_CARGO" ]]; then
        info "找到 server crate: $SERVER_CARGO"
        info "修补 server Cargo.toml（添加 auth-wall 可选依赖与 feature）..."
        patch_server_cargo_add "$SERVER_CARGO" \
            || warn "未能自动修补 server Cargo.toml，请手动添加 auth-wall optional dep 与 feature。"
    else
        warn "未找到 server crate 的 Cargo.toml。如有需要，请手动在 server Cargo.toml 中添加：
  [dependencies]
  auth-wall = { path = \"../auth-wall\", optional = true }
  [features]
  auth-wall = [\"dep:auth-wall\"]"
    fi
}

# ── uninstall ───────────────────────────────────────────────────────────────
do_uninstall() {
    # ── 还原 Cargo.toml 修补 ─────────────────────────────────────────────────
    patch_workspace_remove "$VK_DIR/Cargo.toml"

    SERVER_CARGO="$(find_server_cargo)"
    if [[ -n "$SERVER_CARGO" ]]; then
        patch_server_cargo_remove "$SERVER_CARGO"
    fi

    # ── 移除源码目录 ──────────────────────────────────────────────────────────
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
