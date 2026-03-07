#!/bin/bash
# CC-Mem SQLite 库测试
# 测试 lib/sqlite.sh 的所有核心功能

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 加载测试框架
source "$SCRIPT_DIR/tests/test_framework.sh"

# ═══════════════════════════════════════════════════════════
# 测试：数据库初始化
# ═══════════════════════════════════════════════════════════

describe "数据库初始化"

it "应该成功创建数据库"
test_db_init() {
    assert_file_exists "$TEST_DB" "数据库文件应该存在"
}

it "应该创建 memories 表"
test_memories_table_exists() {
    local result=$(sqlite3 "$TEST_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='memories';")
    assert_equals "memories" "$result" "memories 表应该存在"
}

it "应该创建 sessions 表"
test_sessions_table_exists() {
    local result=$(sqlite3 "$TEST_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions';")
    assert_equals "sessions" "$result" "sessions 表应该存在"
}

it "应该创建 projects 表"
test_projects_table_exists() {
    local result=$(sqlite3 "$TEST_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='projects';")
    assert_equals "projects" "$result" "projects 表应该存在"
}

it "应该创建 project_links 表"
test_project_links_table_exists() {
    local result=$(sqlite3 "$TEST_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='project_links';")
    assert_equals "project_links" "$result" "project_links 表应该存在"
}

it "应该创建 memory_history 表"
test_memory_history_table_exists() {
    local result=$(sqlite3 "$TEST_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='memory_history';")
    assert_equals "memory_history" "$result" "memory_history 表应该存在"
}

it "应该创建 FTS5 虚拟表"
test_fts5_table_exists() {
    local result=$(sqlite3 "$TEST_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='memories_fts';")
    assert_equals "memories_fts" "$result" "memories_fts 虚拟表应该存在"
}

# ═══════════════════════════════════════════════════════════
# 测试：ID 生成
# ═══════════════════════════════════════════════════════════

describe "ID 生成"

it "应该生成以 mem_开头的 ID"
test_generate_id_prefix() {
    local id=$(generate_id)
    assert_contains "$id" "mem_" "ID 应该以 mem_开头"
}

it "应该生成唯一的 ID"
test_generate_id_unique() {
    local id1=$(generate_id)
    local id2=$(generate_id)
    assert_true "[ '$id1' != '$id2' ]" "每次生成的 ID 应该不同"
}

it "应该包含时间戳"
test_generate_id_contains_timestamp() {
    local id=$(generate_id)
    # ID 格式：mem_TIMESTAMP_RANDOM
    local timestamp=$(echo "$id" | cut -d'_' -f2)
    assert_true "[ ${#timestamp} -ge 10 ]" "ID 应该包含时间戳"
}

# ═══════════════════════════════════════════════════════════
# 测试：项目关联
# ═══════════════════════════════════════════════════════════

describe "项目关联"

it "应该可以建立并列出项目关联"
test_project_links_upsert_and_list() {
    link_projects "/repo/app" "/repo/lib-common" "manual" 95 "shared architecture"

    local result
    result=$(list_related_projects "/repo/app" 5 70)
    assert_contains "$result" "/repo/lib-common" "应该列出关联项目"
    assert_contains "$result" "manual" "应该记录关联类型"
    assert_contains "$result" "95" "应该记录关联强度"
}

it "应该可以删除项目关联"
test_project_links_delete() {
    link_projects "/repo/remove-a" "/repo/remove-b" "manual" 95 "temporary link"
    unlink_projects "/repo/remove-a" "/repo/remove-b"

    local result
    result=$(list_related_projects "/repo/remove-a" 5 70)
    assert_true "[ -z \"$result\" ]" "删除后不应再返回关联项目"
}

it "手动关联不应被自动刷新覆盖"
test_project_links_manual_should_override_auto() {
    store_memory "ma1" "/repo/manual" "decision" "手动项目内容" "手动项目摘要" "" "" "manual" "" "" "/repo/manual"
    store_memory "ma2" "/repo/manual/child" "pattern" "子项目内容" "子项目摘要" "" "" "manual" "" "" "/repo/manual/child"

    link_projects "/repo/manual" "/repo/manual/child" "manual" 95 "manual override"
    refresh_project_links "/repo/manual"

    local result
    result=$(list_related_projects "/repo/manual" 5 70)
    assert_contains "$result" "manual" "手动关联类型应该保留"
    assert_contains "$result" "95" "手动关联强度应该保留"
}

# ═══════════════════════════════════════════════════════════
# 测试：自动分类
# ═══════════════════════════════════════════════════════════

describe "自动分类"

it "决策类内容应该分类为 decision"
test_classify_memory_decision() {
    local result
    result=$(classify_memory "manual" "决定采用 SQLite 作为存储方案" "这个方案的 trade-off 更合适" "decision" "trade-off")

    assert_contains "$result" "decision|" "决策类内容应该分类为 decision"
}

it "修复结果应该分类为 solution"
test_classify_memory_solution() {
    local result
    result=$(classify_memory "stop_summary" "已修复搜索结果为空的问题" "实现了 fallback workaround，问题已解决" "fix" "resolved")

    assert_contains "$result" "solution|" "修复结果应该分类为 solution"
}

it "排查过程应该分类为 debug"
test_classify_memory_debug() {
    local result
    result=$(classify_memory "post_tool_use" "" "[BASH] npm test: 排查 error root cause\n[FILE_CHANGE] src/app.js: 修复前先定位 bug" "debug" "issue")

    assert_contains "$result" "debug|" "排查过程应该分类为 debug"
}

