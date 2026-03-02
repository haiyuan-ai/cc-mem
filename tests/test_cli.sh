#!/bin/bash
# CC-Mem CLI 命令测试
# 测试 bin/ccmem-cli.sh 的所有命令

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$SCRIPT_DIR/bin/ccmem-cli.sh"

# 加载测试框架
source "$SCRIPT_DIR/tests/test_framework.sh"

# ═══════════════════════════════════════════════════════════
# 测试：help 命令
# ═══════════════════════════════════════════════════════════

describe "help 命令"

it "应该显示帮助信息"
test_help_shows_usage() {
    local result=$("$CLI" help 2>&1)
    assert_contains "$result" "用法" "帮助信息应该包含用法说明"
    assert_contains "$result" "命令" "帮助信息应该包含命令列表"
}

it "应该列出所有命令"
test_help_lists_commands() {
    local result=$("$CLI" help 2>&1)
    assert_contains "$result" "init" "应该列出 init 命令"
    assert_contains "$result" "capture" "应该列出 capture 命令"
    assert_contains "$result" "search" "应该列出 search 命令"
    assert_contains "$result" "history" "应该列出 history 命令"
    assert_contains "$result" "export" "应该列出 export 命令"
}

# ═══════════════════════════════════════════════════════════
# 测试：status 命令
# ═══════════════════════════════════════════════════════════

describe "status 命令"

it "应该显示数据库状态"
test_status_shows_db_info() {
    local result=$("$CLI" status 2>&1)
    assert_contains "$result" "CC-Mem 状态" "应该显示状态标题"
    assert_contains "$result" "数据库" "应该显示数据库信息"
}

it "应该显示记忆数量"
test_status_shows_memory_count() {
    local result=$("$CLI" status 2>&1)
    assert_contains "$result" "记忆数量" "应该显示记忆数量"
}

it "应该显示会话数量"
test_status_shows_session_count() {
    local result=$("$CLI" status 2>&1)
    assert_contains "$result" "会话数量" "应该显示会话数量"
}

# ═══════════════════════════════════════════════════════════
# 测试：capture 命令
# ═══════════════════════════════════════════════════════════

describe "capture 命令"

it "应该捕获记忆"
test_capture_memory() {
    local result=$(echo "测试捕获内容" | "$CLI" capture -c "context" -t "test" 2>&1)
    assert_contains "$result" "记忆已存储" "应该成功存储记忆"
    assert_contains "$result" "记忆 ID" "应该返回记忆 ID"
}

it "应该自动识别概念标签"
test_capture_auto_detect_concepts() {
    local result=$(echo "这个问题很难解决，但是有办法修复" | "$CLI" capture -c "context" 2>&1)
    assert_contains "$result" "自动识别概念" "应该自动识别概念"
}

it "应该检测重复内容"
test_capture_detects_duplicate() {
    local unique_content="唯一内容_$(date +%s)"

    # 第一次捕获
    "$CLI" capture -c "context" -t "test" <<< "$unique_content" > /dev/null 2>&1

    # 第二次捕获相同内容
    local result=$("$CLI" capture -c "context" -t "test" <<< "$unique_content" 2>&1)
    assert_contains "$result" "跳过" "应该跳过重复内容"
    assert_contains "$result" "内容已存在" "应该提示内容已存在"
}

it "应该过滤私有内容"
test_capture_filters_private() {
    local result=$(echo "公开内容 <private>敏感信息</private> 更多公开内容" | "$CLI" capture -c "context" 2>&1)
    assert_contains "$result" "已过滤" "应该提示已过滤私有内容"
}

# ═══════════════════════════════════════════════════════════
# 测试：search 命令
# ═══════════════════════════════════════════════════════════

describe "search 命令"

it "应该搜索记忆"
test_search_memories() {
    # 先存储一些测试数据
    echo "搜索测试内容 ABC" | "$CLI" capture -c "context" -t "test" > /dev/null 2>&1

    local result=$("$CLI" search -q "ABC" 2>&1)
    assert_contains "$result" "搜索记忆" "应该显示搜索信息"
    assert_contains "$result" "ABC" "应该找到包含 ABC 的记忆"
}

it "应该显示搜索参数"
test_search_shows_params() {
    local result=$("$CLI" search -q "test" -p "/test" -c "context" 2>&1)
    assert_contains "$result" "项目路径" "应该显示项目路径"
    assert_contains "$result" "关键词" "应该显示关键词"
    assert_contains "$result" "类别" "应该显示类别"
}

# ═══════════════════════════════════════════════════════════
# 测试：history 命令
# ═══════════════════════════════════════════════════════════

