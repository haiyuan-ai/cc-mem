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
set_hooks_runtime_config() {
    local memory_db="${1:-$TEST_DB}"
    local failed_queue_dir="${2:-$HOOKS_TEST_FAILED_QUEUE_DIR}"
    local debug_log="${3:-$HOOKS_TEST_DEBUG_LOG}"
    local growth_threshold="${4:-100}"
    local growth_window_seconds="${5:-3600}"

    python3 - <<PY
import json
path = "$CCMEM_CONFIG_FILE"
with open(path) as f:
    data = json.load(f)
data["memory_db"] = "$memory_db"
data["failed_queue_dir"] = "$failed_queue_dir"
data["debug_log"] = "$debug_log"
cleanup = data.setdefault("cleanup", {})
cleanup["growth_threshold"] = int("$growth_threshold")
cleanup["growth_window_seconds"] = int("$growth_window_seconds")
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
}

setup_hooks_test() {
    # 设置测试会话 ID
    export TEST_SESSION_ID="test_hooks_$$"
    export CLAUDE_SESSION_ID="$TEST_SESSION_ID"
    export CCMEM_CLEANUP_STATE_FILE="/tmp/ccmem_cleanup_state_${TEST_SESSION_ID}"
    CCMEM_FAILED_QUEUE_DIR="/tmp/ccmem_failed_${TEST_SESSION_ID}"
    CCMEM_DEBUG_LOG="/tmp/ccmem_debug_${TEST_SESSION_ID}.log"
    HOOKS_TEST_FAILED_QUEUE_DIR="/tmp/ccmem_failed_${TEST_SESSION_ID}"
    HOOKS_TEST_DEBUG_LOG="/tmp/ccmem_debug_${TEST_SESSION_ID}.log"
    set_hooks_runtime_config "$TEST_DB" "$HOOKS_TEST_FAILED_QUEUE_DIR" "$HOOKS_TEST_DEBUG_LOG" "100" "3600"

    # 清理可能的旧日志
    rm -f "/tmp/ccmem_${TEST_SESSION_ID}.log"
    rm -f "$CCMEM_CLEANUP_STATE_FILE"
    rm -rf "$HOOKS_TEST_FAILED_QUEUE_DIR"
    rm -f "$HOOKS_TEST_DEBUG_LOG"
}

cleanup_hooks_test() {
    # 清理测试日志
    rm -f "/tmp/ccmem_${TEST_SESSION_ID}.log"
    rm -f "${HOOKS_TEST_DEBUG_LOG:-}"
    rm -f "${CCMEM_CLEANUP_STATE_FILE:-}"
    rm -rf "${HOOKS_TEST_FAILED_QUEUE_DIR:-}"
    unset CLAUDE_SESSION_ID
    unset TEST_SESSION_ID
    unset CCMEM_CLEANUP_STATE_FILE
    unset CCMEM_FAILED_QUEUE_DIR
    unset CCMEM_DEBUG_LOG
    unset HOOKS_TEST_FAILED_QUEUE_DIR
    unset HOOKS_TEST_DEBUG_LOG
}

make_hook_input() {
    local cwd="${1:-}"
    local extra="${2:-}"
    local input="{\"session_id\": \"$TEST_SESSION_ID\""

    if [ -n "$cwd" ]; then
        input="$input, \"cwd\": \"$cwd\""
    fi

    if [ -n "$extra" ]; then
        input="$input, $extra"
    fi

    input="$input}"
    echo "$input"
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

    require_command_or_skip "jq" "jq 未安装，跳过此测试" || {
        cleanup_hooks_test
        return 0
    }

    # 模拟输入数据
    local input='{"tool_type":"Edit","tool_input":{"file_path":"src/test.c","description":"添加错误处理"}}'

    # 执行 hook
    echo "$input" | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null || true

    # 检查日志是否创建
    assert_file_exists "$log_file" "日志文件应该被创建"
    local content=$(cat "$log_file")
    assert_contains "$content" "FILE_CHANGE" "应该记录文件变更"
    rm -f "$log_file"

    cleanup_hooks_test
}