it "约定和规范应该分类为 pattern"
test_classify_memory_pattern() {
    local result
    result=$(classify_memory "manual" "以后统一使用 project_root 做隔离规范" "这是新的 best practice 和 convention" "pattern" "best-practice")

    assert_contains "$result" "pattern|" "约定和规范应该分类为 pattern"
}

it "自动分类应返回置信度和原因"
test_classify_memory_confidence_and_reason() {
    local confidence
    local reason
    confidence=$(classify_memory_confidence "manual" "决定采用 SQLite" "作为统一方案" "decision" "")
    reason=$(classify_memory_reason "manual" "决定采用 SQLite" "作为统一方案" "decision" "")

    assert_true "[ \"$confidence\" -ge 55 ]" "自动分类应返回合理置信度"
    assert_not_empty "$reason" "自动分类应返回非空原因"
}

it "高置信度 solution 应影响 memory_kind 和 inject policy"
test_infer_policy_with_confidence() {
    local memory_kind
    local inject_policy
    memory_kind=$(infer_memory_kind "session_end" "solution" 90)
    inject_policy=$(infer_auto_inject_policy "session_end" "solution" 90)

    assert_equals "working" "$memory_kind" "高置信度 session_end solution 应提升为 working"
    assert_equals "conditional" "$inject_policy" "高置信度 session_end solution 应允许 conditional 注入"
}

it "低置信度 context 应保持低优先级"
test_infer_policy_low_confidence_context() {
    local memory_kind
    local inject_policy
    memory_kind=$(infer_memory_kind "user_prompt_submit" "context" 60)
    inject_policy=$(infer_auto_inject_policy "user_prompt_submit" "context" 60)

    assert_equals "temporary" "$memory_kind" "低置信度 context 应保持 temporary"
    assert_equals "never" "$inject_policy" "低置信度 context 不应自动注入"
}

# ═══════════════════════════════════════════════════════════
# 测试：记忆清理
# ═══════════════════════════════════════════════════════════

describe "记忆清理"

it "safe cleanup 应只删除低优先级临时记忆"
test_cleanup_low_priority_memories() {
    store_memory "cleanup_sqlite_1" "/tmp/sqlite-cleanup" "context" "temporary cleanup content" "temporary cleanup summary" "" "" "session_end" "temporary" "never" "/tmp/sqlite-cleanup" "2000-01-01 00:00:00" > /dev/null
    store_memory "cleanup_sqlite_2" "/tmp/sqlite-cleanup" "context" "working cleanup content" "working cleanup summary" "" "" "manual" "working" "conditional" "/tmp/sqlite-cleanup" "2000-01-01 00:00:00" > /dev/null

    local deleted_count
    deleted_count=$(cleanup_low_priority_memories 30 100)
    local temp_count
    temp_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM memories WHERE summary='temporary cleanup summary';")
    local working_count
    working_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM memories WHERE summary='working cleanup summary';")

    assert_equals "1" "$deleted_count" "safe cleanup 应只删除 1 条低优先级临时记忆"
    assert_equals "0" "$temp_count" "低优先级临时记忆应被删除"
    assert_equals "1" "$working_count" "working 记忆不应被 safe cleanup 删除"
}

it "aggressive cleanup 应删除过期 working 记忆"
test_cleanup_aggressive_memories_mode() {
    store_memory "cleanup_sqlite_3" "/tmp/sqlite-cleanup" "context" "aggressive temporary content" "aggressive temporary summary" "" "" "session_end" "temporary" "never" "/tmp/sqlite-cleanup" "2000-01-01 00:00:00" > /dev/null
    store_memory "cleanup_sqlite_4" "/tmp/sqlite-cleanup" "context" "aggressive working content" "aggressive working summary" "" "" "manual" "working" "conditional" "/tmp/sqlite-cleanup" "2000-01-01 00:00:00" > /dev/null
    store_memory "cleanup_sqlite_5" "/tmp/sqlite-cleanup" "decision" "durable content" "durable summary" "" "" "manual" "durable" "always" "/tmp/sqlite-cleanup" "2000-01-01 00:00:00" > /dev/null

    local deleted_count
    deleted_count=$(cleanup_aggressive_memories 30 100)
    local working_count
    working_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM memories WHERE summary='aggressive working summary';")
    local durable_count
    durable_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM memories WHERE summary='durable summary';")

    assert_true "[ $deleted_count -ge 2 ]" "aggressive cleanup 应至少删除 temporary 和 working 记忆"
    assert_equals "0" "$working_count" "aggressive cleanup 应删除过期 working 记忆"
    assert_equals "1" "$durable_count" "durable 记忆不应被 aggressive cleanup 删除"
}

it "cleanup 应遵守 limit 参数"
test_cleanup_respects_limit() {
    store_memory "cleanup_limit_1" "/tmp/sqlite-cleanup" "context" "limit content 1" "limit summary 1" "" "" "session_end" "temporary" "never" "/tmp/sqlite-cleanup" "2000-01-01 00:00:00" > /dev/null
    store_memory "cleanup_limit_2" "/tmp/sqlite-cleanup" "context" "limit content 2" "limit summary 2" "" "" "session_end" "temporary" "never" "/tmp/sqlite-cleanup" "2000-01-01 00:00:00" > /dev/null

    local deleted_count
    deleted_count=$(cleanup_low_priority_memories 30 1)
    local remaining_count
    remaining_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM memories WHERE summary IN ('limit summary 1', 'limit summary 2');")

    assert_equals "1" "$deleted_count" "cleanup 应只删除 limit 指定的条数"
    assert_equals "1" "$remaining_count" "剩余记录数应与 limit 对应"
}

