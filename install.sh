#!/bin/bash
# CC-Mem Plugin Installation Script
# Usage: curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/install.sh | bash

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

echo "📦 Installing CC-Mem (${CHANNEL})..."

# Check dependencies
if ! command -v git &> /dev/null; then
    echo "❌ Error: git is required"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "⚠️  Warning: jq not detected. Will try using Python for plugin registration, but hooks auto-injection/capture features recommend installing jq."
    HAS_JQ=false
else
    HAS_JQ=true
fi

if ! command -v python3 &> /dev/null; then
    HAS_PYTHON=false
else
    HAS_PYTHON=true
fi

# 1. Clone repo to temp dir, then replace existing install
if [ -d "$INSTALL_DIR" ]; then
    echo "  Detected existing installation, preparing safe update..."
fi

mkdir -p "${CLAUDE_DIR}/marketplaces"
TMP_INSTALL_DIR=$(mktemp -d "${CLAUDE_DIR}/marketplaces/.${MARKETPLACE_NAME}.tmp.XXXXXX")
echo "  Cloning repository..."
git clone --depth 1 "https://github.com/${OWNER}/${REPO}.git" "$TMP_INSTALL_DIR"

if [ ! -x "$TMP_INSTALL_DIR/bin/ccmem-cli.sh" ]; then
    echo "❌ Error: Clone incomplete, missing bin/ccmem-cli.sh"
    exit 1
fi

# 1.1 Ensure scripts have execute permission (more stable across platforms after clone)
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

# 2. Initialize database
echo "  Initializing database..."
"${INSTALL_DIR}/bin/ccmem-cli.sh" init 2>/dev/null || true

# 2.5 Install Skill
echo "  Installing Skill..."
SKILL_DIR="${HOME}/.claude/skills"
SKILL_SOURCE="${INSTALL_DIR}/skill/cc-mem.md"
mkdir -p "$SKILL_DIR"
if [ -f "$SKILL_SOURCE" ]; then
    cp "$SKILL_SOURCE" "$SKILL_DIR/cc-mem.md"
    echo "    ✅ Skill installed"
else
    echo "    ⚠️  Skill file not found, skipping"
fi

# 3. Register Marketplace
echo "  Registering marketplace..."
MARKETPLACES_FILE="${CLAUDE_DIR}/known_marketplaces.json"
mkdir -p "${CLAUDE_DIR}"

if [ ! -f "$MARKETPLACES_FILE" ]; then
    echo '{}' > "$MARKETPLACES_FILE"
fi

# Generate ISO 8601 timestamp (compatible with macOS and Linux)
if date --version 2>/dev/null | grep -q GNU; then
    # Linux
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
else
    # macOS - %3N not available, use second-level precision
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
    # Basic JSON handling (no jq)
    cat > /tmp/ccmem_marketplace.json << EOF
{"${MARKETPLACE_NAME}":{"source":{"source":"github","repo":"${OWNER}/${REPO}"},"installLocation":"${INSTALL_DIR}","lastUpdated":"${TIMESTAMP}"}}
EOF
    # Simple merge (assume file format is correct)
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
" 2>/dev/null || echo "⚠️  Please manually edit ${MARKETPLACES_FILE} to add marketplace config"
    else
        echo "⚠️  python3 not detected, cannot auto-write ${MARKETPLACES_FILE}. Please manually add marketplace config per README"
    fi
fi

# 4. Register installed plugin
echo "  Registering installed plugin..."
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
" 2>/dev/null || echo "⚠️  Please manually edit ${INSTALLED_FILE} to add plugin config"
    else
        echo "⚠️  python3 not detected, cannot auto-write ${INSTALLED_FILE}. Please manually add installed plugin config per README"
    fi
fi

echo ""
echo "✅ CC-Mem ${DISPLAY_VERSION} installation complete!"
echo ""
echo "📍 Install location: ${INSTALL_DIR}"
echo "🎯 Skill location: ~/.claude/skills/cc-mem.md"
echo ""
echo "🚀 Quick start:"
echo "   CLI:  ${INSTALL_DIR}/bin/ccmem-cli.sh status    # Check status"
echo "   CLI:  ${INSTALL_DIR}/bin/ccmem-cli.sh --help    # Show help"
echo "   Skill: /cc-mem list                             # List memories"
echo "   Skill: /cc-mem status                           # Check status"
echo "   Skill: /ccmem search <keyword>                  # Search memories"
if [ "$HAS_JQ" = false ]; then
    echo ""
    echo "⚠️  Recommended: install jq for full hooks capabilities:"
    echo "   macOS: brew install jq"
    echo "   Ubuntu/Debian: sudo apt-get install jq"
fi
echo ""
echo "⚠️  Please restart Claude Code to activate hooks and Skill:"
echo "   1. Press Ctrl+D or type exit"
echo "   2. Run claude again"
echo ""
echo "📋 After restart:"
echo "   /plugin          - Check plugin status"
echo "   /cc-mem          - Use Skill shortcuts"
trap - EXIT
