#!/bin/bash
# CC-Mem 插件安装脚本
# 用法: curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/install-plugin.sh | bash

set -e

OWNER="haiyuan-ai"
REPO="cc-mem"
CHANNEL="main"
CLAUDE_DIR="${HOME}/.claude/plugins"
# Claude Code 期望的 marketplace 目录名格式: owner-repo
MARKETPLACE_NAME="${OWNER}-${REPO}"
INSTALL_DIR="${CLAUDE_DIR}/marketplaces/${MARKETPLACE_NAME}"
TMP_INSTALL_DIR=""
BACKUP_INSTALL_DIR=""

cleanup_tmp_install() {
    if [ -n "$TMP_INSTALL_DIR" ] && [ -d "$TMP_INSTALL_DIR" ]; then
        rm -rf "$TMP_INSTALL_DIR"
    fi
}

cleanup_backup_install() {
    if [ -n "$BACKUP_INSTALL_DIR" ] && [ -d "$BACKUP_INSTALL_DIR" ]; then
        rm -rf "$BACKUP_INSTALL_DIR"
    fi
}

rollback_install() {
    cleanup_tmp_install
    if [ -n "$BACKUP_INSTALL_DIR" ] && [ -d "$BACKUP_INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR" ]; then
        mv "$BACKUP_INSTALL_DIR" "$INSTALL_DIR" 2>/dev/null || true
    fi
}

trap 'rollback_install' EXIT

echo "📦 安装 CC-Mem (${CHANNEL})..."

# 检查依赖
if ! command -v git &> /dev/null; then
    echo "❌ 错误: 需要安装 git"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "⚠️  警告: 未检测到 jq。将尝试使用 Python 处理插件注册，但 hooks 自动注入/捕获能力仍建议安装 jq。"
    HAS_JQ=false
else
    HAS_JQ=true
fi

if ! command -v python3 &> /dev/null; then
    HAS_PYTHON=false
else
    HAS_PYTHON=true
fi

# 1. 克隆仓库到临时目录，成功后再替换现有安装
if [ -d "$INSTALL_DIR" ]; then
    echo "  检测到现有安装，准备安全更新..."
fi

mkdir -p "${CLAUDE_DIR}/marketplaces"
TMP_INSTALL_DIR=$(mktemp -d "${CLAUDE_DIR}/marketplaces/.${MARKETPLACE_NAME}.tmp.XXXXXX")
echo "  克隆仓库..."
git clone --depth 1 "https://github.com/${OWNER}/${REPO}.git" "$TMP_INSTALL_DIR"

if [ ! -x "$TMP_INSTALL_DIR/bin/ccmem-cli.sh" ]; then
    echo "❌ 错误: 克隆结果不完整，缺少 bin/ccmem-cli.sh"
    exit 1
fi