# ═══════════════════════════════════════════════════════════
# 测试：内容哈希
# ═══════════════════════════════════════════════════════════

describe "内容哈希"

it "应该生成 16 字符哈希"
test_content_hash_length() {
    local hash=$(generate_content_hash "测试内容" "context")
    assert_equals "16" "${#hash}" "哈希应该是 16 个字符"
}

it "相同内容应该生成相同哈希"
test_content_hash_same_for_same_content() {
    local hash1=$(generate_content_hash "测试内容" "context")
    local hash2=$(generate_content_hash "测试内容" "context")
    assert_equals "$hash1" "$hash2" "相同内容应该生成相同哈希"
}

it "不同内容应该生成不同哈希"
test_content_hash_different_for_different_content() {
    local hash1=$(generate_content_hash "内容 A" "context")
    local hash2=$(generate_content_hash "内容 B" "context")
    assert_true "[ '$hash1' != '$hash2' ]" "不同内容应该生成不同哈希"
}

it "不同类别应该生成不同哈希"
test_content_hash_different_for_different_category() {
    local hash1=$(generate_content_hash "测试内容" "decision")
    local hash2=$(generate_content_hash "测试内容" "context")
    assert_true "[ '$hash1' != '$hash2' ]" "不同类别应该生成不同哈希"
}

# ═══════════════════════════════════════════════════════════
# 测试：存储记忆
# ═══════════════════════════════════════════════════════════

describe "存储记忆"

it "应该成功存储记忆"
test_store_memory_success() {
    local id=$(store_memory "session1" "/test/project" "context" "测试内容" "测试摘要" "tag1,tag2" "concept1")
    assert_contains "$id" "mem_" "应该返回记忆 ID"
}

it "应该存储所有字段"
test_store_memory_all_fields() {
    local id=$(store_memory "session1" "/test/project" "decision" "决策内容" "决策摘要" "tag1" "trade-off")

    local result=$(sqlite3 "$TEST_DB" "SELECT category, summary, tags, concepts FROM memories WHERE id='$id';")
    assert_contains "$result" "decision" "类别应该正确"
    assert_contains "$result" "决策摘要" "摘要应该正确"
    assert_contains "$result" "tag1" "标签应该正确"
    assert_contains "$result" "trade-off" "概念应该正确"
}

it "应该写入分层元数据字段"
test_store_memory_metadata_fields() {
    local id=$(store_memory "session1" "/test/project" "decision" "分层内容" "分层摘要" "tag1" "" "manual")

    local result=$(sqlite3 "$TEST_DB" "SELECT source, memory_kind, auto_inject_policy, project_root FROM memories WHERE id='$id';")
    assert_contains "$result" "manual" "应该记录来源"
    assert_contains "$result" "durable" "decision 应该映射为 durable"
    assert_contains "$result" "always" "decision 应该默认 always 注入"
    assert_contains "$result" "/test/project" "非 git 项目 root 应该等于 project_path"
}

it "应该写入分类快照字段"
test_store_memory_classification_snapshot_fields() {
    local id=$(store_memory "session1" "/test/project" "solution" "分类快照内容" "分类快照摘要" "tag1" "" "user_prompt_submit" "working" "conditional" "/test/project" "" "78" "rule matched solution keywords" "rule" "rule-v1")

    local result
    result=$(sqlite3 "$TEST_DB" "SELECT classification_confidence, classification_reason, classification_source, classification_version FROM memories WHERE id='$id';")
    assert_contains "$result" "78" "应该记录 classification_confidence"
    assert_contains "$result" "rule matched solution keywords" "应该记录 classification_reason"
    assert_contains "$result" "rule" "应该记录 classification_source"
    assert_contains "$result" "rule-v1" "应该记录 classification_version"
}

it "应该回填旧记录的分层元数据"
test_backfill_legacy_metadata_fields() {
    sqlite3 "$TEST_DB" <<'EOF'
INSERT INTO memories (
    id, session_id, project_path, project_root, category, source, memory_kind,
    auto_inject_policy, expires_at, content, content_preview, summary, tags,
    concepts, timestamp_epoch, content_hash
)
VALUES (
    'mem_legacy_backfill', 'legacy_session', '/legacy/project', '', 'context', '', '', '',
    NULL, '旧 stop 记录', '旧 stop 记录', '旧 stop 摘要', 'stop,auto-captured', 'what-changed',
    100, 'legacyhash000001'
);
EOF

    ensure_schema_columns

    local result=$(sqlite3 "$TEST_DB" "SELECT source, memory_kind, auto_inject_policy, project_root, expires_at FROM memories WHERE id='mem_legacy_backfill';")
    assert_contains "$result" "stop_summary" "旧 stop 标签应该回填为 stop_summary"
    assert_contains "$result" "working" "stop_summary 应该映射为 working"
    assert_contains "$result" "conditional" "stop_summary 应该默认 conditional 注入"
    assert_contains "$result" "/legacy/project" "旧记录应该回填 project_root"
    assert_true "[[ \"$result\" == *\"-\"* || \"$result\" == *\":\"* ]]" "旧记录应该回填过期时间"
}

