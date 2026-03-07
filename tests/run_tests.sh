#!/bin/bash
# CC-Mem 测试运行器
# 用法：bash run_tests.sh [test_file]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$SCRIPT_DIR/tests"

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║            CC-Mem 测试套件                                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# 设置测试环境
export TEST_MODE=true
export TEST_DB_DIR="/tmp/cc-mem-test-$$"
mkdir -p "$TEST_DB_DIR"

# 清理函数
cleanup() {
    rm -rf "$TEST_DB_DIR"
    echo ""
    echo "已清理测试临时文件"
}
trap cleanup EXIT

# 运行所有测试
run_all_tests() {
    local failed=0

    echo "运行测试文件..."
    echo ""

    # 运行 SQLite 测试
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 SQLite 库测试"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if bash "$TESTS_DIR/test_sqlite.sh" 2>&1; then
        echo ""
        echo "✅ SQLite 测试通过"
    else
        echo ""
        echo "❌ SQLite 测试失败"
        failed=$((failed + 1))
    fi

    echo ""
    echo ""

    # 运行边界条件测试
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 边界条件测试"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if bash "$TESTS_DIR/test_edge_cases.sh" 2>&1; then
        echo ""
        echo "✅ 边界条件测试通过"
    else
        echo ""
        echo "❌ 边界条件测试失败"
        failed=$((failed + 1))
    fi

    echo ""
    echo ""

    # 运行 CLI 测试
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 CLI 命令测试"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if bash "$TESTS_DIR/test_cli.sh"; then
        echo ""
        echo "✅ CLI 测试通过"
    else
        echo ""
        echo "❌ CLI 测试失败"
        failed=$((failed + 1))
    fi

    echo ""
    echo ""

    # 运行 Hooks 测试
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 Hooks 功能测试"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if bash "$TESTS_DIR/test_hooks.sh"; then
        echo ""
        echo "✅ Hooks 测试通过"
    else
        echo ""
        echo "❌ Hooks 测试失败"
        failed=$((failed + 1))
    fi

    echo ""
    echo ""

    # 运行 MCP 测试
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 MCP Server 测试"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if bash "$TESTS_DIR/test_mcp.sh"; then
        echo ""
        echo "✅ MCP 测试通过"
    else
        echo ""
        echo "❌ MCP 测试失败"
        failed=$((failed + 1))
    fi

    echo ""
    echo ""

    # 运行扩展 smoke test
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 扩展 Smoke Test"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if bash "$TESTS_DIR/test_extensions.sh"; then
        echo ""
        echo "✅ 扩展 smoke test 通过"
    else
        echo ""
        echo "❌ 扩展 smoke test 失败"
        failed=$((failed + 1))
    fi

    return $failed
}

# 运行单个测试文件
run_single_test() {
    local test_file="$1"

    if [ ! -f "$test_file" ]; then
        echo "❌ 测试文件不存在：$test_file"
        exit 1
    fi

    echo "运行测试：$test_file"
    echo ""
    bash "$test_file"
}

# 主入口
main() {
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "用法：$0 [test_file]"
        echo ""
        echo "参数:"
        echo "  test_file    要运行的测试文件（可选）"
        echo "               不指定则运行所有测试"
        echo ""
        echo "示例:"
        echo "  $0                         # 运行所有测试"
        echo "  $0 tests/test_sqlite.sh    # 运行 SQLite 测试"
        echo "  $0 tests/test_cli.sh       # 运行 CLI 测试"
        echo "  $0 tests/test_hooks.sh     # 运行 Hooks 测试"
        echo "  $0 tests/test_mcp.sh       # 运行 MCP 测试"
        echo "  $0 tests/test_extensions.sh # 运行扩展 smoke test"
        exit 0
    fi

    if [ -n "$1" ]; then
        # 运行单个测试
        run_single_test "$1"
    else
        # 运行所有测试
        run_all_tests
        exit_code=$?

        echo ""
        echo "═══════════════════════════════════════════════════"
        if [ $exit_code -eq 0 ]; then
            echo "🎉 所有测试通过！"
        else
            echo "⚠️  有 $exit_code 个测试套件失败"
        fi
        echo "═══════════════════════════════════════════════════"

        exit $exit_code
    fi
}

main "$@"
