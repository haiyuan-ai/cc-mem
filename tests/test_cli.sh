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
    assert_contains "$result" "recall" "应该列出 recall 命令"
    assert_contains "$result" "history" "应该列出 history 命令"
    assert_contains "$result" "export" "应该列出 export 命令"
    assert_not_contains "$result" "store" "不应再列出 store 命令"
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

it "应该显示失败队列摘要"
test_status_shows_failed_queue_summary() {
    local queue_dir="/tmp/ccmem_failed_cli_$$"
    local config_file="$CCMEM_CONFIG_FILE"
    rm -rf "$queue_dir"
    mkdir -p "$queue_dir"
    printf "# hook=user-prompt-submit session_id=test reason=capture_failed queued_at=2026-03-08T00:00:00Z\npayload\n" > "$queue_dir/failed_user-prompt-submit_test_abc.log"
    python3 - <<PY
import json
path = "$config_file"
with open(path) as f:
    data = json.load(f)
data["failed_queue_dir"] = "$queue_dir"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\\n")
PY

    local result
    result=$("$CLI" status 2>&1)

    assert_contains "$result" "失败队列" "应该显示失败队列区块"
    assert_contains "$result" "文件数：1" "应该显示失败文件数量"
    assert_contains "$result" "user-prompt-submit=1" "应该显示按 hook 聚合的失败计数"

    rm -rf "$queue_dir"
}

it "应该显示最近 cleanup 摘要"
test_status_shows_recent_cleanup_summary() {
    local debug_log="/tmp/ccmem_debug_cli_$$.log"
    local config_file="$CCMEM_CONFIG_FILE"
    cat > "$debug_log" <<'EOF'
[cleanup] Sun Mar  8 13:00:00 CST 2026: trigger=session-end mode=safe days=30 limit=50 reason=growth
[cleanup] Sun Mar  8 13:00:00 CST 2026: trigger=session-end deleted=3 scope=temporary never/manual_only
EOF
    python3 - <<PY
import json
path = "$config_file"
with open(path) as f:
    data = json.load(f)
data["debug_log"] = "$debug_log"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\\n")
PY

    local result
    result=$("$CLI" status 2>&1)

    assert_contains "$result" "最近 Cleanup" "应该显示 cleanup 摘要区块"
    assert_contains "$result" "mode=safe" "应该显示最近 cleanup 触发信息"
    assert_contains "$result" "deleted=3" "应该显示最近 cleanup 结果"

    rm -f "$debug_log"
}

# ═══════════════════════════════════════════════════════════
# 测试：stats 命令
# ═══════════════════════════════════════════════════════════

describe "stats 命令"

it "应该显示最近记忆统计"
test_stats_shows_summary() {
    store_memory "stats_1" "/tmp/stats-project" "decision" "统计内容 A" "统计摘要 A" "" "" "manual" "durable" "always" "/tmp/stats-project" > /dev/null
    store_memory "stats_2" "/tmp/stats-project" "debug" "统计内容 B" "统计摘要 B" "" "" "post_tool_use" "temporary" "never" "/tmp/stats-project" > /dev/null

    local result
    result=$("$CLI" stats --days 7 2>&1)

    assert_contains "$result" "CC-Mem 统计" "应该显示 stats 标题"
    assert_contains "$result" "总览" "应该显示总览区块"
    assert_contains "$result" "Preview 占比" "应该显示 preview 压缩占比"
    assert_contains "$result" "每日明细" "应该显示每日明细区块"
}

it "status 应支持从 config.json 读取 debug_log 路径"
test_status_reads_debug_log_from_config() {
    local config_file="$CCMEM_CONFIG_FILE"
    local debug_log="/tmp/ccmem_config_debug_$$.log"
    python3 - <<PY
import json
path = "$config_file"
with open(path) as f:
    data = json.load(f)
data["debug_log"] = "$debug_log"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\\n")
PY
    cat > "$debug_log" <<'EOF'
[cleanup] Sun Mar  8 13:00:00 CST 2026: trigger=stop mode=safe days=30 limit=50 reason=schedule
[cleanup] Sun Mar  8 13:00:00 CST 2026: trigger=stop deleted=1 scope=temporary never/manual_only
EOF

    local result
    result=$("$CLI" status 2>&1)

    assert_contains "$result" "deleted=1" "status 应通过配置文件读取 debug_log"

    rm -f "$debug_log"
}

