#!/bin/bash
# CC-Mem Git Bash Compatibility Test Script
# Usage: Run in Git Bash: bash test-git-bash.sh

echo "=============================================="
echo "     CC-Mem Git Bash Compatibility Test"
echo "=============================================="
echo ""

PASS=0
FAIL=0
WARN=0

# Test function
test_case() {
    local name="$1"
    local result="$2"

    if [ "$result" -eq 0 ]; then
        echo "  ✅ PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

warn_case() {
    local name="$1"
    echo "  ⚠️  WARN: $name"
    WARN=$((WARN + 1))
}

# 1. Environment detection
echo "=== 1. Environment Info ==="
echo "  uname -s: $(uname -s)"
echo "  uname -r: $(uname -r)"
echo "  Bash version: $(bash --version 2>&1 | head -1)"
echo "  HOME: $HOME"
echo "  USERPROFILE: ${USERPROFILE:-not set}"
echo ""

if [[ "$(uname -s)" == "MSYS"* ]] || [[ "$(uname -s)" == "MINGW"* ]]; then
    echo "  ✅ Git Bash environment detected"
    test_case "Git Bash environment detection" 0
else
    echo "  ⚠️  Not Git Bash environment, some tests may be inaccurate"
    warn_case "Non-Git Bash environment"
fi
echo ""

# 2. Path handling tests
echo "=== 2. Path Handling Tests ==="

# Test HOME path
if [ -n "$HOME" ]; then
    test_case "HOME variable set" 0
else
    test_case "HOME variable set" 1
fi

# Test USERPROFILE (Git Bash specific)
if [ -n "$USERPROFILE" ]; then
    test_case "USERPROFILE variable set" 0
else
    warn_case "USERPROFILE variable not set (OK, may not be Git Bash)"
fi

# Test path existence
TEST_DIR="$HOME/.claude/cc-mem"
if [ -d "$TEST_DIR" ] || [[ "$(uname -s)" != "MSYS"* && "$(uname -s)" != "MINGW"* ]]; then
    test_case "Directory path accessible" 0
else
    test_case "Directory path accessible" 1
fi
echo ""

# 3. Command compatibility tests
echo "=== 3. Command Compatibility Tests ==="

# sqlite3
if command -v sqlite3 &> /dev/null; then
    test_case "sqlite3 command available" 0
else
    test_case "sqlite3 command available" 1
    echo "     Hint: choco install sqlite"
fi

# grep
if echo "test" | grep -o "e" &> /dev/null; then
    test_case "grep -o available" 0
else
    test_case "grep -o available" 1
fi

# sed
if echo "test" | sed 's/test/ok/' &> /dev/null; then
    test_case "sed substitution available" 0
else
    test_case "sed substitution available" 1
fi

# date
if date +%s &> /dev/null; then
    test_case "date +%s available" 0
else
    test_case "date +%s available" 1
fi

# date -Iseconds (optional)
if date -Iseconds &> /dev/null 2>&1; then
    test_case "date -Iseconds available" 0
else
    warn_case "date -Iseconds not available (OK, cc-mem has fallback)"
fi

# du
if du -h "$HOME" &> /dev/null 2>&1; then
    test_case "du -h available" 0
else
    warn_case "du -h not available (cc-mem has fallback)"
fi

# /dev/urandom
if [ -e /dev/urandom ]; then
    test_case "/dev/urandom available" 0
else
    warn_case "/dev/urandom not available (cc-mem uses \$RANDOM fallback)"
fi
echo ""

# 4. cc-mem script loading tests
echo "=== 4. cc-mem Script Loading Tests ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCMEM_DIR="$(dirname "$SCRIPT_DIR")"

# Test sqlite.sh loading
if [ -f "$CCMEM_DIR/lib/sqlite.sh" ]; then
    # Try loading (not executing)
    if bash -n "$CCMEM_DIR/lib/sqlite.sh" 2>&1; then
        test_case "sqlite.sh syntax check" 0
    else
        test_case "sqlite.sh syntax check" 1
    fi
else
    test_case "sqlite.sh file exists" 1
fi

# Test ccmem-cli.sh loading
if [ -f "$CCMEM_DIR/bin/ccmem-cli.sh" ]; then
    if bash -n "$CCMEM_DIR/bin/ccmem-cli.sh" 2>&1; then
        test_case "ccmem-cli.sh syntax check" 0
    else
        test_case "ccmem-cli.sh syntax check" 1
    fi
else
    test_case "ccmem-cli.sh file exists" 1
fi
echo ""

# 5. Actual function tests (if database exists)
echo "=== 5. Actual Function Tests ==="

if [ -f "$HOME/.claude/cc-mem/memory.db" ]; then
    # Test database connection
    RESULT=$(sqlite3 "$HOME/.claude/cc-mem/memory.db" "SELECT COUNT(*) FROM memories;" 2>&1)
    if [ $? -eq 0 ]; then
        test_case "SQLite database connection" 0
        echo "     Memory count: $RESULT"
    else
        test_case "SQLite database connection" 1
        echo "     Error: $RESULT"
    fi

    # Test ccmem-cli.sh status
    if [ -x "$CCMEM_DIR/bin/ccmem-cli.sh" ]; then
        OUTPUT=$("$CCMEM_DIR/bin/ccmem-cli.sh" status 2>&1)
        if echo "$OUTPUT" | grep -q "Memories"; then
            test_case "ccmem-cli.sh status runs" 0
        else
            test_case "ccmem-cli.sh status runs" 1
        fi
    fi
else
    warn_case "Database not found, skipping function tests"
    echo "     Hint: Run ccmem-cli.sh init to initialize"
fi
echo ""

# 6. Git Bash specific tests
echo "=== 6. Git Bash Specific Tests ==="

if [[ "$(uname -s)" == "MSYS"* ]] || [[ "$(uname -s)" == "MINGW"* ]]; then
    # Only run in Git Bash

    # Test path conversion
    if command -v cygpath &> /dev/null; then
        WIN_PATH=$(cygpath -w "$HOME" 2>&1)
        if [ $? -eq 0 ]; then
            test_case "cygpath path conversion" 0
            echo "     Windows path: $WIN_PATH"
        else
            test_case "cygpath path conversion" 1
        fi
    else
        warn_case "cygpath not available"
    fi

    # Test USERPROFILE fallback
    if [ -n "$USERPROFILE" ] && [ "$HOME" = "$USERPROFILE" ]; then
        test_case "HOME=USERPROFILE fallback" 0
    else
        warn_case "HOME=USERPROFILE fallback not triggered"
    fi
else
    echo "  (Git Bash specific tests only)"
    echo ""
fi

# Summary
echo "=============================================="
echo "     Test Summary"
echo "=============================================="
echo "  ✅ PASS: $PASS"
echo "  ⚠️  WARN: $WARN"
echo "  ❌ FAIL: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "  🎉 All tests passed! cc-mem can run in Git Bash."
    exit 0
else
    echo "  ⚠️  $FAIL test(s) failed, please check output above."
    exit 1
fi