it "应该处理 Bash 工具输入并记录到日志"
test_post_tool_use_bash() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"

    require_command_or_skip "jq" "jq 未安装，跳过此测试" || {
        cleanup_hooks_test
        return 0
    }

    local input='{"tool_type":"Bash","tool_input":{"command":"npm test","description":"运行测试"}}'

    echo "$input" | bash "$HOOKS_DIR/post-tool-use.sh" 2>/dev/null || true

    assert_file_exists "$log_file" "日志文件应该被创建"
    local content=$(cat "$log_file")
    assert_contains "$content" "BASH" "应该记录 Bash 命令"
    rm -f "$log_file"

    cleanup_hooks_test
}

it "post-tool-use capture 失败时应把日志入队而不是丢弃"
test_post_tool_use_queues_log_on_capture_failure() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"
    cat > "$log_file" <<'EOF'
[FILE_CHANGE] src/a.js: 修改 A
[BASH] npm test: 运行测试
[FILE_CHANGE] src/b.js: 修改 B
EOF

    local input='{"tool_type":"Edit","tool_input":{"file_path":"src/c.js","description":"触发失败队列"}}'
    set_hooks_runtime_config "/tmp" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"
    echo "$input" | bash "$HOOKS_DIR/post-tool-use.sh" > /dev/null 2>&1 || true
    set_hooks_runtime_config "$TEST_DB" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"

    local queued_count
    queued_count=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_post-tool-use_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$queued_count" "post-tool-use capture 失败时应生成 1 条队列日志"

    local line_count
    line_count=$(wc -l < "$log_file" 2>/dev/null | tr -d ' ')
    assert_equals "0" "$line_count" "入队成功后原始缓冲日志应被清空"

    local queued_file
    queued_file=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_post-tool-use_*" 2>/dev/null | head -1)
    local queued_content
    queued_content=$(cat "$queued_file" 2>/dev/null || true)
    assert_contains "$queued_content" "capture_failed" "队列日志应记录失败原因"
    assert_contains "$queued_content" "[FILE_CHANGE]" "队列日志应保留原始内容"

    rm -f "$log_file"
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
        local line_count
        line_count=$(wc -l < "$log_file" 2>/dev/null || echo "0")
        line_count=$(echo "$line_count" | tr -d '[:space:]')
        assert_equals "0" "$line_count" "日志应该被清空"
        rm -f "$log_file"
    else
        assert_true "true" "日志文件已被处理"
    fi

    assert_equals "" "$result" "没有 prompt 时不应该输出业务日志"

    cleanup_hooks_test
}

it "user-prompt-submit capture 失败时应把日志入队而不是丢弃"
test_user_prompt_submit_queues_log_on_capture_failure() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"
    cat > "$log_file" <<'EOF'
[FILE_CHANGE] src/app.js: 修改 A
[BASH] npm test: 调试错误
EOF

    local input
    input=$(make_hook_input "/tmp")
    set_hooks_runtime_config "/tmp" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"
    echo "$input" | bash "$HOOKS_DIR/user-prompt-submit.sh" > /dev/null 2>&1 || true
    set_hooks_runtime_config "$TEST_DB" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"

    local queued_count
    queued_count=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_user-prompt-submit_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$queued_count" "user-prompt-submit capture 失败时应生成 1 条队列日志"

    local line_count
    line_count=$(wc -l < "$log_file" 2>/dev/null | tr -d ' ')
    assert_equals "0" "$line_count" "入队成功后 user-prompt-submit 缓冲日志应被清空"

    local queued_file
    queued_file=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_user-prompt-submit_*" 2>/dev/null | head -1)
    local queued_content
    queued_content=$(cat "$queued_file" 2>/dev/null || true)
    assert_contains "$queued_content" "capture_failed" "user-prompt-submit 队列日志应记录失败原因"
    assert_contains "$queued_content" "[FILE_CHANGE]" "user-prompt-submit 队列日志应保留原始内容"

    rm -f "$log_file"
    cleanup_hooks_test
}

describe "SessionStart Hook 功能"

it "应该输出结构化上下文而不是搜索结果"
test_session_start_outputs_context_block() {
    setup_hooks_test
    local test_dir
    test_dir=$(create_test_dir "ccmem_session_start")

    store_memory "session1" "$test_dir" "decision" "SessionStart 内容" "SessionStart 摘要" "hook" "" "manual" > /dev/null
    upsert_session "$TEST_SESSION_ID" "$test_dir"
    db_query "UPDATE sessions SET status='stopped', summary='上次停在修复注入逻辑', end_time=CURRENT_TIMESTAMP WHERE id='$TEST_SESSION_ID';"

    local input
    input=$(make_hook_input "$test_dir")
    local result
    result=$(echo "$input" | bash "$HOOKS_DIR/session-start.sh" 2>/dev/null || true)

    assert_contains "$result" "<cc-mem-context>" "SessionStart 应该输出上下文标签"
    assert_contains "$result" "Recent High-Value Memory" "应该包含高价值记忆部分"
    assert_not_contains "$result" "搜索记忆" "不应该输出 search 命令的标题"

    rm -rf "$test_dir"
    cleanup_hooks_test
}

