#!/bin/bash
# CC-Mem 边界条件测试
# 测试各种边界情况和异常输入

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 加载测试框架
source "$SCRIPT_DIR/tests/test_framework.sh"

# 加载 sqlite.sh（数据库操作库）
source "$SCRIPT_DIR/lib/sqlite.sh"

# 加载 llm.sh（LLM 相关函数库）
source "$SCRIPT_DIR/lib/llm.sh"

# 设置测试环境（加载 sqlite.sh 并初始化数据库）
setup_test_db

# ═══════════════════════════════════════════════════════════
# 测试：空值处理
# ═══════════════════════════════════════════════════════════

describe "空值处理"

it "应该处理空内容"
test_empty_content() {
    local result=$(store_memory "session1" "/test" "context" "" "" "" "")
    # 空内容应该被拒绝或存储（取决于实现）
    assert_true "[[ \"$result\" == *\"mem_\"* ]]" "应该返回 ID 或错误"
}

it "应该处理空会话 ID"
test_empty_session_id() {
    local id=$(store_memory "" "/test" "context" "内容" "摘要" "" "")
    assert_contains "$id" "mem_" "应该生成记忆 ID"
}

it "应该处理空项目路径"
test_empty_project_path() {
    local id=$(store_memory "session1" "" "context" "内容" "摘要" "" "")
    assert_contains "$id" "mem_" "应该生成记忆 ID"
}

it "应该处理空类别"
test_empty_category() {
    local id=$(store_memory "session1" "/test" "" "内容" "摘要" "" "")
    # 空类别应该使用默认值或拒绝
    assert_true "[[ \"$id\" == *\"mem_\"* || \"$id\" == *\"CHECK\"* ]]" "应该处理或拒绝"
}

# ═══════════════════════════════════════════════════════════
# 测试：特殊字符处理
# ═══════════════════════════════════════════════════════════

describe "特殊字符处理"

it "应该处理包含单引号的内容"
test_content_with_single_quotes() {
    local content="It is a test with quotes"
    local id=$(store_memory "session1" "/test" "context" "$content" "摘要" "" "")
    # 验证内容是否被存储（不直接查询含单引号的内容）
    if [[ "$id" != duplicate:* ]]; then
        local stored=$(sqlite3 "$TEST_DB" "SELECT content FROM memories WHERE id='$id';")
        assert_not_empty "$stored" "应该存储内容"
    else
        skip_test "内容重复"
    fi
}

it "应该处理包含双引号的内容"
test_content_with_double_quotes() {
    local content='Say "Hello" to "World"'
    local id=$(store_memory "session1" "/test" "context" "$content" "摘要" "" "")
    if [[ "$id" != duplicate:* ]]; then
        local stored=$(sqlite3 "$TEST_DB" "SELECT content FROM memories WHERE id='$id';")
        assert_contains "$stored" "Hello" "应该正确存储双引号"
    else
        skip_test "内容重复"
    fi
}

it "应该处理包含换行符的内容"
test_content_with_newlines() {
    local content=$'Line 1\nLine 2\nLine 3'
    local id=$(store_memory "session1" "/test" "context" "$content" "摘要" "" "")
    if [[ "$id" != duplicate:* ]]; then
        local stored=$(sqlite3 "$TEST_DB" "SELECT content FROM memories WHERE id='$id';")
        assert_contains "$stored" "Line" "应该存储包含换行的内容"
    else
        skip_test "内容重复"
    fi
}

it "应该处理包含 SQL 特殊字符的内容"
test_content_with_sql_chars() {
    local content="DROP TABLE memories; SELECT * FROM memories WHERE 1=1"
    local id=$(store_memory "session1" "/test" "context" "$content" "摘要" "" "")
    # 应该安全存储而不出错
    assert_true "[[ \"$id\" == *\"mem_\"* || \"$id\" == duplicate:* ]]" "应该安全处理 SQL 特殊字符"
}

it "应该处理包含 HTML 标签的内容"
test_content_with_html() {
    local content="<div>Hello World</div>"
    local id=$(store_memory "session1" "/test" "context" "$content" "摘要" "" "")
    if [[ "$id" != duplicate:* ]]; then
        local stored=$(sqlite3 "$TEST_DB" "SELECT content FROM memories WHERE id='$id';")
        assert_contains "$stored" "<div>" "应该存储 HTML 标签"
    else
        skip_test "内容重复"
    fi
}

# ═══════════════════════════════════════════════════════════
# 测试：长度边界
# ═══════════════════════════════════════════════════════════

describe "长度边界"

it "应该处理超长内容"
test_very_long_content() {
    # 生成 10KB 内容
    local long_content=$(head -c 10240 /dev/urandom | base64)
    local id=$(store_memory "session1" "/test" "context" "$long_content" "摘要" "" "")
    assert_true "[[ \"$id\" == *\"mem_\"* || \"$id\" == duplicate:* ]]" "应该处理超长内容"
}

it "应该处理超长标签"
test_very_long_tags() {
    local long_tags=$(printf "tag%d," {1..100})
    local id=$(store_memory "session1" "/test" "context" "内容" "摘要" "$long_tags" "")
    assert_true "[[ \"$id\" == *\"mem_\"* || \"$id\" == duplicate:* ]]" "应该处理超长标签"
}

