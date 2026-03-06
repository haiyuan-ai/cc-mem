#!/bin/bash
# CC-Mem 插件安装脚本
# 用法: curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/install-plugin.sh | bash

set -e

OWNER="haiyuan-ai"
REPO="cc-mem"
VERSION="1.4.0"
CLAUDE_DIR="${HOME}/.claude/plugins"
INSTALL_DIR="${CLAUDE_DIR}/marketplaces/${OWNER}"

echo "📦 安装 CC-Mem ${VERSION}..."

# 检查依赖
if ! command -v git &> /dev/null; then
    echo "❌ 错误: 需要安装 git"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "⚠️  警告: 未检测到 jq，将使用基本 JSON 处理"
    HAS_JQ=false
else
    HAS_JQ=true
fi

# 1. 克隆仓库
if [ -d "$INSTALL_DIR" ]; then
    echo "  检测到现有安装，正在更新..."
    rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR"
echo "  克隆仓库..."
git clone --depth 1 "https://github.com/${OWNER}/${REPO}.git" "$INSTALL_DIR"

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

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)

if [ "$HAS_JQ" = true ]; then
    TMP_FILE=$(mktemp)
    jq --arg owner "$OWNER" --arg repo "${OWNER}/${REPO}" --arg path "$INSTALL_DIR" --arg date "$TIMESTAMP" '
        .[$owner] = {
            "source": {"source": "github", "repo": $repo},
            "installLocation": $path,
            "lastUpdated": $date
        }
    ' "$MARKETPLACES_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$MARKETPLACES_FILE"
else
    # 基本 JSON 处理（无 jq）
    cat > /tmp/ccmem_marketplace.json << EOF
{"${OWNER}":{"source":{"source":"github","repo":"${OWNER}/${REPO}"},"installLocation":"${INSTALL_DIR}","lastUpdated":"${TIMESTAMP}"}}
EOF
    # 简单合并（假设文件格式正确）
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
fi

# 4. 注册已安装插件
echo "  注册已安装插件..."
INSTALLED_FILE="${CLAUDE_DIR}/installed_plugins.json"

if [ ! -f "$INSTALLED_FILE" ]; then
    echo '{"version": 2, "plugins": {}}' > "$INSTALLED_FILE"
fi

COMMIT_SHA=$(cd "$INSTALL_DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown")

if [ "$HAS_JQ" = true ]; then
    TMP_FILE=$(mktemp)
    jq --arg owner "$OWNER" --arg path "$INSTALL_DIR" --arg version "$VERSION" --arg sha "$COMMIT_SHA" --arg date "$TIMESTAMP" '
        .plugins["cc-mem@" + $owner] = [{
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
{"cc-mem@${OWNER}":[{"scope":"user","installPath":"${INSTALL_DIR}","version":"${VERSION}","installedAt":"${TIMESTAMP}","lastUpdated":"${TIMESTAMP}","gitCommitSha":"${COMMIT_SHA}"}]}
EOF
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
fi

echo ""
echo "✅ CC-Mem ${VERSION} 安装完成！"
echo ""
echo "📍 安装位置: ${INSTALL_DIR}"
echo ""
echo "🚀 使用方法:"
echo "   ccmem-cli.sh status    # 查看状态"
echo "   ccmem-cli.sh --help    # 查看帮助"
echo ""
echo "⚠️  请重启 Claude Code 以激活 hooks:"
echo "   1. 按 Ctrl+D 或输入 exit"
echo "   2. 重新运行 claude"
echo ""
echo "📋 重启后运行 /plugin 可查看:"
echo "   Marketplace: ● haiyuan-ai"
echo "   Installed:   ● cc-mem v${VERSION}"
