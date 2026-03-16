#!/bin/bash
# CC-Mem 卸载脚本
# 用法: curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/uninstall.sh | bash

set -e

OWNER="haiyuan-ai"
REPO="cc-mem"
MARKETPLACE_NAME="${OWNER}-${REPO}"
CLAUDE_DIR="${HOME}/.claude/plugins"
INSTALL_DIR="${CLAUDE_DIR}/marketplaces/${MARKETPLACE_NAME}"
SKILL_FILE="${HOME}/.claude/skills/cc-mem.md"

echo "🗑️  卸载 CC-Mem..."

# 1. 删除插件目录
if [ -d "$INSTALL_DIR" ]; then
    echo "  删除插件目录: ${INSTALL_DIR}"
    rm -rf "$INSTALL_DIR"
    echo "    ✅ 插件已删除"
else
    echo "  ⚠️  插件目录不存在，跳过"
fi

# 2. 删除 Skill
if [ -f "$SKILL_FILE" ]; then
    echo "  删除 Skill: ${SKILL_FILE}"
    rm -f "$SKILL_FILE"
    echo "    ✅ Skill 已删除"
else
    echo "  ⚠️  Skill 文件不存在，跳过"
fi

# 3. 清理 marketplace 注册（可选）
MARKETPLACES_FILE="${CLAUDE_DIR}/known_marketplaces.json"
if [ -f "$MARKETPLACES_FILE" ] && command -v jq &> /dev/null; then
    echo "  清理 marketplace 注册..."
    if jq -e ".${MARKETPLACE_NAME}" "$MARKETPLACES_FILE" &> /dev/null; then
        TMP_FILE=$(mktemp)
        jq "del(.${MARKETPLACE_NAME})" "$MARKETPLACES_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$MARKETPLACES_FILE"
        echo "    ✅ Marketplace 注册已清理"
    else
        echo "    ℹ️  Marketplace 中无此条目"
    fi
fi

# 4. 清理已安装插件注册
INSTALLED_FILE="${CLAUDE_DIR}/installed_plugins.json"
PLUGIN_KEY="cc-mem@${MARKETPLACE_NAME}"
if [ -f "$INSTALLED_FILE" ] && command -v jq &> /dev/null; then
    echo "  清理已安装插件注册..."
    if jq -e ".plugins.${PLUGIN_KEY}" "$INSTALLED_FILE" &> /dev/null; then
        TMP_FILE=$(mktemp)
        jq "del(.plugins.${PLUGIN_KEY})" "$INSTALLED_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$INSTALLED_FILE"
        echo "    ✅ 插件注册已清理"
    else
        echo "    ℹ️  已安装插件列表中无此条目"
    fi
fi

echo ""
echo "✅ CC-Mem 卸载完成！"
echo ""
echo "📋 注意："
echo "   数据库文件默认保留: ~/.claude/cc-mem/memory.db"
echo "   如需删除，请手动执行: rm -rf ~/.claude/cc-mem/"
echo ""
echo "⚠️  请重启 Claude Code 以完全生效:"
echo "   1. 按 Ctrl+D 或输入 exit"
echo "   2. 重新运行 claude"
