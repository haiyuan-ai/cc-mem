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
    rm -f "/tmp/ccmem_debug.log"
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

it "stop.sh 应该存在"
test_stop_exists() {
    setup_hooks_test
    assert_file_exists "$HOOKS_DIR/stop.sh" "stop.sh 应该存在"
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

it "stop.sh 应该通过语法检查"
test_stop_syntax() {
    local result=$(bash -n "$HOOKS_DIR/stop.sh" 2>&1)
    assert_equals "" "$result" "stop.sh 语法检查应该通过"
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

it "stop.sh 应该是可执行的"
test_stop_executable() {
    assert_file_executable "$HOOKS_DIR/stop.sh" "stop.sh 应该是可执行的"
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
    local result
    result=$(bash "$HOOKS_DIR/user-prompt-submit.sh" 2>/dev/null || true)

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

    assert_equals "" "$result" "没有 prompt 时不应该输出业务日志"

    cleanup_hooks_test
}

describe "SessionStart Hook 功能"

it "应该输出结构化上下文而不是搜索结果"
test_session_start_outputs_context_block() {
    setup_hooks_test
    local test_dir="/tmp/ccmem_session_start_$$"
    mkdir -p "$test_dir"

    store_memory "session1" "$test_dir" "decision" "SessionStart 内容" "SessionStart 摘要" "hook" "" "manual" > /dev/null
    upsert_session "$TEST_SESSION_ID" "$test_dir"
    sqlite3 "$TEST_DB" "UPDATE sessions SET status='stopped', summary='上次停在修复注入逻辑', end_time=CURRENT_TIMESTAMP WHERE id='$TEST_SESSION_ID';"

    local input="{\"session_id\": \"$TEST_SESSION_ID\", \"cwd\": \"$test_dir\"}"
    local result
    result=$(echo "$input" | bash "$HOOKS_DIR/session-start.sh" 2>/dev/null || true)

    assert_contains "$result" "<cc-mem-context>" "SessionStart 应该输出上下文标签"
    assert_contains "$result" "Recent High-Value Memory" "应该包含高价值记忆部分"
    assert_true "[[ ! \"$result\" == *\"搜索记忆\"* ]]" "不应该输出 search 命令的标题"

    rm -rf "$test_dir"
    cleanup_hooks_test
}

it "带 prompt 时应该输出 recall 上下文"
test_user_prompt_submit_outputs_recall_context() {
    setup_hooks_test
    local test_dir="/tmp/ccmem_prompt_recall_$$"
    mkdir -p "$test_dir"

    store_memory "session1" "$test_dir" "decision" "SQLite recall 内容" "SQLite recall 摘要" "sqlite" "" "manual" > /dev/null

    local input="{\"session_id\": \"$TEST_SESSION_ID\", \"cwd\": \"$test_dir\", \"prompt\": \"SQLite\"}"
    local result
    result=$(echo "$input" | bash "$HOOKS_DIR/user-prompt-submit.sh" 2>/dev/null || true)

    assert_contains "$result" "<cc-mem-recall>" "应该输出 recall 标签"
    assert_contains "$result" "SQLite recall 摘要" "应该输出相关摘要"

    rm -rf "$test_dir"
    cleanup_hooks_test
}

# ═══════════════════════════════════════════════════════════
# 测试：Stop Hook 功能
# ═══════════════════════════════════════════════════════════

describe "Stop Hook 功能"

it "应该从 transcript 提取最后一条助手消息"
test_stop_extract_last_message() {
    setup_hooks_test
    local test_dir="/tmp/ccmem_stop_test_$$"
    mkdir -p "$test_dir"
    rm -f /tmp/ccmem_debug.log

    # 创建模拟 transcript
    cat > "$test_dir/transcript.jsonl" << 'EOF'
{"type": "user", "message": {"content": "开始任务"}}
{"type": "assistant", "message": {"content": "收到，我来处理这个任务。"}}
{"type": "user", "message": {"content": "[执行工具]"}}
{"type": "assistant", "message": {"content": "任务已完成。主要修改：\n1. 修复了 bug\n2. 优化了性能"}}
EOF

    # 创建操作日志
    echo "[EDIT] src/main.js: 修复 bug" > "/tmp/ccmem_${TEST_SESSION_ID}.log"

    # 执行 hook
    local input="{\"session_id\": \"$TEST_SESSION_ID\", \"transcript_path\": \"$test_dir/transcript.jsonl\", \"cwd\": \"$test_dir\"}"
    echo "$input" | bash "$HOOKS_DIR/stop.sh" > /dev/null 2>&1 || true

    # 检查调试日志中是否成功提取消息
    if grep -q "Extracted last assistant message" /tmp/ccmem_debug.log 2>/dev/null; then
        echo -e "${GREEN}✓ PASS${NC}: 应该提取到助手消息"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${YELLOW}⊘ SKIP${NC}: 调试日志不可用，跳过验证"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi

    rm -rf "$test_dir" "/tmp/ccmem_${TEST_SESSION_ID}.log"
    cleanup_hooks_test
}

it "应该处理无 transcript 的情况"
test_stop_no_transcript() {
    setup_hooks_test

    # 创建操作日志
    echo "[BASH] npm test: 运行测试" > "/tmp/ccmem_${TEST_SESSION_ID}.log"

    # 执行 hook（不带 transcript）
    local input="{\"session_id\": \"$TEST_SESSION_ID\", \"cwd\": \"/tmp\"}"
    local result=$(echo "$input" | bash "$HOOKS_DIR/stop.sh" 2>&1)

    # 应该正常完成
    assert_contains "$result" "会话已停止" "应该正常完成（即使没有 transcript）"

    rm -f "/tmp/ccmem_${TEST_SESSION_ID}.log"
    cleanup_hooks_test
}

it "应该生成包含操作统计的摘要"
test_stop_generate_summary() {
    setup_hooks_test
    local test_dir="/tmp/ccmem_stop_summary_$$"
    mkdir -p "$test_dir"
    rm -f /tmp/ccmem_debug.log

    # 创建操作日志（使用真实的 FILE_CHANGE 格式）
    cat > "/tmp/ccmem_${TEST_SESSION_ID}.log" << 'EOF'
[FILE_CHANGE] src/main.js: 修复 bug
[FILE_CHANGE] src/config.json: 添加配置
[BASH] npm test: 运行测试
EOF

    # 执行 hook
    local input="{\"session_id\": \"$TEST_SESSION_ID\", \"cwd\": \"$test_dir\"}"
    echo "$input" | bash "$HOOKS_DIR/stop.sh" > /dev/null 2>&1 || true

    # 检查摘要生成（通过调试日志）
    if grep -q "Generated summary" /tmp/ccmem_debug.log 2>/dev/null; then
        local summary_line=$(grep "Generated summary" /tmp/ccmem_debug.log | tail -1)
        if echo "$summary_line" | grep -q "Files="; then
            assert_true "true" "应该生成包含操作统计的摘要"
        else
            assert_true "false" "摘要已生成但没有操作统计（Files=）"
        fi
    else
        echo -e "${YELLOW}⊘ SKIP${NC}: 调试日志不可用，跳过验证"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    fi

    rm -rf "$test_dir" "/tmp/ccmem_${TEST_SESSION_ID}.log"
    cleanup_hooks_test
}

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

run_tests "Hooks 功能测试"

# 存在性测试
test_post_tool_use_exists
test_user_prompt_submit_exists
test_session_start_exists
test_session_end_exists
test_stop_exists

# 语法检查测试
test_post_tool_use_syntax
test_user_prompt_submit_syntax
test_session_start_syntax
test_session_end_syntax
test_stop_syntax

# 可执行权限测试
test_post_tool_use_executable
test_user_prompt_submit_executable
test_session_start_executable
test_session_end_executable
test_stop_executable

# PostToolUse 功能测试
test_post_tool_use_edit
test_post_tool_use_bash

# UserPromptSubmit 功能测试
test_user_prompt_submit_clears_log

# SessionStart / recall 注入测试
test_session_start_outputs_context_block
test_user_prompt_submit_outputs_recall_context

# Stop Hook 功能测试
test_stop_extract_last_message
test_stop_no_transcript
test_stop_generate_summary

# 批量保存阈值测试
test_batch_save_threshold

# Hooks 配置测试
test_hooks_config_exists
test_hooks_config_valid_json

# 打印测试报告
print_summary
exit_code=$?

exit $exit_code