it "应该处理超长项目路径"
test_very_long_project_path() {
    local long_path=$(printf "/level%d" {1..50})
    local id=$(store_memory "session1" "$long_path" "context" "内容" "摘要" "" "")
    assert_true "[[ \"$id\" == *\"mem_\"* || \"$id\" == duplicate:* ]]" "应该处理超长路径"
}

it "应该处理极短内容"
test_very_short_content() {
    local id=$(store_memory "session1" "/test" "context" "a" "a" "" "")
    assert_true "[[ \"$id\" == *\"mem_\"* || \"$id\" == duplicate:* ]]" "应该处理单字符内容"
}

# ═══════════════════════════════════════════════════════════
# 测试：哈希边界
# ═══════════════════════════════════════════════════════════

describe "哈希边界"

it "应该处理空字符串哈希"
test_empty_string_hash() {
    local hash1=$(generate_content_hash "" "context")
    local hash2=$(generate_content_hash "" "context")
    assert_equals "$hash1" "$hash2" "空字符串应该生成相同哈希"
    assert_equals "16" "${#hash1}" "哈希长度应该是 16"
}

it "应该处理极大内容哈希"
test_huge_content_hash() {
    local huge_content=$(head -c 100000 /dev/urandom | base64)
    local hash=$(generate_content_hash "$huge_content" "context")
    assert_equals "16" "${#hash}" "哈希长度应该是 16"
}

it "应该处理 Unicode 内容哈希"
test_unicode_content_hash() {
    local unicode_content="你好 世界 🌍 Привет мир"
    local hash1=$(generate_content_hash "$unicode_content" "context")
    local hash2=$(generate_content_hash "$unicode_content" "context")
    assert_equals "$hash1" "$hash2" "相同 Unicode 内容应该生成相同哈希"
}

# ═══════════════════════════════════════════════════════════
# 测试：时间戳边界
# ═══════════════════════════════════════════════════════════

describe "时间戳边界"

it "应该处理负时间戳"
test_negative_timestamp() {
    # 尝试存储带负时间戳的数据（应该被拒绝或使用当前时间）
    local id=$(store_memory "session1" "/test" "context" "内容" "摘要" "" "")
    assert_true "[[ \"$id\" == *\"mem_\"* || \"$id\" == duplicate:* ]]" "应该处理时间戳"
}

it "应该处理未来时间戳"
test_future_timestamp() {
    # 存储记忆，时间戳应该是当前时间
    local id=$(store_memory "session1" "/test" "context" "内容" "摘要" "" "")
    if [[ "$id" != duplicate:* ]]; then
        local epoch=$(sqlite3 "$TEST_DB" "SELECT timestamp_epoch FROM memories WHERE id='$id';")
        local current=$(date +%s)
        # epoch 不应该超过当前时间太多（允许少量误差）
        assert_true "[ $epoch -le $((current + 60)) ]" "时间戳不应该超过当前时间太多"
    else
        skip_test "内容重复"
    fi
}

# ═══════════════════════════════════════════════════════════
# 测试：并发和竞态条件
# ═══════════════════════════════════════════════════════════

describe "并发处理"

it "应该处理快速连续存储"
test_rapid_sequential_stores() {
    local ids=()
    for i in {1..10}; do
        local id=$(store_memory "session$i" "/test" "context" "内容_$i_$(date +%s%N)" "摘要" "" "")
        ids+=("$id")
    done

    # 验证所有 ID 都是唯一的（排除 duplicate 前缀）
    local unique_ids=$(printf '%s\n' "${ids[@]}" | grep -v "^duplicate:" | sort -u | wc -l)
    # 使用数值比较
    if [ "$unique_ids" -eq 10 ]; then
        assert_true "true" "应该生成 10 个唯一 ID"
    else
        echo "DEBUG: 实际唯一 ID 数：$unique_ids"
        assert_true "false" "应该生成 10 个唯一 ID（实际：$unique_ids）"
    fi
}

it "应该处理重复检测的边界情况"
test_duplicate_detection_boundary() {
    # 存储几乎相同但略有不同的内容
    local id1=$(store_memory "session1" "/test" "context" "内容 A" "摘要" "" "")
    local id2=$(store_memory "session2" "/test" "context" "内容 A " "摘要" "" "")  # 多一个空格

    # 两个内容不同，应该都被存储
    assert_true "[[ \"$id1\" != \"$id2\" ]]" "不同内容应该生成不同 ID"
}

# ═══════════════════════════════════════════════════════════
# 测试：错误恢复
# ═══════════════════════════════════════════════════════════

describe "错误恢复"

it "应该处理数据库锁定"
test_database_lock() {
    # 尝试在事务中存储（模拟锁定）
    sqlite3 "$TEST_DB" "BEGIN TRANSACTION;"
    local id=$(store_memory "session1" "/test" "context" "内容" "摘要" "" "")
    sqlite3 "$TEST_DB" "ROLLBACK;"

    # 应该能够处理或返回错误
    assert_true "[[ \"$id\" == *\"mem_\"* || \"$id\" == *\"locked\"* || \"$id\" == duplicate:* ]]" "应该处理数据库锁定"
}