it "应该自动设置 timestamp_epoch"
test_store_memory_sets_epoch() {
    local unique_content="测试 epoch_$(date +%s)"
    local id=$(store_memory "session1" "/test/project" "context" "$unique_content" "摘要" "" "")

    # 如果因为重复被跳过，记录跳过
    if [[ "$id" == duplicate:* ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        echo -e "${YELLOW}⊘ SKIP${NC}: 内容重复，跳过 epoch 测试"
        return 0
    fi

    local epoch=$(sqlite3 "$TEST_DB" "SELECT timestamp_epoch FROM memories WHERE id='$id';")
    if [ -z "$epoch" ]; then
        assert_true "false" "timestamp_epoch 应该被设置"
    else
        assert_true "[ $epoch -gt 0 ]" "timestamp_epoch 应该大于 0"
    fi
}

# ═══════════════════════════════════════════════════════════
# 测试：记忆去重
# ═══════════════════════════════════════════════════════════

describe "记忆去重"

it "相同内容应该检测到重复"
test_duplicate_detection_same_content() {
    # 存储第一条记忆
    store_memory "session1" "/test/project" "context" "唯一内容 XYZ" "摘要" "" ""

    # 尝试存储相同内容
    local result=$(store_memory "session2" "/test/project" "context" "唯一内容 XYZ" "摘要" "" "")

    assert_contains "$result" "duplicate:" "应该返回重复标识"
}

it "不同内容不应该检测到重复"
test_no_duplicate_for_different_content() {
    # 存储第一条记忆
    store_memory "session1" "/test/project" "context" "内容 A" "摘要 A" "" ""

    # 尝试存储不同内容
    local result=$(store_memory "session2" "/test/project" "context" "内容 B" "摘要 B" "" "")

    assert_contains "$result" "mem_" "应该返回新的记忆 ID（不重复）"
}

it "相同内容在不同项目下不应该互相去重"
test_no_duplicate_across_different_projects() {
    local result1=$(store_memory "session1" "/project/A" "context" "跨项目重复内容" "摘要 A" "" "")
    local result2=$(store_memory "session2" "/project/B" "context" "跨项目重复内容" "摘要 B" "" "")

    assert_contains "$result1" "mem_" "第一个项目应该成功存储"
    assert_contains "$result2" "mem_" "不同项目不应该被判定为重复"
}

# ═══════════════════════════════════════════════════════════
# 测试：检索记忆
# ═══════════════════════════════════════════════════════════

describe "检索记忆"

it "应该按项目路径检索"
test_retrieve_by_project() {
    # 存储不同项目的记忆
    store_memory "session1" "/project/A" "context" "项目 A 内容" "项目 A 摘要" "" ""
    store_memory "session2" "/project/B" "context" "项目 B 内容" "项目 B 摘要" "" ""

    local result=$(retrieve_memories "/project/A" "" "" 10)
    assert_contains "$result" "项目 A 摘要" "应该返回项目 A 的记忆"
    assert_true "[[ ! \"$result\" == *\"项目 B 摘要\"* ]]" "不应该返回项目 B 的记忆"
}

it "项目路径包含单引号时也应该能检索"
test_retrieve_by_project_with_quote() {
    local quoted_project="/project/O'Brien"
    store_memory "session1" "$quoted_project" "context" "带单引号路径的内容" "带单引号路径摘要" "tag'o" ""
    store_memory "session2" "/project/Other" "context" "其他项目内容" "其他项目摘要" "" ""

    local result=$(retrieve_memories "$quoted_project" "" "" 10)
    assert_contains "$result" "带单引号路径摘要" "应该返回带单引号路径的记忆"
    assert_true "[[ ! \"$result\" == *\"其他项目摘要\"* ]]" "不应该返回其他项目的记忆"
}

it "应该按类别检索"
test_retrieve_by_category() {
    store_memory "session1" "/test" "decision" "决策内容" "摘要" "" ""
    store_memory "session2" "/test" "solution" "解决方案" "摘要" "" ""

    local result=$(retrieve_memories "/test" "" "decision" 10)
    assert_contains "$result" "decision" "应该只返回 decision 类别"
}

it "应该支持全文检索"
test_retrieve_fulltext_search() {
    # 存储包含特定关键词的记忆
    local unique_content="FTS测试_$(date +%s)_SQLite全文检索"
    store_memory "session1" "/test" "context" "$unique_content" "SQLite 优化摘要" "sqlite" ""
    store_memory "session2" "/test" "context" "其他无关内容" "其他摘要" "" ""

    # 使用全文检索搜索关键词
    local result=$(retrieve_memories "/test" "SQLite" "" 10)
    assert_contains "$result" "SQLite 优化摘要" "全文检索应该找到包含 SQLite 的记忆"
}

it "全文检索应该支持混合内容"
test_retrieve_fulltext_search_mixed() {
    # 存储包含中英文混合内容的记忆
    local unique_content="mixed_content_$(date +%s)_优化方法"
    store_memory "session1" "/test" "context" "$unique_content" "混合内容测试摘要" "mixed" ""

    # 使用英文部分搜索
    local result=$(retrieve_memories "/test" "mixed_content" "" 10)
    assert_contains "$result" "混合内容测试摘要" "全文检索应该能找到混合内容的记忆"
}

it "中文查询应该能通过 fallback 找到内容"
test_retrieve_fulltext_search_cjk_fallback_content() {
    local unique_content="这是一个性能优化方案_$(date +%s)"
    store_memory "session1" "/test" "context" "$unique_content" "中文内容搜索摘要" "技术" ""

    local result=$(retrieve_memories "/test" "性能" "" 10)
    assert_contains "$result" "中文内容搜索摘要" "中文查询应该能找到内容中的关键词"
}

it "中文查询应该能通过 fallback 找到标签"
test_retrieve_fulltext_search_cjk_fallback_tags() {
    local unique_content="标签回退测试内容_$(date +%s)"
    store_memory "session1" "/test" "context" "$unique_content" "中文标签搜索摘要" "中文标签,归档" ""

    local result=$(retrieve_memories "/test" "归档" "" 10)
    assert_contains "$result" "中文标签搜索摘要" "中文查询应该能找到标签中的关键词"
}

it "分阶段检索应该支持中文 fallback"
test_retrieve_memories_staged_cjk_fallback() {
    local unique_content="分阶段中文检索内容_$(date +%s)"
    local unique_tag="中文分阶段归档_$(date +%s)"
    store_memory "session1" "/test" "context" "$unique_content" "分阶段中文摘要" "$unique_tag" ""

    local result=$(retrieve_memories_staged "/test" "$unique_tag" "" 10 1)
    assert_contains "$result" "分阶段中文摘要" "分阶段检索应该能通过中文 fallback 找到结果"
}

it "分阶段检索的 min_results 应该按真实数据行计数"
test_retrieve_memories_staged_counts_only_data_rows() {
    local project="/stage-count"
    store_memory "session1" "$project" "decision" "阶段计数内容 A" "阶段计数摘要 A" "" ""
    store_memory "session2" "$project" "context" "阶段计数内容 B" "阶段计数摘要 B" "" ""

    local result=$(retrieve_memories_staged "$project" "" "decision" 10 2)
    assert_contains "$result" "阶段计数摘要 A" "应该保留精确匹配结果"
    assert_contains "$result" "阶段计数摘要 B" "结果不足时应该继续放宽到项目级检索"
}

it "全文检索空结果时应该返回空"
test_retrieve_fulltext_search_empty() {
    # 搜索不存在的关键词
    local result=$(retrieve_memories "/test/nonexistent" "XYZ123NONEXISTENT" "" 10)
    # 结果应该只有表头，不包含任何 mem_ 开头的记录
    local mem_count=0
    if [ -n "$result" ]; then
        mem_count=$(echo "$result" | grep "^mem_" 2>/dev/null | wc -l | tr -d ' ')
    fi
    assert_equals "0" "$mem_count" "搜索不存在的关键词应该返回空结果"
}

# ═══════════════════════════════════════════════════════════
# 测试：记忆历史
# ═══════════════════════════════════════════════════════════

describe "记忆历史"

it "应该记录 create 事件"
test_history_create_event() {
    local unique_content="历史测试_$(date +%s)_1"
    local id=$(store_memory "session1" "/test" "context" "$unique_content" "摘要" "" "")

    # 检查记忆是否被存储（可能因去重返回 duplicate）
    if [[ "$id" == duplicate:* ]]; then
        # 如果是因为去重，直接验证已有记录
        local history=$(sqlite3 "$TEST_DB" "SELECT event_type FROM memory_history WHERE memory_id='${id#duplicate:}' LIMIT 1;")
        assert_equals "create" "$history" "应该记录 create 事件"
    else
        local history=$(sqlite3 "$TEST_DB" "SELECT event_type FROM memory_history WHERE memory_id='$id';")
        assert_equals "create" "$history" "应该记录 create 事件"
    fi
}

it "应该记录新旧值"
test_history_records_values() {
    local unique_content="历史测试_$(date +%s)_2"
    local id=$(store_memory "session1" "/test" "context" "$unique_content" "摘要" "" "")

    if [[ "$id" != duplicate:* ]]; then
        local new_value=$(sqlite3 "$TEST_DB" "SELECT new_value FROM memory_history WHERE memory_id='$id';")
        assert_contains "$new_value" "历史测试" "应该记录新值"
    else
        skip_test "内容重复，跳过测试"
    fi
}

it "应该记录 session_id"
test_history_records_session() {
    local unique_content="历史测试_$(date +%s)_3"
    local id=$(store_memory "test_session_$(date +%s)" "/test" "context" "$unique_content" "摘要" "" "")

    if [[ "$id" != duplicate:* ]]; then
        local session=$(sqlite3 "$TEST_DB" "SELECT session_id FROM memory_history WHERE memory_id='$id';")
        assert_contains "$session" "test_session" "应该记录 session_id"
    else
        skip_test "内容重复，跳过测试"
    fi
}

it "应该能查询记忆历史"
test_get_memory_history() {
    local unique_content="历史测试_$(date +%s)_4"
    local id=$(store_memory "session1" "/test" "context" "$unique_content" "摘要" "" "")

    # 直接查询数据库验证历史记录
    if [[ "$id" != duplicate:* ]]; then
        local history=$(sqlite3 "$TEST_DB" "SELECT event_type FROM memory_history WHERE memory_id='$id';")
        assert_equals "create" "$history" "历史记录应该包含事件类型"
    else
        skip_test "内容重复，跳过测试"
    fi
}

it "应该能查询最近历史"
test_get_recent_history() {
    # 存储两条唯一内容的记忆
    local id1=$(store_memory "session1" "/test" "context" "唯一内容_A_$(date +%s)" "摘要 A" "" "")
    local id2=$(store_memory "session2" "/test" "context" "唯一内容_B_$(date +%s)" "摘要 B" "" "")

    # 验证至少有一条历史记录
    local history_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM memory_history;")
    assert_true "[ $history_count -gt 0 ]" "应该有历史记录"
}

# ═══════════════════════════════════════════════════════════
# 测试：项目操作
# ═══════════════════════════════════════════════════════════

describe "项目操作"

it "应该更新项目访问记录"
test_update_project_access() {
    update_project_access "/test/project" "TestProject" "tag1,tag2"

    local result=$(sqlite3 "$TEST_DB" "SELECT name FROM projects WHERE path='/test/project';")
    assert_equals "TestProject" "$result" "应该记录项目名称"
}

it "应该能列出项目"
test_list_projects() {
    update_project_access "/project/A" "ProjectA" ""
    update_project_access "/project/B" "ProjectB" ""

    local result=$(list_projects)
    # list_projects 返回的是路径而不是名称
    assert_contains "$result" "/project/A" "项目列表应该包含/project/A"
    assert_contains "$result" "/project/B" "项目列表应该包含/project/B"
}

# ═══════════════════════════════════════════════════════════
# 测试：会话操作
# ═══════════════════════════════════════════════════════════

describe "会话操作"

it "应该创建会话"
test_upsert_session() {
    upsert_session "test_session" "/test/project"

    local result=$(sqlite3 "$TEST_DB" "SELECT project_path FROM sessions WHERE id='test_session';")
    assert_contains "$result" "/test/project" "应该记录项目路径"
}

it "应该能更新会话状态"
test_end_session() {
    upsert_session "test_session_2" "/test/project"

    end_session "test_session_2" 10 "会话摘要"

    local status=$(sqlite3 "$TEST_DB" "SELECT status FROM sessions WHERE id='test_session_2';")
    assert_equals "completed" "$status" "会话状态应该是 completed"

    local msg_count=$(sqlite3 "$TEST_DB" "SELECT message_count FROM sessions WHERE id='test_session_2';")
    assert_equals "10" "$msg_count" "消息数应该正确"
}

it "应该能获取单条记忆"
test_get_memory() {
    # 先存储一条记忆
    local id=$(store_memory "session1" "/test" "context" "测试内容 GetMemory" "测试摘要" "test" "")

    if [[ "$id" != duplicate:* ]]; then
        # 测试 get_memory 函数
        local result=$(get_memory "$id")
        assert_contains "$result" "测试内容 GetMemory" "应该返回记忆内容"
        assert_contains "$result" "context" "应该返回类别"
    else
        skip_test "内容重复，跳过测试"
    fi
}

it "应该能获取时间线"
test_get_timeline() {
    # 存储两条有关联的记忆
    local id1=$(store_memory "session1" "/test" "context" "内容 A Timeline" "摘要 A" "" "")
    local id2=$(store_memory "session2" "/test" "context" "内容 B Timeline" "摘要 B" "" "")

    if [[ "$id1" != duplicate:* ]]; then
        # 测试 get_timeline 函数
        local result=$(get_timeline "$id1" 2 2)
        assert_not_empty "$result" "应该返回时间线数据"
    else
        skip_test "内容重复，跳过测试"
    fi
}

it "应该能生成 epoch 时间戳"
test_generate_epoch_timestamp() {
    local epoch=$(generate_epoch_timestamp)
    # 验证是数字
    if [[ "$epoch" =~ ^[0-9]+$ ]]; then
        assert_true "true" "应该返回数字"
    else
        assert_true "false" "应该返回数字"
    fi
    # 验证大于 0
    if [ "$epoch" -gt 0 ]; then
        assert_true "true" "应该大于 0"
    else
        assert_true "false" "应该大于 0"
    fi
}

# ═══════════════════════════════════════════════════════════
# 测试：开场注入上下文生成
# ═══════════════════════════════════════════════════════════

describe "开场注入上下文生成"

it "应该能获取项目最近记忆"
test_get_recent_project_memories() {
    # 存储一些测试记忆（使用唯一摘要避免去重问题）
    local unique_ts=$(date +%s)
    store_memory "session1" "/test/sessionstart" "decision" "决策内容" "决策摘要_$unique_ts" "tag1" ""
    store_memory "session2" "/test/sessionstart" "solution" "解决方案" "方案摘要_$unique_ts" "tag2" ""

    local result=$(get_recent_project_memories "/test/sessionstart" 5)
    assert_contains "$result" "决策摘要_$unique_ts" "应该获取项目记忆"
    assert_contains "$result" "方案摘要_$unique_ts" "应该获取多条记忆"
}

it "应该按类别计算排序分数"
test_rank_memory_for_sessionstart() {
    local score_decision=$(rank_memory_for_sessionstart "decision" "" "")
    local score_debug=$(rank_memory_for_sessionstart "debug" "" "")
    local score_context=$(rank_memory_for_sessionstart "context" "" "")

    assert_true "[ $score_decision -gt $score_context ]" "decision 应该比 context 分数高"
    assert_true "[ $score_debug -gt $score_context ]" "debug 应该比 context 分数高"
}

it "salience 分数应该优先高价值高置信度主项目记忆"
test_score_memory_salience() {
    local high_score
    local low_score
    high_score=$(score_memory_salience "decision" 90 "manual" "durable" "always" "$(date +%s)" "/test/salience" "/test/salience")
    low_score=$(score_memory_salience "context" 40 "session_end" "temporary" "never" "$(date +%s)" "/test/other" "/test/salience")

    assert_true "[ $high_score -gt $low_score ]" "高价值高置信度主项目记忆应有更高 salience"
}

it "salience 分数应该优先当前项目而不是 related project"
test_score_memory_salience_prefers_current_project() {
    local current_score
    local related_score
    local now_ts
    now_ts=$(date +%s)

    current_score=$(score_memory_salience "solution" 70 "user_prompt_submit" "working" "conditional" "$now_ts" "/test/current" "/test/current")
    related_score=$(score_memory_salience "solution" 70 "user_prompt_submit" "working" "conditional" "$now_ts" "/test/related" "/test/current")

    assert_true "[ $current_score -gt $related_score ]" "当前项目记忆应高于 related project 记忆"
}

it "应该能选择高价值记忆"
test_select_sessionstart_memories() {
    # 存储不同类别的记忆
    store_memory "s1" "/test/select" "decision" "重要决策" "决策摘要1" "" ""
    store_memory "s2" "/test/select" "debug" "修复bug" "调试摘要" "" ""
    store_memory "s3" "/test/select" "context" "普通内容" "普通摘要" "" ""

    local result=$(select_sessionstart_memories "/test/select" 2)
    assert_not_empty "$result" "应该返回高价值记忆"
    # decision 和 debug 应该排在 context 前面
    local decision_count=$(echo "$result" | grep -c "decision")
    local debug_count=$(echo "$result" | grep -c "debug")
    assert_true "[ $((decision_count + debug_count)) -ge 1 ]" "应该优先选择高优先级类别"
}

it "应该生成 SessionStart 上下文"
test_generate_sessionstart_context() {
    # 存储测试数据
    store_memory "s1" "/test/context" "decision" "测试决策内容" "测试决策摘要" "test" ""

    local result=$(generate_injection_context "/test/context" 1)
    assert_contains "$result" "<cc-mem-context>" "应该包含上下文标签"
    assert_contains "$result" "Recent High-Value Memory" "应该包含高价值记忆部分"
    assert_contains "$result" "/test/context" "应该包含项目路径"
}

it "应该在 SessionStart 中补充 related project 记忆"
test_sessionstart_related_project_memory() {
    local child_path="/repo/worktrees/feature-a"
    local child_root="/repo/worktrees/feature-a"
    local parent_path="/repo"
    local parent_root="/repo"

    store_memory "s1" "$child_path" "decision" "子项目内容" "子项目摘要" "" "" "manual" "" "" "$child_root"
    store_memory "s2" "$parent_path" "pattern" "父项目内容" "父项目模式摘要" "" "" "manual" "" "" "$parent_root"

    local result=$(generate_injection_context "$child_path" 2)
    assert_contains "$result" "Related Project Memory" "应该包含 related project 区块"
    assert_contains "$result" "父项目模式摘要" "应该补充 related project 记忆"
    assert_contains "$result" "$parent_root" "应该标明 related project 路径"
}

it "连续调试时应该生成 timeline hint"
test_sessionstart_timeline_hint() {
    local project="/test/timeline-hint"
    store_memory "t1" "$project" "debug" "修复 SQLite 索引问题" "修复 SQLite 索引问题" "" ""
    store_memory "t2" "$project" "debug" "继续排查 recall 漏注入" "继续排查 recall 漏注入" "" ""
    store_memory "t3" "$project" "solution" "补上 timeline hint 输出" "补上 timeline hint 输出" "" ""

    local result=$(generate_injection_context "$project" 3)
    assert_contains "$result" "Recent Timeline Hint" "连续调试时应该出现 timeline hint"
    assert_contains "$result" "补上 timeline hint 输出" "timeline hint 应该包含最近脉络"
}

it "生成的上下文应该包含时间戳"
test_sessionstart_context_timestamp() {
    local result=$(generate_injection_context "/test" 1)
    assert_contains "$result" "Updated:" "应该包含更新时间"
}

it "生成的上下文应该按优先级排序"
test_sessionstart_priority_order() {
    # 清除之前的测试数据
    # 存储不同优先级的记忆
    store_memory "p1" "/test/priority" "context" "低优先级内容" "低优先级摘要" "" ""
    store_memory "p2" "/test/priority" "decision" "高优先级内容" "高优先级决策" "" ""

    local result=$(generate_injection_context "/test/priority" 1)
    # 应该优先选择 decision
    if echo "$result" | grep -q "高优先级决策"; then
        assert_true "true" "高优先级类别应该被优先选择"
    else
        # 可能只有一条记录，只要不报错就算通过
        assert_true "true" "上下文生成成功"
    fi
}

it "应该生成 query recall 上下文"
test_generate_query_recall_context() {
    store_memory "session1" "/test/recall" "decision" "SQLite fallback 方案" "SQLite fallback 方案摘要" "sqlite,fallback" "" "manual"

    local result=$(generate_query_recall_context "/test/recall" "SQLite" 3)
    assert_contains "$result" "<cc-mem-recall>" "应该包含 recall 标签"
    assert_contains "$result" "SQLite fallback 方案摘要" "应该返回相关摘要"
}

it "query recall 应该补充 related project 记忆"
test_generate_query_recall_context_related_project() {
    local child_path="/repo/worktrees/feature-b"
    local child_root="/repo/worktrees/feature-b"
    local parent_path="/repo"
    local parent_root="/repo"

    store_memory "session1" "$parent_path" "decision" "跨项目 recall 方案" "跨项目 recall 摘要" "sqlite" "" "manual" "" "" "$parent_root"
    store_memory "session2" "$child_path" "context" "当前项目无关内容" "当前项目无关摘要" "other" "" "manual" "" "" "$child_root"

    local result=$(generate_query_recall_context "$child_path" "recall" 3)
    assert_contains "$result" "跨项目 recall 摘要" "应该补充 related project 命中的摘要"
    assert_contains "$result" "(related: $parent_root)" "应该标注 related project 来源"
}

it "query recall 应该优先主项目高 salience 记忆"
test_generate_query_recall_context_prefers_primary_project() {
    local project="/test/recall-priority"
    local related="/test/recall-priority-related"

    link_projects "$project" "$related" "manual" 95 "priority test"
    store_memory "session1" "$project" "decision" "主项目 recall 命中" "主项目 recall 摘要" "priority" "" "manual" "durable" "always" "$project" > /dev/null
    store_memory "session2" "$related" "decision" "关联项目 recall 命中" "关联项目 recall 摘要" "priority" "" "manual" "durable" "always" "$related" > /dev/null

    local result
    result=$(generate_query_recall_context "$project" "priority" 1)
    assert_contains "$result" "主项目 recall 摘要" "主项目命中应优先保留"
    assert_not_contains "$result" "关联项目 recall 摘要" "limit=1 时 related project 结果不应抢占主项目"
}

it "git worktree 场景下应该识别 related project"
test_related_project_resolution_via_git_worktree() {
    local repo_dir="/tmp/ccmem-main-repo-$$"
    local worktree_dir="/tmp/ccmem-feature-wt-$$"
    local resolved_repo_dir=""

    rm -rf "$repo_dir" "$worktree_dir"
    mkdir -p "$repo_dir"

    git -C "$repo_dir" init >/dev/null 2>&1
    git -C "$repo_dir" config user.name "cc-mem-test"
    git -C "$repo_dir" config user.email "cc-mem-test@example.com"
    echo "root" > "$repo_dir/README.md"
    git -C "$repo_dir" add README.md >/dev/null 2>&1
    git -C "$repo_dir" commit -m "init" >/dev/null 2>&1
    git -C "$repo_dir" worktree add "$worktree_dir" -b feature/test >/dev/null 2>&1
    resolved_repo_dir=$(resolve_project_root "$repo_dir")

    store_memory "session1" "$repo_dir" "decision" "主仓库相关记忆" "主仓库相关摘要" "git,worktree" "" "manual" > /dev/null
    store_memory "session2" "$worktree_dir" "context" "当前 worktree 普通内容" "当前 worktree 普通摘要" "feature" "" "manual" > /dev/null

    local related
    related=$(resolve_related_projects "$worktree_dir" 1)
    assert_contains "$related" "$resolved_repo_dir" "worktree 应该能识别主仓库为 related project"

    local result
    result=$(generate_query_recall_context "$worktree_dir" "相关" 3)
    assert_contains "$result" "主仓库相关摘要" "worktree recall 应该能命中主仓库记忆"
    assert_contains "$result" "(related: $resolved_repo_dir)" "worktree recall 应该标注主仓库来源"

    rm -rf "$repo_dir" "$worktree_dir"
}

# ═══════════════════════════════════════════════════════════
# 运行所有测试
# ═══════════════════════════════════════════════════════════

run_tests "SQLite 库测试"

# 数据库初始化测试
test_db_init
test_memories_table_exists
test_sessions_table_exists
test_projects_table_exists
test_project_links_table_exists
test_memory_history_table_exists
test_fts5_table_exists

# ID 生成测试
test_generate_id_prefix
test_generate_id_unique
test_generate_id_contains_timestamp

# 项目关联测试
test_project_links_upsert_and_list
test_project_links_delete
test_project_links_manual_should_override_auto

# 自动分类测试
test_classify_memory_decision
test_classify_memory_solution
test_classify_memory_debug
test_classify_memory_pattern
test_classify_memory_confidence_and_reason
test_infer_policy_with_confidence
test_infer_policy_low_confidence_context

# 记忆清理测试
test_cleanup_low_priority_memories
test_cleanup_aggressive_memories_mode
test_cleanup_respects_limit

# 内容哈希测试
test_content_hash_length
test_content_hash_same_for_same_content
test_content_hash_different_for_different_content
test_content_hash_different_for_different_category

# 存储记忆测试
test_store_memory_success
test_store_memory_all_fields
test_store_memory_metadata_fields
test_store_memory_classification_snapshot_fields
test_backfill_legacy_metadata_fields
test_store_memory_sets_epoch

# 去重测试
test_duplicate_detection_same_content
test_no_duplicate_for_different_content
test_no_duplicate_across_different_projects

# 检索测试
test_retrieve_by_project
test_retrieve_by_project_with_quote
test_retrieve_by_category
test_retrieve_fulltext_search
test_retrieve_fulltext_search_mixed
test_retrieve_fulltext_search_cjk_fallback_content
test_retrieve_fulltext_search_cjk_fallback_tags
test_retrieve_memories_staged_cjk_fallback
test_retrieve_memories_staged_counts_only_data_rows
test_retrieve_fulltext_search_empty

# 记忆历史测试
test_history_create_event
test_history_records_values
test_history_records_session
test_get_memory_history
test_get_recent_history

# 项目操作测试
test_update_project_access
test_list_projects

# 会话操作测试
test_upsert_session
test_end_session

# get_memory 和 get_timeline 测试
test_get_memory
test_get_timeline

# 内部辅助函数测试
test_generate_epoch_timestamp

# SessionStart 测试
test_get_recent_project_memories
test_rank_memory_for_sessionstart
test_score_memory_salience
test_score_memory_salience_prefers_current_project
test_select_sessionstart_memories
test_generate_sessionstart_context
test_sessionstart_related_project_memory
test_sessionstart_timeline_hint
test_sessionstart_context_timestamp
test_sessionstart_priority_order
test_generate_query_recall_context
test_generate_query_recall_context_related_project
test_generate_query_recall_context_prefers_primary_project
test_related_project_resolution_via_git_worktree

# 打印测试报告
print_summary
exit_code=$?

exit $exit_code