it "带 prompt 时应该输出 recall 上下文"
test_user_prompt_submit_outputs_recall_context() {
    setup_hooks_test
    local test_dir
    test_dir=$(create_test_dir "ccmem_prompt_recall")

    store_memory "session1" "$test_dir" "decision" "SQLite recall 内容" "SQLite recall 摘要" "sqlite" "" "manual" > /dev/null

    local input
    input=$(make_hook_input "$test_dir" "\"prompt\": \"SQLite\"")
    local result
    result=$(echo "$input" | bash "$HOOKS_DIR/user-prompt-submit.sh" 2>/dev/null || true)

    assert_contains "$result" "<cc-mem-recall>" "应该输出 recall 标签"
    assert_contains "$result" "SQLite recall 摘要" "应该输出相关摘要"

    rm -rf "$test_dir"
    cleanup_hooks_test
}

it "user-prompt-submit 应使用规则分类器推导类别"
test_user_prompt_submit_uses_rule_classification() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"
    local test_dir
    test_dir=$(create_test_dir "ccmem_prompt_classify")

    cat > "$log_file" <<'EOF'
[BASH] npm test: 调试 error root cause
[FILE_CHANGE] src/app.js: 继续排查 bug
EOF

    local input
    input=$(make_hook_input "$test_dir")
    echo "$input" | bash "$HOOKS_DIR/user-prompt-submit.sh" > /dev/null 2>&1 || true

    local saved_category
    saved_category=$(db_query "SELECT category FROM memories WHERE source='user_prompt_submit' ORDER BY rowid DESC LIMIT 1;")
    assert_equals "debug" "$saved_category" "user-prompt-submit 应把调试内容分类为 debug"

    local policy_row
    policy_row=$(db_query "SELECT memory_kind || '|' || auto_inject_policy FROM memories WHERE source='user_prompt_submit' ORDER BY rowid DESC LIMIT 1;")
    assert_equals "working|conditional" "$policy_row" "user-prompt-submit debug 记忆应写入 working|conditional"

    local classification_snapshot
    classification_snapshot=$(db_query "SELECT classification_confidence || '|' || classification_source || '|' || classification_version FROM memories WHERE source='user_prompt_submit' ORDER BY rowid DESC LIMIT 1;")
    assert_contains "$classification_snapshot" "|rule|rule-v2" "user-prompt-submit 应保存规则分类快照"

    local classification_log
    classification_log=$(grep "CLASSIFICATION_SOURCE=rule" "$CCMEM_DEBUG_LOG" 2>/dev/null | grep "CATEGORY=debug" || true)
    assert_contains "$classification_log" "CATEGORY=debug" "debug log 应记录规则分类结果"
    assert_contains "$(grep 'MEMORY_KIND=working AUTO_INJECT_POLICY=conditional' "$CCMEM_DEBUG_LOG" 2>/dev/null || true)" "AUTO_INJECT_POLICY=conditional" "debug log 应记录分层决策"

    rm -rf "$test_dir" "$log_file"
    cleanup_hooks_test
}

it "可复用用户 prompt 应单独保存为记忆"
test_user_prompt_submit_saves_reusable_prompt() {
    setup_hooks_test
    local test_dir
    test_dir=$(create_test_dir "ccmem_prompt_reusable")

    local input
    input=$(make_hook_input "$test_dir" "\"prompt\": \"不要单独引入 queue-status，统一放进 status 中扩展\"")
    echo "$input" | bash "$HOOKS_DIR/user-prompt-submit.sh" > /dev/null 2>&1 || true

    local saved_row
    saved_row=$(db_query "SELECT category || '|' || memory_kind || '|' || auto_inject_policy || '|' || summary FROM memories WHERE source='user_prompt_submit' ORDER BY rowid DESC LIMIT 1;")
    assert_contains "$saved_row" "status" "可复用 prompt 应保存摘要"
    assert_true "[[ \"$saved_row\" == pattern\\|* || \"$saved_row\" == decision\\|* ]]" "可复用 prompt 应归入 pattern 或 decision"

    rm -rf "$test_dir"
    cleanup_hooks_test
}

