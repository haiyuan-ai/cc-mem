#!/bin/bash
# CC-Mem Compatibility Check Script
# Usage: bash check-compat.sh

echo "=== CC-Mem Compatibility Check ==="
echo ""

# System info
SYSTEM=$(uname -s)
echo "System: $SYSTEM $(uname -r)"

# Git Bash detection
if [[ "$SYSTEM" == "MSYS"* ]] || [[ "$SYSTEM" == "MINGW"* ]]; then
    echo "Environment: Git Bash for Windows"
    echo "HOME: $HOME (USERPROFILE: $USERPROFILE)"
else
    echo "Bash version: $(bash --version 2>&1 | head -1)"
fi
echo ""

# Dependency check
echo "=== Dependency Check ==="

check_command() {
    local cmd="$1"
    local required="$2"

    if command -v "$cmd" &> /dev/null; then
        # Try to get version, handle BSD/GNU differences
        local version=""
        if "$cmd" --version &> /dev/null; then
            version=$("$cmd" --version 2>&1 | head -1)
        elif "$cmd" -V &> /dev/null; then
            version=$("$cmd" -V 2>&1 | head -1)
        else
            version="installed"
        fi
        echo "  ✅ $cmd: $version"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo "  ❌ $cmd: not installed (required)"
            return 1
        else
            echo "  ⚠️  $cmd: not installed (optional)"
            return 1
        fi
    fi
}

# Required dependencies
check_command "sqlite3" "required"
check_command "bash" "required"
check_command "grep" "required"
check_command "sed" "required"

# Optional dependencies
echo ""
echo "=== Optional Features ==="
check_command "perl" "optional"  # Private content filtering
check_command "du" "optional"    # Database size
check_command "jq" "optional"    # Hooks JSON parsing

# Check date command compatibility
echo ""
echo "=== Date Command Compatibility ==="
if date -Iseconds &> /dev/null; then
    echo "  ✅ ISO 8601 format: supported (date -Iseconds)"
else
    echo "  ⚠️  ISO 8601 format: not supported, using fallback"
    echo "     Fallback: $(date +%Y-%m-%dT%H:%M:%S%z)"
fi

if date +%s &> /dev/null; then
    echo "  ✅ Unix timestamp: supported (date +%s)"
else
    echo "  ❌ Unix timestamp: not supported"
fi

# Check /dev/urandom
echo ""
echo "=== Random Number Generation ==="
if [ -e /dev/urandom ]; then
    echo "  ✅ /dev/urandom: available"
else
    echo "  ⚠️  /dev/urandom: not available, alternative needed"
fi

# SQLite FTS5 support
echo ""
echo "=== SQLite FTS5 Support ==="
if sqlite3 ":memory:" "CREATE VIRTUAL TABLE t USING fts5(content);" 2>/dev/null; then
    echo "  ✅ FTS5: supported"
else
    echo "  ⚠️  FTS5: not supported (full-text search will be unavailable)"
fi

echo ""
echo "=== Check Complete ==="
