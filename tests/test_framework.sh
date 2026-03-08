#!/bin/bash
# CC-Mem 测试框架
# 基于 bash 的单元测试框架，使用 Red/Green TDD 方式

# 获取脚本目录（测试框架自身路径检测）
TEST_FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试统计
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 测试数据库路径（使用临时数据库）
TEST_DB_DIR="/tmp/cc-mem-test-$$"
TEST_DB="$TEST_DB_DIR/test-memory.db"
TEST_CONFIG_TEMPLATE="$TEST_FRAMEWORK_DIR/config.json"
TEST_RUNTIME_CONFIG="$TEST_DB_DIR/ccmem_test_config.json"

# 测试辅助函数
setup_test_db() {
    mkdir -p "$TEST_DB_DIR"
    export CCMEM_CONFIG_FILE="$TEST_RUNTIME_CONFIG"
    mkdir -p "$TEST_DB_DIR/exports"
    cp "$TEST_CONFIG_TEMPLATE" "$TEST_RUNTIME_CONFIG"
    python3 - <<PY
import json
path = "$TEST_RUNTIME_CONFIG"
with open(path) as f:
    data = json.load(f)
data["memory_db"] = "$TEST_DB"
data["failed_queue_dir"] = "$TEST_DB_DIR/failed_queue"
data["debug_log"] = "$TEST_DB_DIR/debug.log"
data["memory"]["markdown_export_path"] = "$TEST_DB_DIR/exports"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

    # 加载 sqlite.sh 并初始化数据库（使用测试框架自身路径）
    source "$TEST_FRAMEWORK_DIR/../lib/sqlite.sh"
    init_db
}

cleanup_test_db() {
    unset CCMEM_CONFIG_FILE
    rm -rf "$TEST_DB_DIR"
}

db_query() {
    local sql="$1"
    sqlite3 "$TEST_DB" "$sql"
}

create_test_dir() {
    local prefix="${1:-cc-mem-test}"
    local dir="/tmp/${prefix}_$$"
    mkdir -p "$dir"
    echo "$dir"
}

require_command_or_skip() {
    local command_name="$1"
    local reason="${2:-$command_name 未安装，跳过此测试}"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        skip_test "$reason"
        return 1
    fi

    return 0
}

# 断言函数
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -n "$value" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message (value is empty)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}


assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo -e "  Looking for: $needle"
        echo -e "  In: $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -f "$file" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message (file not found: $file)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_executable() {
    local file="$1"
    local message="${2:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -x "$file" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message (file not executable: $file)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_false() {
    local value="$1"
    local message="${2:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$value" = "false" ] || [ "$value" = "0" ] || [ "$value" = "no" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message (value is not false)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_less_than() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$actual" -lt "$expected" ] 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo -e "  Expected less than: $expected"
        echo -e "  Actual:   $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if eval "$condition"; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message (condition is false)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}: $message"
        echo -e "  Unexpected: $needle"
        echo -e "  In: $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# 测试组函数
describe() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

it() {
    echo ""
    echo -e "${YELLOW}  ▶ $1${NC}"
}

# 测试报告
print_summary() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  测试报告${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  总测试数：${YELLOW}$TESTS_RUN${NC}"
    echo -e "  通过：${GREEN}$TESTS_PASSED${NC}"
    echo -e "  失败：${RED}$TESTS_FAILED${NC}"
    echo -e "  跳过：$TESTS_SKIPPED"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ 所有测试通过！${NC}"
        return 0
    else
        echo -e "${RED}❌ 有 $TESTS_FAILED 个测试失败${NC}"
        return 1
    fi
}

# 跳过测试
skip_test() {
    local reason="${1:-}"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${YELLOW}⊘ SKIP${NC}: $reason"
}

# 主入口
run_tests() {
    local script_name="$1"

    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  CC-Mem 测试套件                                          ║${NC}"
    echo -e "${BLUE}║  $script_name${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"

    # 设置测试环境
    setup_test_db
}

# 清理函数（在脚本退出时调用）
cleanup() {
    cleanup_test_db
}

# 注册清理陷阱
trap cleanup EXIT