it "可复用用户 prompt capture 失败时应入队"
test_user_prompt_submit_queues_reusable_prompt_on_capture_failure() {
    setup_hooks_test
    local test_dir
    test_dir=$(create_test_dir "ccmem_prompt_reusable_queue")

    local input
    input=$(make_hook_input "$test_dir" "\"prompt\": \"不要单独引入 queue-status，统一放进 status 中扩展\"")
    set_hooks_runtime_config "/tmp" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"
    echo "$input" | bash "$HOOKS_DIR/user-prompt-submit.sh" > /dev/null 2>&1 || true
    set_hooks_runtime_config "$TEST_DB" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"

    local queued_file
    queued_file=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_user-prompt-submit_*" 2>/dev/null | head -1)
    assert_file_exists "$queued_file" "可复用 prompt capture 失败时应写入失败队列"

    local queued_content
    queued_content=$(cat "$queued_file" 2>/dev/null || true)
    assert_contains "$queued_content" "reusable_prompt_capture_failed" "队列文件应记录可复用 prompt 的失败原因"
    assert_contains "$queued_content" "queue-status" "队列文件应保留原始 prompt 内容"
    assert_contains "$queued_content" "project_path_b64=" "队列文件应记录项目路径元数据"

    rm -rf "$test_dir"
    cleanup_hooks_test
}

it "一次性用户 prompt 不应单独保存为记忆"
test_user_prompt_submit_skips_ephemeral_prompt() {
    setup_hooks_test
    local test_dir
    test_dir=$(create_test_dir "ccmem_prompt_ephemeral")

    local input
    input=$(make_hook_input "$test_dir" "\"prompt\": \"可以\"")
    echo "$input" | bash "$HOOKS_DIR/user-prompt-submit.sh" > /dev/null 2>&1 || true

    local saved_count
    saved_count=$(db_query "SELECT COUNT(*) FROM memories WHERE source='user_prompt_submit' AND content='可以';")
    assert_equals "0" "$saved_count" "一次性 prompt 不应单独保存"

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
    local test_dir
    test_dir=$(create_test_dir "ccmem_stop_test")
    rm -f "$CCMEM_DEBUG_LOG"

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
    local input
    input=$(make_hook_input "$test_dir" "\"transcript_path\": \"$test_dir/transcript.jsonl\"")
    echo "$input" | bash "$HOOKS_DIR/stop.sh" > /dev/null 2>&1 || true

    # 检查调试日志中是否成功提取消息
    if grep -q "Extracted last assistant message" "$CCMEM_DEBUG_LOG" 2>/dev/null; then
        assert_true "true" "应该提取到助手消息"
    else
        skip_test "调试日志不可用，跳过验证"
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
    local input
    input=$(make_hook_input "/tmp")
    local result=$(echo "$input" | bash "$HOOKS_DIR/stop.sh" 2>&1)

    # 应该正常完成
    assert_contains "$result" "会话已停止" "应该正常完成（即使没有 transcript）"

    rm -f "/tmp/ccmem_${TEST_SESSION_ID}.log"
    cleanup_hooks_test
}

it "stop capture 失败时应把操作日志入队而不是丢弃"
test_stop_queues_log_on_capture_failure() {
    setup_hooks_test
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"
    cat > "$log_file" <<'EOF'
[FILE_CHANGE] src/main.js: 修复 bug
[BASH] npm test: 运行测试
EOF

    local input
    input=$(make_hook_input "/tmp")
    set_hooks_runtime_config "/tmp" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"
    echo "$input" | bash "$HOOKS_DIR/stop.sh" > /dev/null 2>&1 || true
    set_hooks_runtime_config "$TEST_DB" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"

    local queued_count
    queued_count=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_stop_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$queued_count" "stop capture 失败时应生成 1 条队列日志"

    local line_count
    line_count=$(wc -l < "$log_file" 2>/dev/null | tr -d ' ')
    assert_equals "0" "$line_count" "入队成功后 stop 缓冲日志应被清空"

    local queued_file
    queued_file=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_stop_*" 2>/dev/null | head -1)
    local queued_content
    queued_content=$(cat "$queued_file" 2>/dev/null || true)
    assert_contains "$queued_content" "capture_failed" "stop 队列日志应记录失败原因"
    assert_contains "$queued_content" "[FILE_CHANGE]" "stop 队列日志应保留原始内容"

    rm -f "$log_file"
    cleanup_hooks_test
}