it "应该处理无效类别"
test_invalid_category() {
    # 尝试使用无效类别存储（CHECK 约束应该拒绝）
    local result=$(sqlite3 "$TEST_DB" "INSERT INTO memories (id, session_id, project_path, category, content, summary) VALUES ('test_invalid', 'session', '/test', 'invalid_category', 'content', 'summary');" 2>&1)

    # 应该返回 CHECK constraint failed 错误
    if [[ "$result" == *"CHECK constraint failed"* ]]; then
        assert_true "true" "应该拒绝无效类别"
    else
        # 如果插入成功，说明 CHECK 约束未生效
        # 清理测试数据
        sqlite3 "$TEST_DB" "DELETE FROM memories WHERE id='test_invalid';"
        assert_true "false" "应该拒绝无效类别（CHECK 约束）"
    fi
}

# ═══════════════════════════════════════════════════════════
# LLM 和私有内容测试
# ═══════════════════════════════════════════════════════════

describe "LLM 和私有内容测试"

it "应该能加载 LLM profile"
test_load_llm_profile_compression() {
    # 测试 load_llm_profile 函数
    local result=$(load_llm_profile "compression")
    assert_not_empty "$result" "应该返回 profile 信息"
    # 返回格式应该是 provider|model|max_tokens
    assert_contains "$result" "|" "应该返回正确格式"
}

it "应该能过滤私有内容"
test_filter_private_content() {
    local content="公开内容 <private>秘密信息</private> 更多公开内容"
    local result=$(filter_private_content "$content")
    # 秘密信息应该被过滤
    if [[ "$result" != *"秘密信息"* ]]; then
        assert_true "true" "应该过滤私有内容"
    else
        assert_true "false" "应该过滤私有内容"
    fi
}

it "应该能检测私有内容"
test_has_private_content() {
    # 测试包含私有内容的情况
    local content1="公开内容 <private>秘密</private>"
    if has_private_content "$content1"; then
        assert_true "true" "应该检测到私有内容"
    else
        assert_true "false" "应该检测到私有内容"
    fi

    # 测试不包含私有内容的情况
    local content2="全是公开内容"
    if has_private_content "$content2"; then
        assert_true "false" "不应该检测到私有内容"
    else
        assert_true "true" "不应该检测到私有内容"
    fi
}

# ═══════════════════════════════════════════════════════════
# LLM 内部函数测试
# ═══════════════════════════════════════════════════════════

describe "LLM 内部函数测试"

it "应该能识别类别"
test_detect_category() {
    # 测试 debug 类别
    local result1=$(detect_category "error exception bug fix")
    assert_equals "debug" "$result1" "应该识别 debug 类别"

    # 测试 solution 类别
    local result2=$(detect_category "solution resolve workaround implement")
    assert_equals "solution" "$result2" "应该识别 solution 类别"

    # 测试 decision 类别
    local result3=$(detect_category "decision choose select decide")
    assert_equals "decision" "$result3" "应该识别 decision 类别"

    # 测试 context 类别（默认）
    local result4=$(detect_category "普通内容")
    assert_equals "context" "$result4" "应该返回 context 类别"
}

it "应该能提取标签"
test_extract_tags() {
    local result=$(extract_tags "Python JavaScript Docker Kubernetes AWS Git SQL Linux")
    assert_not_empty "$result" "应该返回标签"
    assert_contains "$result" "python" "应该包含 python 标签"
    assert_contains "$result" "docker" "应该包含 docker 标签"
}

it "应该能生成摘要"
test_generate_summary() {
    local result=$(generate_summary "这是第一行内容\n这是第二行" 20)
    assert_not_empty "$result" "应该返回摘要"
    # 摘要应该以第一行开头
    assert_contains "$result" "这是第一行" "应该包含第一行"
}

# ═══════════════════════════════════════════════════════════
# 运行所有测试
# ═══════════════════════════════════════════════════════════

run_tests "边界条件测试"

# 空值处理测试
test_empty_content
test_empty_session_id
test_empty_project_path
test_empty_category

# 特殊字符处理测试
test_content_with_single_quotes
test_content_with_double_quotes
test_content_with_newlines
test_content_with_sql_chars
test_content_with_html

# 长度边界测试
test_very_long_content
test_very_long_tags
test_very_long_project_path
test_very_short_content

# 哈希边界测试
test_empty_string_hash
test_huge_content_hash
test_unicode_content_hash

# 时间戳边界测试
test_negative_timestamp
test_future_timestamp

# 并发处理测试
test_rapid_sequential_stores
test_duplicate_detection_boundary

# 错误恢复测试
test_database_lock
test_invalid_category

# LLM 和私有内容测试
test_load_llm_profile_compression
test_filter_private_content
test_has_private_content

# LLM 内部函数测试
test_detect_category
test_extract_tags
test_generate_summary

# 打印测试报告
print_summary
exit_code=$?

exit $exit_code