it "stats 命令应该支持按项目过滤"
test_stats_supports_project_filter() {
    store_memory "stats_project_a" "/tmp/stats-filter-a" "decision" "项目 A 内容" "项目 A 摘要" "" "" "manual" "durable" "always" "/tmp/stats-filter-a" > /dev/null
    store_memory "stats_project_b" "/tmp/stats-filter-b" "debug" "项目 B 内容" "项目 B 摘要" "" "" "manual" "working" "conditional" "/tmp/stats-filter-b" > /dev/null

    local result
    result=$("$CLI" stats --days 7 --project "/tmp/stats-filter-a" 2>&1)

    assert_contains "$result" "项目：/tmp/stats-filter-a" "应该显示过滤后的项目根路径"
    assert_contains "$result" "记忆数量：1" "项目过滤后应该只统计该项目"
    assert_contains "$result" "durable=1" "应该统计该项目的 durable 分层数量"
    assert_contains "$result" "working=0" "不应混入其他项目的 working 记忆"
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

it "应该支持自定义摘要"
test_capture_supports_custom_summary() {
    local content="自定义摘要正文_$(date +%s)"
    local custom_summary="这是自定义摘要"
    local result
    result=$(echo "$content" | "$CLI" capture -c "pattern" -m "$custom_summary" 2>&1)
    local memory_id
    memory_id=$(echo "$result" | sed -n 's/.*记忆 ID: \(mem_[A-Za-z0-9_]*\).*/\1/p' | tail -n 1)

    assert_contains "$result" "记忆已存储" "应该成功存储带自定义摘要的记忆"
    assert_contains "$result" "记忆 ID" "应该返回记忆 ID"
    local stored_summary
    stored_summary=$(db_query "SELECT summary FROM memories WHERE id = '$memory_id';")
    assert_equals "$custom_summary" "$stored_summary" "应该保存自定义摘要"
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

it "应该拒绝纯空白内容"
test_capture_rejects_whitespace_only() {
    local before_count
    before_count=$(db_query "SELECT COUNT(*) FROM memories;")
    local result
    result=$(printf "   " | "$CLI" capture -c "context" 2>&1)
    local status=$?
    local after_count
    after_count=$(db_query "SELECT COUNT(*) FROM memories;")

    assert_equals "1" "$status" "纯空白内容应该返回非 0"
    assert_contains "$result" "content cannot be empty" "应该提示空内容错误"
    assert_equals "$before_count" "$after_count" "纯空白内容不应该写入数据库"
}

it "capture 命令遇到无效类别时应该返回错误"
test_capture_rejects_invalid_category() {
    local before_count
    before_count=$(db_query "SELECT COUNT(*) FROM memories;")
    local result
    result=$(echo "capture invalid category" | "$CLI" capture -c "invalid_category" 2>&1)
    local status=$?
    local after_count
    after_count=$(db_query "SELECT COUNT(*) FROM memories;")

    assert_equals "1" "$status" "无效类别应该返回非 0"
    assert_contains "$result" "存储记忆失败" "应该提示存储失败"
    assert_equals "$before_count" "$after_count" "无效类别不应该写入数据库"
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
    assert_contains "$result" "中文回退：未使用" "英文搜索不应该使用中文回退"
    assert_contains "$result" "ABC" "应该找到包含 ABC 的记忆"
}

it "应该显示搜索参数"
test_search_shows_params() {
    local result=$("$CLI" search -q "test" -p "/test" -c "context" 2>&1)
    assert_contains "$result" "项目路径" "应该显示项目路径"
    assert_contains "$result" "关键词" "应该显示关键词"
    assert_contains "$result" "类别" "应该显示类别"
}

it "应该支持中文搜索 fallback"
test_search_memories_cjk_fallback() {
    echo "这是一个中文归档示例" | "$CLI" capture -c "context" -t "中文归档" > /dev/null 2>&1

    local result=$("$CLI" search -q "归档" 2>&1)
    assert_contains "$result" "搜索记忆" "中文搜索应该显示搜索信息"
    assert_contains "$result" "中文回退：已使用" "中文搜索应该标记已使用回退"
    assert_contains "$result" "中文归档" "中文搜索应该返回相关结果"
}

# ═══════════════════════════════════════════════════════════
# 测试：recall 命令
# ═══════════════════════════════════════════════════════════

describe "recall 命令"

it "应该生成 query-aware recall 注入块"
test_recall_generates_recall_block() {
    local project="/tmp/recall-cli"
    echo "Recall CLI 关键决策" | "$CLI" capture -p "$project" -c "decision" -m "Recall CLI 关键决策" > /dev/null 2>&1

    local result=$("$CLI" recall -p "$project" -q "关键决策" -l 2 2>&1)
    assert_contains "$result" "<cc-mem-recall>" "应该输出 recall block"
    assert_contains "$result" "Relevant project context" "应该包含 recall 标题"
    assert_contains "$result" "Recall CLI 关键决策" "应该包含命中的摘要"
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
    local capture_result
    capture_result=$(echo "历史事件测试 XYZ123" | "$CLI" capture -c "context" -t "test" 2>&1)
    local memory_id=$(echo "$capture_result" | sed -n 's/.*记忆 ID: \(mem_[a-z0-9_]*\).*/\1/p' | tail -1)

    local result=$("$CLI" history -m "$memory_id" -l 5 2>&1)
    assert_contains "$result" "event_type" "应该显示事件类型列"
    assert_contains "$result" "create" "应该显示 create 事件"
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

it "list 命令应该支持包含单引号的项目路径"
test_list_with_quoted_project_path() {
    local quoted_project="/tmp/O'Brien"
    echo "quoted project list" | "$CLI" capture -p "$quoted_project" -c "context" -t "quoted" > /dev/null 2>&1

    local result=$("$CLI" list -p "$quoted_project" -l 5 2>&1)
    assert_contains "$result" "$quoted_project" "应该返回带单引号的项目路径"
    assert_contains "$result" "quoted project list" "应该返回对应项目的记忆"
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

it "export 默认目录应从顶层 markdown_export_path 读取"
test_export_reads_top_level_markdown_export_path() {
    local config_file="$CCMEM_CONFIG_FILE"
    local export_dir="$TEST_DB_DIR/top-level-exports"
    mkdir -p "$export_dir"

    python3 - <<PY
import json
path = "$config_file"
with open(path) as f:
    data = json.load(f)
data["markdown_export_path"] = "$export_dir"
data.pop("memory", None)
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\\n")
PY

    local result
    result=$("$CLI" export 2>&1)

    assert_contains "$result" "导出记忆到：$export_dir" "默认导出目录应来自顶层 markdown_export_path"
}

# ═══════════════════════════════════════════════════════════
# 测试：retry 命令
# ═══════════════════════════════════════════════════════════

describe "retry 命令"

it "应该恢复失败队列中的记忆并删除队列文件"
test_retry_recovers_failed_capture() {
    local config_file="$CCMEM_CONFIG_FILE"
    local queue_dir="$TEST_DB_DIR/retry-queue"
    local payload="[FILE_CHANGE] updated lib/retry.sh: fix retry parsing"
    mkdir -p "$queue_dir"

    python3 - <<PY
import json
path = "$config_file"
with open(path) as f:
    data = json.load(f)
data["failed_queue_dir"] = "$queue_dir"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\\n")
PY

    cat > "$queue_dir/failed_post-tool-use_test_001.log" <<'EOF'
# hook=post-tool-use session_id=test_retry reason=capture_failed queued_at=2026-03-08T00:00:00Z
[FILE_CHANGE] updated lib/retry.sh: fix retry parsing
EOF

    local result
    result=$("$CLI" retry 2>&1)

    assert_contains "$result" "成功恢复：1" "应该恢复 1 条失败记忆"
    assert_equals "0" "$(find "$queue_dir" -type f | wc -l | tr -d ' ')" "成功恢复后应删除队列文件"
    assert_equals "1" "$(db_query "SELECT COUNT(*) FROM memories WHERE source = 'post_tool_use' AND content = '$payload';")" "应写入恢复后的记忆"
}

it "duplicate 应视为成功并删除队列文件"
test_retry_treats_duplicate_as_success() {
    local config_file="$CCMEM_CONFIG_FILE"
    local queue_dir="$TEST_DB_DIR/retry-duplicate-queue"
    local payload="[FILE_CHANGE] updated lib/retry.sh: fix duplicate handling"
    mkdir -p "$queue_dir"

    python3 - <<PY
import json
path = "$config_file"
with open(path) as f:
    data = json.load(f)
data["failed_queue_dir"] = "$queue_dir"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\\n")
PY

    store_memory "dup_retry" "/tmp/retry-project" "solution" "$payload" "duplicate summary" "auto-captured" "what-changed" "post_tool_use" "working" "conditional" "/tmp/retry-project" > /dev/null

    cat > "$queue_dir/failed_post-tool-use_test_002.log" <<EOF
# hook=post-tool-use session_id=test_retry reason=capture_failed queued_at=2026-03-08T00:00:00Z
$payload
EOF

    local result
    result=$("$CLI" retry 2>&1)

    assert_contains "$result" "重复跳过：1" "duplicate 应计入重复跳过"
    assert_equals "0" "$(find "$queue_dir" -type f | wc -l | tr -d ' ')" "duplicate 也应删除队列文件"
}

it "--dry-run 不应删除队列文件"
test_retry_dry_run_keeps_files() {
    local config_file="$CCMEM_CONFIG_FILE"
    local queue_dir="$TEST_DB_DIR/retry-dry-run-queue"
    mkdir -p "$queue_dir"

    python3 - <<PY
import json
path = "$config_file"
with open(path) as f:
    data = json.load(f)
data["failed_queue_dir"] = "$queue_dir"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\\n")
PY

    cat > "$queue_dir/failed_stop_test_003.log" <<'EOF'
# hook=stop session_id=test_retry reason=capture_failed queued_at=2026-03-08T00:00:00Z
[FILE_CHANGE] updated hooks/stop.sh: improve summary
EOF

    local result
    result=$("$CLI" retry --dry-run 2>&1)

    assert_contains "$result" "将处理失败项：1" "dry-run 应显示将处理数量"
    assert_equals "1" "$(find "$queue_dir" -type f | wc -l | tr -d ' ')" "dry-run 不应删除队列文件"
}

it "--hook 应只处理匹配的失败项"
test_retry_filters_by_hook() {
    local config_file="$CCMEM_CONFIG_FILE"
    local queue_dir="$TEST_DB_DIR/retry-hook-queue"
    mkdir -p "$queue_dir"

    python3 - <<PY
import json
path = "$config_file"
with open(path) as f:
    data = json.load(f)
data["failed_queue_dir"] = "$queue_dir"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\\n")
PY

    cat > "$queue_dir/failed_stop_test_004.log" <<'EOF'
# hook=stop session_id=test_retry reason=capture_failed queued_at=2026-03-08T00:00:00Z
[FILE_CHANGE] updated hooks/stop.sh: recover stop queue
EOF

    cat > "$queue_dir/failed_session-end_test_005.log" <<'EOF'
# hook=session-end session_id=test_retry reason=capture_failed queued_at=2026-03-08T00:00:00Z
[FILE_CHANGE] updated hooks/session-end.sh: keep original log
EOF

    local result
    result=$("$CLI" retry --hook stop 2>&1)

    assert_contains "$result" "匹配处理：1" "应只处理匹配 hook 的失败项"
    assert_equals "1" "$(find "$queue_dir" -type f | wc -l | tr -d ' ')" "未匹配的队列文件应保留"
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
# 测试：项目关联命令
# ═══════════════════════════════════════════════════════════

describe "项目关联命令"

it "应该建立并列出项目关联"
test_related_projects_commands() {
    "$CLI" link-projects "/repo/cli-app" "/repo/cli-lib" --reason "cli test" > /dev/null 2>&1

    local result
    result=$("$CLI" related-projects -p "/repo/cli-app" 2>&1)
    assert_contains "$result" "/repo/cli-lib" "应该列出关联项目"
    assert_contains "$result" "manual" "应该显示手动关联类型"
}

it "应该删除项目关联"
test_unlink_projects_command() {
    "$CLI" link-projects "/repo/cli-unlink-a" "/repo/cli-unlink-b" > /dev/null 2>&1
    "$CLI" unlink-projects "/repo/cli-unlink-a" "/repo/cli-unlink-b" > /dev/null 2>&1

    local result
    result=$("$CLI" related-projects -p "/repo/cli-unlink-a" 2>&1)
    assert_not_contains "$result" "/repo/cli-unlink-b" "删除后不应再显示关联项目"
}

it "应该刷新自动项目关联"
test_refresh_project_links_command() {
    echo "父项目记忆" | "$CLI" capture -p "/repo/refresh-parent" -c "decision" > /dev/null 2>&1
    echo "子项目记忆" | "$CLI" capture -p "/repo/refresh-parent/child" -c "context" > /dev/null 2>&1

    local refresh_output
    refresh_output=$("$CLI" refresh-project-links -p "/repo/refresh-parent/child" 2>&1)
    assert_contains "$refresh_output" "已刷新项目关联" "应该提示刷新成功"

    local related_output
    related_output=$("$CLI" related-projects -p "/repo/refresh-parent/child" 2>&1)
    assert_contains "$related_output" "/repo/refresh-parent" "应该识别父项目关联"
}

# ═══════════════════════════════════════════════════════════
# 测试：inject-context 命令
# ═══════════════════════════════════════════════════════════

describe "inject-context 命令"

it "应该生成结构化上下文"
test_inject_context_outputs_context() {
    echo "SessionStart CLI 内容" | "$CLI" capture -p "/tmp/sessionstart-cli" -c "decision" -t "cli" > /dev/null 2>&1

    local result=$("$CLI" inject-context -p "/tmp/sessionstart-cli" -l 2 2>&1)
    assert_contains "$result" "<cc-mem-context>" "应该输出上下文标签"
    assert_contains "$result" "Recent High-Value Memory" "应该包含高价值记忆部分"
    assert_not_contains "$result" "搜索记忆" "不应该输出搜索命令标题"
}

# ═══════════════════════════════════════════════════════════
# 测试：cleanup 命令
# ═══════════════════════════════════════════════════════════

describe "cleanup 命令"

it "默认 cleanup 应只清理低优先级临时记忆"
test_cleanup_safe_mode() {
    store_memory "cleanup_safe_1" "/tmp/cleanup-safe" "context" "safe temporary old" "safe temporary old" "" "" "session_end" "temporary" "never" "/tmp/cleanup-safe" "2000-01-01 00:00:00" > /dev/null
    store_memory "cleanup_safe_2" "/tmp/cleanup-safe" "context" "safe working old" "safe working old" "" "" "manual" "working" "conditional" "/tmp/cleanup-safe" "2000-01-01 00:00:00" > /dev/null

    local result
    result=$("$CLI" cleanup 2>&1)

    local temporary_count
    temporary_count=$(db_query "SELECT COUNT(*) FROM memories WHERE summary='safe temporary old';")
    local working_count
    working_count=$(db_query "SELECT COUNT(*) FROM memories WHERE summary='safe working old';")

    assert_contains "$result" "safe" "默认 cleanup 应显示 safe 模式"
    assert_equals "0" "$temporary_count" "默认 cleanup 应删除低优先级临时记忆"
    assert_equals "1" "$working_count" "默认 cleanup 不应删除 working 记忆"
}

it "aggressive cleanup 应清理过期 working 记忆"
test_cleanup_aggressive_mode() {
    store_memory "cleanup_aggr_1" "/tmp/cleanup-aggr" "context" "aggressive working old" "aggressive working old" "" "" "manual" "working" "conditional" "/tmp/cleanup-aggr" "2000-01-01 00:00:00" > /dev/null

    local result
    result=$("$CLI" cleanup --aggressive 2>&1)

    local working_count
    working_count=$(db_query "SELECT COUNT(*) FROM memories WHERE summary='aggressive working old';")

    assert_contains "$result" "aggressive" "aggressive cleanup 应显示 aggressive 模式"
    assert_equals "0" "$working_count" "aggressive cleanup 应删除过期 working 记忆"
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
test_status_shows_failed_queue_summary
test_status_shows_recent_cleanup_summary

# stats 命令测试
test_stats_shows_summary
test_stats_supports_project_filter

# capture 命令测试
test_capture_memory
test_capture_auto_detect_concepts
test_capture_supports_custom_summary
test_capture_detects_duplicate
test_capture_filters_private
test_capture_rejects_whitespace_only
test_capture_rejects_invalid_category

# search 命令测试
test_search_memories
test_search_shows_params
test_search_memories_cjk_fallback

# recall 命令测试
test_recall_generates_recall_block

# history 命令测试
test_history_shows_recent
test_history_shows_event_type

# list 命令测试
test_list_memories
test_list_limit
test_list_with_quoted_project_path

# export 命令测试
test_export_to_directory
test_export_creates_markdown_files

# projects 命令测试
test_projects_lists_projects

# 项目关联命令测试
test_related_projects_commands
test_unlink_projects_command
test_refresh_project_links_command

# inject-context 命令测试
test_inject_context_outputs_context

# cleanup 命令测试
test_cleanup_safe_mode
test_cleanup_aggressive_mode

# 错误处理测试
test_unknown_command
test_help_flag

# 打印测试报告
print_summary
exit_code=$?

exit $exit_code