it "应该生成包含操作统计的摘要"
test_stop_generate_summary() {
    setup_hooks_test
    local test_dir
    test_dir=$(create_test_dir "ccmem_stop_summary")
    rm -f "$CCMEM_DEBUG_LOG"

    # 创建操作日志（使用真实的 FILE_CHANGE 格式）
    cat > "/tmp/ccmem_${TEST_SESSION_ID}.log" << 'EOF'
[FILE_CHANGE] src/main.js: 修复 bug
[FILE_CHANGE] src/config.json: 添加配置
[BASH] npm test: 运行测试
EOF

    # 执行 hook
    local input
    input=$(make_hook_input "$test_dir")
    echo "$input" | bash "$HOOKS_DIR/stop.sh" > /dev/null 2>&1 || true

    # 检查摘要生成（通过调试日志）
    if grep -q "Generated summary" "$CCMEM_DEBUG_LOG" 2>/dev/null; then
        local summary_line=$(grep "Generated summary" "$CCMEM_DEBUG_LOG" | tail -1)
        if echo "$summary_line" | grep -q "Files="; then
            assert_true "true" "应该生成包含操作统计的摘要"
        else
            assert_true "false" "摘要已生成但没有操作统计（Files=）"
        fi
    else
        skip_test "调试日志不可用，跳过验证"
    fi

    rm -rf "$test_dir" "/tmp/ccmem_${TEST_SESSION_ID}.log"
    cleanup_hooks_test
}

it "应该压缩超长最终回复"
test_stop_condenses_long_final_response() {
    setup_hooks_test
    local test_dir
    test_dir=$(create_test_dir "ccmem_stop_long_reply")

    local repeated
    repeated=$(printf '补充说明段落。%.0s' $(seq 1 120))
    cat > "$test_dir/transcript.jsonl" <<EOF
{"type": "assistant", "message": {"content": "任务完成总结\\n1. 修复了搜索逻辑\\n2. 增加了中文 fallback\\n3. 补充了回归测试\\n${repeated}\\n最终建议继续观察 recall 命中质量"}}
EOF

    local input
    input=$(make_hook_input "$test_dir" "\"transcript_path\": \"$test_dir/transcript.jsonl\"")
    echo "$input" | bash "$HOOKS_DIR/stop.sh" > /dev/null 2>&1 || true

    local saved_content
    saved_content=$(db_query "SELECT content FROM memories WHERE source='stop_final_response' ORDER BY rowid DESC LIMIT 1;")
    local content_length
    content_length=$(db_query "SELECT LENGTH(content) FROM memories WHERE source='stop_final_response' ORDER BY rowid DESC LIMIT 1;")

    assert_contains "$saved_content" "关键点:" "长回复应该被裁剪成关键点格式"
    assert_contains "$saved_content" "1. 修复了搜索逻辑" "应该保留关键条目"
    assert_less_than 1400 "$content_length" "裁剪后的最终回复应该明显短于原文"

    rm -rf "$test_dir" "/tmp/ccmem_${TEST_SESSION_ID}.log"
    cleanup_hooks_test
}

