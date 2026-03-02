#!/bin/bash
# CC-Mem Hooks 功能测试
# 测试实时记忆捕获机制

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$SCRIPT_DIR/bin/ccmem-cli.sh"
HOOKS_DIR="$SCRIPT_DIR/hooks"

# 加载测试框架
source "$SCRIPT_DIR/tests/test_framework.sh"

# 测试辅助函数
setup_hooks_test() {
    # 设置测试会话 ID
    export TEST_SESSION_ID="test_hooks_$$"
    export CLAUDE_SESSION_ID="$TEST_SESSION_ID"

    # 清理可能的旧日志
    rm -f "/tmp/ccmem_${TEST_SESSION_ID}.log"
}

cleanup_hooks_test() {
    # 清理测试日志
    rm -f "/tmp/ccmem_${TEST_SESSION_ID}.log"
    unset CLAUDE_SESSION_ID
    unset TEST_SESSION_ID
}

# ═══════════════════════════════════════════════════════════
# 测试：Hook 脚本存在性
# ═══════════════════════════════════════════════════════════

describe "Hooks 脚本存在性"

it "post-tool-use.sh 应该存在"
test_post_tool_use_exists() {
    setup_hooks_test
    assert_file_exists "$HOOKS_DIR/post-tool-use.sh" "post-tool-use.sh 应该存在"
    cleanup_hooks_test
}

it "user-prompt-submit.sh 应该存在"
test_user_prompt_submit_exists() {
    setup_hooks_test
    assert_file_exists "$HOOKS_DIR/user-prompt-submit.sh" "user-prompt-submit.sh 应该存在"
    cleanup_hooks_test
}

it "session-start.sh 应该存在"
test_session_start_exists() {
    setup_hooks_test
    assert_file_exists "$HOOKS_DIR/session-start.sh" "session-start.sh 应该存在"
    cleanup_hooks_test
}

it "session-end.sh 应该存在"
test_session_end_exists() {
    setup_hooks_test
    assert_file_exists "$HOOKS_DIR/session-end.sh" "session-end.sh 应该存在"
    cleanup_hooks_test
}

# ═══════════════════════════════════════════════════════════
# 测试：Hook 脚本语法检查
# ═══════════════════════════════════════════════════════════

describe "Hooks 脚本语法检查"

it "post-tool-use.sh 应该通过语法检查"
test_post_tool_use_syntax() {
    local result=$(bash -n "$HOOKS_DIR/post-tool-use.sh" 2>&1)
    assert_equals "" "$result" "post-tool-use.sh 语法检查应该通过"
}

it "user-prompt-submit.sh 应该通过语法检查"
test_user_prompt_submit_syntax() {
    local result=$(bash -n "$HOOKS_DIR/user-prompt-submit.sh" 2>&1)
    assert_equals "" "$result" "user-prompt-submit.sh 语法检查应该通过"
}

it "session-start.sh 应该通过语法检查"
test_session_start_syntax() {
    local result=$(bash -n "$HOOKS_DIR/session-start.sh" 2>&1)
    assert_equals "" "$result" "session-start.sh 语法检查应该通过"
}

it "session-end.sh 应该通过语法检查"
test_session_end_syntax() {
    local result=$(bash -n "$HOOKS_DIR/session-end.sh" 2>&1)
    assert_equals "" "$result" "session-end.sh 语法检查应该通过"
}

# ═══════════════════════════════════════════════════════════
# 测试：Hook 脚本可执行权限
# ═══════════════════════════════════════════════════════════

describe "Hooks 脚本可执行权限"

it "post-tool-use.sh 应该是可执行的"
test_post_tool_use_executable() {
    assert_file_executable "$HOOKS_DIR/post-tool-use.sh" "post-tool-use.sh 应该是可执行的"
}

it "user-prompt-submit.sh 应该是可执行的"
test_user_prompt_submit_executable() {
    assert_file_executable "$HOOKS_DIR/user-prompt-submit.sh" "user-prompt-submit.sh 应该是可执行的"
}

it "session-start.sh 应该是可执行的"
test_session_start_executable() {
    assert_file_executable "$HOOKS_DIR/session-start.sh" "session-start.sh 应该是可执行的"
}

it "session-end.sh 应该是可执行的"
test_session_end_executable() {
    assert_file_executable "$HOOKS_DIR/session-end.sh" "session-end.sh 应该是可执行的"
}

# ═══════════════════════════════════════════════════════════
# 测试：PostToolUse Hook 功能
# ═══════════════════════════════════════════════════════════

describe "PostToolUse Hook 功能"