# 1.1 确保脚本具有执行权限（跨平台 clone 后更稳）
chmod +x "$TMP_INSTALL_DIR"/bin/*.sh 2>/dev/null || true
chmod +x "$TMP_INSTALL_DIR"/hooks/*.sh 2>/dev/null || true
chmod +x "$TMP_INSTALL_DIR"/mcp/*.py 2>/dev/null || true

if [ -d "$INSTALL_DIR" ]; then
    BACKUP_INSTALL_DIR="${INSTALL_DIR}.prev"
    rm -rf "$BACKUP_INSTALL_DIR"
    mv "$INSTALL_DIR" "$BACKUP_INSTALL_DIR"
fi
mv "$TMP_INSTALL_DIR" "$INSTALL_DIR"
TMP_INSTALL_DIR=""
cleanup_backup_install
BACKUP_INSTALL_DIR=""

# 2. 初始化数据库
echo "  初始化数据库..."
"${INSTALL_DIR}/bin/ccmem-cli.sh" init 2>/dev/null || true

# 3. 注册 Marketplace
echo "  注册 marketplace..."
MARKETPLACES_FILE="${CLAUDE_DIR}/known_marketplaces.json"
mkdir -p "${CLAUDE_DIR}"

if [ ! -f "$MARKETPLACES_FILE" ]; then
    echo '{}' > "$MARKETPLACES_FILE"
fi

# 生成 ISO 8601 时间戳（兼容 macOS 和 Linux）
if date --version 2>/dev/null | grep -q GNU; then
    # Linux
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
else
    # macOS - %3N 不可用，使用秒级精度
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

if [ "$HAS_JQ" = true ]; then
    TMP_FILE=$(mktemp)
    jq --arg name "$MARKETPLACE_NAME" --arg repo "${OWNER}/${REPO}" --arg path "$INSTALL_DIR" --arg date "$TIMESTAMP" '
        .[$name] = {
            "source": {"source": "github", "repo": $repo},
            "installLocation": $path,
            "lastUpdated": $date
        }
    ' "$MARKETPLACES_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$MARKETPLACES_FILE"
else
    # 基本 JSON 处理（无 jq）
    cat > /tmp/ccmem_marketplace.json << EOF
{"${MARKETPLACE_NAME}":{"source":{"source":"github","repo":"${OWNER}/${REPO}"},"installLocation":"${INSTALL_DIR}","lastUpdated":"${TIMESTAMP}"}}
EOF
    # 简单合并（假设文件格式正确）
    if [ "$HAS_PYTHON" = true ]; then
    python3 -c "
import json, sys
with open('$MARKETPLACES_FILE', 'r') as f:
    data = json.load(f)
with open('/tmp/ccmem_marketplace.json', 'r') as f:
    new_data = json.load(f)
data.update(new_data)
with open('$MARKETPLACES_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || echo "⚠️  请手动编辑 ${MARKETPLACES_FILE} 添加 marketplace 配置"
    else
        echo "⚠️  未检测到 python3，无法自动写入 ${MARKETPLACES_FILE}，请按 README 手动添加 marketplace 配置"
    fi
fi

# 4. 注册已安装插件
echo "  注册已安装插件..."
INSTALLED_FILE="${CLAUDE_DIR}/installed_plugins.json"

if [ ! -f "$INSTALLED_FILE" ]; then
    echo '{"version": 2, "plugins": {}}' > "$INSTALLED_FILE"
fi

COMMIT_SHA=$(cd "$INSTALL_DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown")
SHORT_SHA=$(printf '%s' "$COMMIT_SHA" | cut -c1-7)
INSTALL_VERSION="$CHANNEL"
DISPLAY_VERSION="$CHANNEL@$SHORT_SHA"

if [ "$HAS_JQ" = true ]; then
    TMP_FILE=$(mktemp)
    jq --arg name "$MARKETPLACE_NAME" --arg path "$INSTALL_DIR" --arg version "$INSTALL_VERSION" --arg sha "$COMMIT_SHA" --arg date "$TIMESTAMP" '
        .plugins["cc-mem@" + $name] = [{
            "scope": "user",
            "installPath": $path,
            "version": $version,
            "installedAt": $date,
            "lastUpdated": $date,
            "gitCommitSha": $sha
        }]
    ' "$INSTALLED_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$INSTALLED_FILE"
else
    cat > /tmp/ccmem_installed.json << EOF
{"cc-mem@${MARKETPLACE_NAME}":[{"scope":"user","installPath":"${INSTALL_DIR}","version":"${INSTALL_VERSION}","installedAt":"${TIMESTAMP}","lastUpdated":"${TIMESTAMP}","gitCommitSha":"${COMMIT_SHA}"}]}
EOF
    if [ "$HAS_PYTHON" = true ]; then
    python3 -c "
import json, sys
with open('$INSTALLED_FILE', 'r') as f:
    data = json.load(f)
with open('/tmp/ccmem_installed.json', 'r') as f:
    new_data = json.load(f)
if 'plugins' not in data:
    data['plugins'] = {}
data['plugins'].update(new_data)
with open('$INSTALLED_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || echo "⚠️  请手动编辑 ${INSTALLED_FILE} 添加插件配置"
    else
        echo "⚠️  未检测到 python3，无法自动写入 ${INSTALLED_FILE}，请按 README 手动添加已安装插件配置"
    fi
fi

echo ""
echo "✅ CC-Mem ${DISPLAY_VERSION} 安装完成！"
echo ""
echo "📍 安装位置: ${INSTALL_DIR}"
echo ""
echo "🚀 使用方法:"
echo "   ${INSTALL_DIR}/bin/ccmem-cli.sh status    # 查看状态"
echo "   ${INSTALL_DIR}/bin/ccmem-cli.sh --help    # 查看帮助"
if [ "$HAS_JQ" = false ]; then
    echo ""
    echo "⚠️  建议补装 jq 以启用完整 hooks 能力："
    echo "   macOS: brew install jq"
    echo "   Ubuntu/Debian: sudo apt-get install jq"
fi
echo ""
echo "⚠️  请重启 Claude Code 以激活 hooks:"
echo "   1. 按 Ctrl+D 或输入 exit"
echo "   2. 重新运行 claude"
echo ""
echo "📋 重启后运行 /plugin 可查看:"
echo "   Marketplace: ● ${MARKETPLACE_NAME}"
echo "   Installed:   ● cc-mem ${DISPLAY_VERSION}"
trap - EXIT