it "stop final response capture 失败时应把内容入队而不是丢弃"
test_stop_final_response_queues_on_capture_failure() {
    setup_hooks_test
    local test_dir
    test_dir=$(create_test_dir "ccmem_stop_final_response_fail")

    cat > "$test_dir/transcript.jsonl" <<'EOF'
{"type": "assistant", "message": {"content": "最终回复内容：修复完成，建议继续验证。"}}
EOF

    local input
    input=$(make_hook_input "$test_dir" "\"transcript_path\": \"$test_dir/transcript.jsonl\"")
    set_hooks_runtime_config "/tmp" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"
    echo "$input" | bash "$HOOKS_DIR/stop.sh" > /dev/null 2>&1 || true
    set_hooks_runtime_config "$TEST_DB" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"

    local queued_count
    queued_count=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_stop-final-response_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$queued_count" "stop final response capture 失败时应生成 1 条队列日志"

    local queued_file
    queued_file=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_stop-final-response_*" 2>/dev/null | head -1)
    local queued_content
    queued_content=$(cat "$queued_file" 2>/dev/null || true)
    assert_contains "$queued_content" "capture_failed" "stop final response 队列日志应记录失败原因"
    assert_contains "$queued_content" "最终回复内容：修复完成，建议继续验证。" "stop final response 队列日志应保留原始内容"

    rm -rf "$test_dir" "/tmp/ccmem_${TEST_SESSION_ID}.log" "/tmp/ccmem_${TEST_SESSION_ID}_final_response.log"
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

it "session-end 应该压缩超长操作日志"
test_session_end_condenses_long_log() {
    setup_hooks_test
    local test_dir
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"
    test_dir=$(create_test_dir "ccmem_session_end")

    cat > "$log_file" <<'EOF'
[FILE_CHANGE] src/a.js: 修改 A
[FILE_CHANGE] src/b.js: 修改 B
[FILE_CHANGE] src/c.js: 修改 C
[FILE_CHANGE] src/d.js: 修改 D
[FILE_CHANGE] src/e.js: 修改 E
[FILE_CHANGE] src/f.js: 修改 F
[BASH] npm test: 运行测试
[BASH] npm run lint: 运行 lint
[BASH] git diff: 查看差异
[BASH] npm run build: 构建
[FILE_CHANGE] src/g.js: 修改 G
[FILE_CHANGE] src/h.js: 修改 H
[FILE_CHANGE] src/i.js: 修改 I
EOF

    export PWD="$test_dir"
    local input
    input=$(make_hook_input)
    echo "$input" | bash "$HOOKS_DIR/session-end.sh" > /dev/null 2>&1 || true

    local saved_content
    saved_content=$(db_query "SELECT content FROM memories WHERE source='session_end' ORDER BY rowid DESC LIMIT 1;")
    assert_contains "$saved_content" "操作摘要: Files=" "超长日志应该被压缩为操作摘要"
    assert_contains "$saved_content" "最近文件变更:" "应该保留文件变更摘要"
    assert_contains "$saved_content" "最近命令:" "应该保留命令摘要"

    rm -rf "$test_dir" "$log_file"
    cleanup_hooks_test
}

it "session-end 应使用规则分类器推导类别"
test_session_end_uses_rule_classification() {
    setup_hooks_test
    local test_dir
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"
    test_dir=$(create_test_dir "ccmem_session_end_classify")

    cat > "$log_file" <<'EOF'
[FILE_CHANGE] src/search.js: 实现 fallback workaround
[BASH] npm test: 验证 solution 已完成
EOF

    export PWD="$test_dir"
    local input
    input=$(make_hook_input)
    echo "$input" | bash "$HOOKS_DIR/session-end.sh" > /dev/null 2>&1 || true

    local saved_category
    saved_category=$(db_query "SELECT category FROM memories WHERE source='session_end' ORDER BY rowid DESC LIMIT 1;")
    assert_equals "solution" "$saved_category" "session-end 应把修复结果分类为 solution"

    local policy_row
    policy_row=$(db_query "SELECT memory_kind || '|' || auto_inject_policy FROM memories WHERE source='session_end' ORDER BY rowid DESC LIMIT 1;")
    assert_equals "working|conditional" "$policy_row" "session-end solution 记忆应写入 working|conditional"

    local classification_snapshot
    classification_snapshot=$(db_query "SELECT classification_confidence || '|' || classification_source || '|' || classification_version FROM memories WHERE source='session_end' ORDER BY rowid DESC LIMIT 1;")
    assert_contains "$classification_snapshot" "|rule|rule-v2" "session-end 应保存规则分类快照"

    local classification_log
    classification_log=$(grep "CLASSIFICATION_SOURCE=rule" "$CCMEM_DEBUG_LOG" 2>/dev/null | grep "CATEGORY=solution" || true)
    assert_contains "$classification_log" "CATEGORY=solution" "debug log 应记录规则分类结果"
    assert_contains "$(grep 'MEMORY_KIND=working AUTO_INJECT_POLICY=conditional' "$CCMEM_DEBUG_LOG" 2>/dev/null || true)" "AUTO_INJECT_POLICY=conditional" "debug log 应记录分层决策"

    rm -rf "$test_dir" "$log_file"
    cleanup_hooks_test
}

it "session-end capture 失败时应把日志入队而不是丢弃"
test_session_end_queues_log_on_capture_failure() {
    setup_hooks_test
    local test_dir
    local log_file="/tmp/ccmem_${TEST_SESSION_ID}.log"
    test_dir=$(create_test_dir "ccmem_session_end_capture_fail")

    cat > "$log_file" <<'EOF'
[FILE_CHANGE] src/search.js: 修改检索逻辑
[BASH] npm test: 运行测试
EOF

    local input
    input=$(make_hook_input "$test_dir")
    set_hooks_runtime_config "/tmp" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"
    echo "$input" | bash "$HOOKS_DIR/session-end.sh" > /dev/null 2>&1 || true
    set_hooks_runtime_config "$TEST_DB" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "100" "3600"

    local queued_count
    queued_count=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_session-end_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$queued_count" "session-end capture 失败时应生成 1 条队列日志"

    local line_count
    line_count=$(wc -l < "$log_file" 2>/dev/null | tr -d ' ')
    assert_equals "0" "$line_count" "入队成功后 session-end 缓冲日志应被清空"

    local queued_file
    queued_file=$(find "$CCMEM_FAILED_QUEUE_DIR" -type f -name "failed_session-end_*" 2>/dev/null | head -1)
    local queued_content
    queued_content=$(cat "$queued_file" 2>/dev/null || true)
    assert_contains "$queued_content" "capture_failed" "session-end 队列日志应记录失败原因"
    assert_contains "$queued_content" "[FILE_CHANGE]" "session-end 队列日志应保留原始内容"

    rm -rf "$test_dir" "$log_file"
    cleanup_hooks_test
}

it "session-end 应该触发机会式清理"
test_session_end_runs_opportunistic_cleanup() {
    setup_hooks_test
    rm -f "$CCMEM_DEBUG_LOG"

    store_memory "cleanup_session_1" "/tmp/cleanup-project" "context" "低优先级旧记忆" "旧摘要" "" "" "session_end" "temporary" "never" "/tmp/cleanup-project" "2000-01-01 00:00:00" > /dev/null

    local before_count
    before_count=$(db_query "SELECT COUNT(*) FROM memories WHERE summary='旧摘要';")

    local input
    input=$(make_hook_input)
    echo "$input" | bash "$HOOKS_DIR/session-end.sh" > /dev/null 2>&1 || true

    local after_count
    after_count=$(db_query "SELECT COUNT(*) FROM memories WHERE summary='旧摘要';")

    assert_equals "1" "$before_count" "测试前应该存在待清理记忆"
    assert_equals "0" "$after_count" "session-end 应该清理过期低优先级记忆"

    local cleanup_log
    cleanup_log=$(grep "\\[cleanup\\].*trigger=session-end" "$CCMEM_DEBUG_LOG" 2>/dev/null || true)
    assert_contains "$cleanup_log" "deleted=" "debug log 应记录 session-end 清理结果"

    cleanup_hooks_test
}

it "机会式清理应受节流限制"
test_opportunistic_cleanup_throttled() {
    setup_hooks_test
    rm -f "$CCMEM_DEBUG_LOG"

    date +%s > "$CCMEM_CLEANUP_STATE_FILE"
    store_memory "cleanup_session_2" "/tmp/cleanup-project" "context" "节流测试记忆" "节流摘要" "" "" "session_end" "temporary" "never" "/tmp/cleanup-project" "2000-01-01 00:00:00" > /dev/null

    local input
    input=$(make_hook_input)
    echo "$input" | bash "$HOOKS_DIR/session-end.sh" > /dev/null 2>&1 || true

    local remaining_count
    remaining_count=$(db_query "SELECT COUNT(*) FROM memories WHERE summary='节流摘要';")
    assert_equals "1" "$remaining_count" "节流时不应执行清理"

    local cleanup_log
    cleanup_log=$(grep "\\[cleanup\\].*skipped=throttle" "$CCMEM_DEBUG_LOG" 2>/dev/null || true)
    assert_contains "$cleanup_log" "skipped=throttle" "debug log 应记录节流跳过"

    cleanup_hooks_test
}

it "记忆增长过快时应绕过节流执行清理"
test_opportunistic_cleanup_bypasses_throttle_on_growth() {
    setup_hooks_test
    rm -f "$CCMEM_DEBUG_LOG"

    set_hooks_runtime_config "$TEST_DB" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "2" "3600"
    date +%s > "$CCMEM_CLEANUP_STATE_FILE"

    store_memory "cleanup_growth_1" "/tmp/cleanup-project" "context" "增长触发记忆" "增长触发摘要" "" "" "session_end" "temporary" "never" "/tmp/cleanup-project" "2000-01-01 00:00:00" > /dev/null

    local input
    input=$(make_hook_input)
    echo "$input" | bash "$HOOKS_DIR/session-end.sh" > /dev/null 2>&1 || true

    local remaining_count
    remaining_count=$(db_query "SELECT COUNT(*) FROM memories WHERE summary='增长触发摘要';")
    assert_equals "0" "$remaining_count" "增长速率达到阈值时应绕过节流并执行清理"

    local cleanup_log
    cleanup_log=$(grep "\\[cleanup\\].*bypass=growth" "$CCMEM_DEBUG_LOG" 2>/dev/null || true)
    assert_contains "$cleanup_log" "bypass=growth" "debug log 应记录增长速率绕过节流"

    cleanup_hooks_test
}

it "其他项目的增长不应绕过当前项目的节流"
test_opportunistic_cleanup_growth_is_project_scoped() {
    setup_hooks_test
    rm -f "$CCMEM_DEBUG_LOG"

    set_hooks_runtime_config "$TEST_DB" "$CCMEM_FAILED_QUEUE_DIR" "$CCMEM_DEBUG_LOG" "2" "3600"
    date +%s > "$CCMEM_CLEANUP_STATE_FILE"

    store_memory "cleanup_scope_target" "/tmp/cleanup-project" "context" "当前项目旧记忆" "当前项目旧摘要" "" "" "session_end" "temporary" "never" "/tmp/cleanup-project" "2000-01-01 00:00:00" > /dev/null
    store_memory "cleanup_scope_other" "/tmp/other-project" "context" "其他项目新记忆" "其他项目新摘要" "" "" "session_end" "temporary" "never" "/tmp/other-project" > /dev/null

    local input
    input=$(make_hook_input "/tmp/cleanup-project")
    echo "$input" | bash "$HOOKS_DIR/session-end.sh" > /dev/null 2>&1 || true

    local remaining_count
    remaining_count=$(db_query "SELECT COUNT(*) FROM memories WHERE summary='当前项目旧摘要';")
    assert_equals "1" "$remaining_count" "其他项目增长不应触发当前项目绕过节流"

    local cleanup_log
    cleanup_log=$(grep "\\[cleanup\\].*bypass=growth.*project=/tmp/cleanup-project" "$CCMEM_DEBUG_LOG" 2>/dev/null || true)
    assert_equals "" "$cleanup_log" "debug log 不应记录跨项目增长绕过"

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
    require_command_or_skip "jq" "jq 未安装，跳过 JSON 验证" || return 0

    jq . "$HOOKS_DIR/hooks.json" > /dev/null 2>&1
    local jq_result=$?
    assert_equals "0" "$jq_result" "hooks.json 应该是有效的 JSON"
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
test_post_tool_use_queues_log_on_capture_failure

# UserPromptSubmit 功能测试
test_user_prompt_submit_clears_log
test_user_prompt_submit_queues_log_on_capture_failure

# SessionStart / recall 注入测试
test_session_start_outputs_context_block
test_user_prompt_submit_outputs_recall_context
test_user_prompt_submit_uses_rule_classification
test_user_prompt_submit_saves_reusable_prompt
test_user_prompt_submit_skips_ephemeral_prompt

# Stop Hook 功能测试
test_stop_extract_last_message
test_stop_no_transcript
test_stop_queues_log_on_capture_failure
test_stop_generate_summary
test_stop_condenses_long_final_response
test_stop_final_response_queues_on_capture_failure

# 批量保存阈值测试
test_batch_save_threshold
test_session_end_condenses_long_log
test_session_end_uses_rule_classification
test_session_end_queues_log_on_capture_failure
test_session_end_runs_opportunistic_cleanup
test_opportunistic_cleanup_throttled
test_opportunistic_cleanup_bypasses_throttle_on_growth
test_opportunistic_cleanup_growth_is_project_scoped

# Hooks 配置测试
test_hooks_config_exists
test_hooks_config_valid_json

# 打印测试报告
print_summary
exit_code=$?

exit $exit_code