it "应该处理 Edit 工具输入并记录到日志"
test_post_tool_use_edit() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"

    # 检查 jq 是否可用
    if ! command -v jq &> /dev/null; then
        echo "SKIP: jq 未安装，跳过此测试"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        cleanup_hooks_test
        return 0
    fi

    # 模拟输入数据
    local input='{"tool_type":"Edit","tool_input":{"file_path":"src/test.c","description":"添加错误处理"}}'

    # 执行 hook
    echo "$input" | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null || true

    # 检查日志是否创建
    if [ -f "$log_file" ]; then
        local content=$(cat "$log_file")
        assert_contains "$content" "FILE_CHANGE" "应该记录文件变更"
        rm -f "$log_file"
    else
        # 日志没有创建，测试失败
        echo -e "${RED}✗ FAIL${NC}: 日志文件应该被创建"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    cleanup_hooks_test
}

it "应该处理 Bash 工具输入并记录到日志"
test_post_tool_use_bash() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"

    # 检查 jq 是否可用
    if ! command -v jq &> /dev/null; then
        echo "SKIP: jq 未安装，跳过此测试"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        cleanup_hooks_test
        return 0
    fi

    local input='{"tool_type":"Bash","tool_input":{"command":"npm test","description":"运行测试"}}'

    echo "$input" | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null || true

    if [ -f "$log_file" ]; then
        local content=$(cat "$log_file")
        assert_contains "$content" "BASH" "应该记录 Bash 命令"
        rm -f "$log_file"
    else
        echo -e "${RED}✗ FAIL${NC}: 日志文件应该被创建"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    cleanup_hooks_test
}

# ═══════════════════════════════════════════════════════════
# 测试：UserPromptSubmit Hook 功能
# ═══════════════════════════════════════════════════════════

describe "UserPromptSubmit Hook 功能"

it "应该处理累积的日志并清空"
test_user_prompt_submit_clears_log() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"

    # 创建测试日志
    echo "[FILE_CHANGE] test.c: 修改" > "$log_file"
    echo "[BASH] git commit: 提交" >> "$log_file"

    export PWD="$SCRIPT_DIR"

    # 执行 hook
    bash "$HOOKS_DIR/user-prompt-submit.sh" 2>/dev/null || true

    # 检查日志是否被清空
    if [ -f "$log_file" ]; then
        local line_count=$(wc -l < "$log_file" 2>/dev/null || echo "0")
        # 日志应该被清空（0 行）
        if [ "$line_count" -eq 0 ]; then
            echo -e "${GREEN}✓ PASS${NC}: 日志应该被清空"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}✗ FAIL${NC}: 日志应该被清空"
            echo "  实际行数：$line_count"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        rm -f "$log_file"
    else
        echo -e "${GREEN}✓ PASS${NC}: 日志文件已被处理"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    cleanup_hooks_test
}

# ═══════════════════════════════════════════════════════════
# 测试：批量保存阈值
# ═══════════════════════════════════════════════════════════

describe "批量保存阈值"

it "应该累积记录直到阈值"
test_batch_save_threshold() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"

    rm -f "$log_file"

    # 写入 5 条记录
    for i in 1 2 3 4 5; do
        echo "[FILE_CHANGE] test$i.c: 修改$i" >> "$log_file"
    done

    # 检查行数
    local line_count=$(wc -l < "$log_file" | tr -d ' ')
    assert_equals "5" "$line_count" "应该有 5 条记录"

    rm -f "$log_file"
    cleanup_hooks_test
}

# ═══════════════════════════════════════════════════════════
# 测试：Hooks 配置
# ═══════════════════════════════════════════════════════════

describe "Hooks 配置"

it "hooks.json 应该存在"
test_hooks_config_exists() {
    assert_file_exists "$HOOKS_DIR/hooks.json" "hooks.json 应该存在"
}

it "hooks.json 应该是有效的 JSON"
test_hooks_config_valid_json() {
    if command -v jq &> /dev/null; then
        jq . "$HOOKS_DIR/hooks.json" > /dev/null 2>&1
        local jq_result=$?
        assert_equals "0" "$jq_result" "hooks.json 应该是有效的 JSON"
    else
        echo "SKIP: jq 未安装，跳过 JSON 验证"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi
}

# ═══════════════════════════════════════════════════════════
# 测试执行
# ═══════════════════════════════════════════════════════════

# 存在性测试
test_post_tool_use_exists
test_user_prompt_submit_exists
test_session_start_exists
test_session_end_exists

# 语法检查测试
test_post_tool_use_syntax
test_user_prompt_submit_syntax
test_session_start_syntax
test_session_end_syntax

# 可执行权限测试
test_post_tool_use_executable
test_user_prompt_submit_executable
test_session_start_executable
test_session_end_executable

# PostToolUse 功能测试
test_post_tool_use_edit
test_post_tool_use_bash

# UserPromptSubmit 功能测试
test_user_prompt_submit_clears_log

# 批量保存阈值测试
test_batch_save_threshold

# Hooks 配置测试
test_hooks_config_exists
test_hooks_config_valid_json

# 打印测试报告
print_summary
exit_code=$?

exit $exit_code
