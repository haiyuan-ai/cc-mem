#!/bin/bash
# CC-Mem Uninstallation Script
# Usage: curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/uninstall.sh | bash

set -e

OWNER="haiyuan-ai"
REPO="cc-mem"
MARKETPLACE_NAME="${OWNER}-${REPO}"
CLAUDE_DIR="${HOME}/.claude/plugins"
INSTALL_DIR="${CLAUDE_DIR}/marketplaces/${MARKETPLACE_NAME}"
SKILL_DIR="${HOME}/.claude/skills/cc-mem"

echo "🗑️  Uninstalling CC-Mem..."

# 1. Remove plugin directory
if [ -d "$INSTALL_DIR" ]; then
    echo "  Removing plugin directory: ${INSTALL_DIR}"
    rm -rf "$INSTALL_DIR"
    echo "    ✅ Plugin removed"
else
    echo "    ⚠️  Plugin directory not found, skipping"
fi

# 2. Remove Skill
if [ -d "$SKILL_DIR" ]; then
    echo "  Removing Skill: ${SKILL_DIR}"
    rm -rf "$SKILL_DIR"
    echo "    ✅ Skill removed"
else
    echo "    ⚠️  Skill directory not found, skipping"
fi

# 3. Clean up marketplace registration (optional)
MARKETPLACES_FILE="${CLAUDE_DIR}/known_marketplaces.json"
if [ -f "$MARKETPLACES_FILE" ] && command -v jq &> /dev/null; then
    echo "  Cleaning up marketplace registration..."
    if jq -e ".${MARKETPLACE_NAME}" "$MARKETPLACES_FILE" &> /dev/null; then
        TMP_FILE=$(mktemp)
        jq "del(.${MARKETPLACE_NAME})" "$MARKETPLACES_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$MARKETPLACES_FILE"
        echo "    ✅ Marketplace registration cleaned"
    else
        echo "    ℹ️  No entry in marketplace"
    fi
fi

# 4. Clean up installed plugin registration
INSTALLED_FILE="${CLAUDE_DIR}/installed_plugins.json"
PLUGIN_KEY="cc-mem@${MARKETPLACE_NAME}"
if [ -f "$INSTALLED_FILE" ] && command -v jq &> /dev/null; then
    echo "  Cleaning up installed plugin registration..."
    if jq -e ".plugins.${PLUGIN_KEY}" "$INSTALLED_FILE" &> /dev/null; then
        TMP_FILE=$(mktemp)
        jq "del(.plugins.${PLUGIN_KEY})" "$INSTALLED_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$INSTALLED_FILE"
        echo "    ✅ Plugin registration cleaned"
    else
        echo "    ℹ️  No entry in installed plugins"
    fi
fi

echo ""
echo "✅ CC-Mem uninstallation complete!"
echo ""
echo "📋 Note:"
echo "   Database file preserved by default: ~/.claude/cc-mem/memory.db"
echo "   To remove, manually run: rm -rf ~/.claude/cc-mem/"
echo ""
echo "⚠️  Please restart Claude Code to complete:"
echo "   1. Press Ctrl+D or type exit"
echo "   2. Run claude again"