describe "history 命令"

it "应该显示最近历史"
test_history_shows_recent() {
    # 先创建一条记忆以产生历史记录
    echo "历史测试内容" | "$CLI" capture -c "context" -t "test" > /dev/null 2>&1

    local result=$("$CLI" history -l 5 2>&1)
    assert_contains "$result" "记忆历史" "应该显示历史标题"
}

it "应该显示事件类型"
test_history_shows_event_type() {
    # 先创建一条记忆以产生历史记录
    echo "历史事件测试 XYZ123" | "$CLI" capture -c "context" -t "test" > /dev/null 2>&1

    # 直接查询测试数据库验证（因为 CLI 使用的是全局数据库而非测试数据库）
    local result=$(sqlite3 "$TEST_DB" "SELECT event_type FROM memory_history WHERE new_value LIKE '%历史事件测试%' ORDER BY timestamp DESC LIMIT 1;")
    assert_equals "create" "$result" "应该显示 create 事件"
}

# ═══════════════════════════════════════════════════════════
# 测试：list 命令
# ═══════════════════════════════════════════════════════════

describe "list 命令"

it "应该列出记忆"
test_list_memories() {
    local result=$("$CLI" list -l 5 2>&1)
    assert_contains "$result" "id" "应该显示 ID 列"
    assert_contains "$result" "timestamp" "应该显示时间戳列"
    assert_contains "$result" "category" "应该显示类别列"
}

it "应该限制返回数量"
test_list_limit() {
    local result=$("$CLI" list -l 2 2>&1)
    # 计算行数（减去标题行）
    local line_count=$(echo "$result" | wc -l)
    assert_true "[ $line_count -le 5 ]" "返回行数应该不超过限制 + 标题"
}

# ═══════════════════════════════════════════════════════════
# 测试：export 命令
# ═══════════════════════════════════════════════════════════

describe "export 命令"

it "应该导出记忆到指定目录"
test_export_to_directory() {
    local export_dir="$TEST_DB_DIR/test-exports"
    mkdir -p "$export_dir"

    local result=$("$CLI" export -o "$export_dir" 2>&1)
    assert_contains "$result" "导出记忆到" "应该显示导出目录"
    assert_contains "$result" "导出完成" "应该显示完成信息"
}

it "应该创建 Markdown 文件"
test_export_creates_markdown_files() {
    local export_dir="$TEST_DB_DIR/test-exports-2"
    mkdir -p "$export_dir"

    "$CLI" export -o "$export_dir" > /dev/null 2>&1

    # 检查是否有 .md 文件
    local file_count=$(find "$export_dir" -name "*.md" 2>/dev/null | wc -l)
    assert_true "[ $file_count -gt 0 ]" "应该创建 Markdown 文件"
}

# ═══════════════════════════════════════════════════════════
# 测试：projects 命令
# ═══════════════════════════════════════════════════════════

describe "projects 命令"

it "应该列出项目"
test_projects_lists_projects() {
    local result=$("$CLI" projects 2>&1)
    assert_contains "$result" "项目列表" "应该显示项目列表标题"
}

# ═══════════════════════════════════════════════════════════
# 测试：错误处理
# ═══════════════════════════════════════════════════════════

describe "错误处理"

it "应该处理未知命令"
test_unknown_command() {
    local result=$("$CLI" unknown_command_xyz 2>&1)
    assert_contains "$result" "未知命令" "应该提示未知命令"
}

it "应该处理帮助参数"
test_help_flag() {
    local result=$("$CLI" --help 2>&1)
    assert_contains "$result" "用法" "应该显示帮助信息"
}

# ═══════════════════════════════════════════════════════════
# 运行所有测试
# ═══════════════════════════════════════════════════════════

run_tests "CLI 命令测试"

# help 命令测试
test_help_shows_usage
test_help_lists_commands

# status 命令测试
test_status_shows_db_info
test_status_shows_memory_count
test_status_shows_session_count

# capture 命令测试
test_capture_memory
test_capture_auto_detect_concepts
test_capture_detects_duplicate
test_capture_filters_private

# search 命令测试
test_search_memories
test_search_shows_params

# history 命令测试
test_history_shows_recent
test_history_shows_event_type

# list 命令测试
test_list_memories
test_list_limit

# export 命令测试
test_export_to_directory
test_export_creates_markdown_files

# projects 命令测试
test_projects_lists_projects

# 错误处理测试
test_unknown_command
test_help_flag

# 打印测试报告
print_summary
exit_code=$?

exit $exit_code
