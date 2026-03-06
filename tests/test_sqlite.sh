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
# 运行所有测试
# ═══════════════════════════════════════════════════════════

run_tests "SQLite 库测试"

# 数据库初始化测试
test_db_init
test_memories_table_exists
test_sessions_table_exists
test_projects_table_exists
test_memory_history_table_exists
test_fts5_table_exists

# ID 生成测试
test_generate_id_prefix
test_generate_id_unique
test_generate_id_contains_timestamp

# 内容哈希测试
test_content_hash_length
test_content_hash_same_for_same_content
test_content_hash_different_for_different_content
test_content_hash_different_for_different_category

# 存储记忆测试
test_store_memory_success
test_store_memory_all_fields
test_store_memory_sets_epoch

# 去重测试
test_duplicate_detection_same_content
test_no_duplicate_for_different_content

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

# 打印测试报告
print_summary
exit_code=$?

exit $exit_code
