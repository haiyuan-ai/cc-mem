#!/bin/bash
# LLM API 调用函数库

# 默认配置
LLM_PROVIDER="${LLM_PROVIDER:-anthropic}"
LLM_MODEL="${LLM_MODEL:-claude-sonnet-4-6}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

# 从配置文件加载 LLM profiles（如果存在）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.json"

load_llm_profile() {
    local profile_name="${1:-default}"

    if [ -f "$CONFIG_FILE" ] && command -v jq &> /dev/null; then
        local profile=$(jq -r ".llm_profiles.$profile_name // empty" "$CONFIG_FILE" 2>/dev/null)

        if [ -n "$profile" ]; then
            local provider=$(jq -r ".llm_profiles.$profile_name.provider // \"$LLM_PROVIDER\"" "$CONFIG_FILE" 2>/dev/null)
            local model=$(jq -r ".llm_profiles.$profile_name.model // \"$LLM_MODEL\"" "$CONFIG_FILE" 2>/dev/null)
            local max_tokens=$(jq -r ".llm_profiles.$profile_name.max_tokens // 1024" "$CONFIG_FILE" 2>/dev/null)

            echo "$provider|$model|$max_tokens"
            return
        fi
    fi

    # 回退到默认值
    echo "$LLM_PROVIDER|$LLM_MODEL|1024"
}

# 概念标签定义 - 使用简单变量存储关键词（兼容 grep）
CONCEPT_how_it_works="工作原理|如何实现 | 机制 | 流程 | 步骤"
CONCEPT_why_it_exists="为什么 | 原因 | 背景 | 目的 | 理由"
CONCEPT_what_changed="修改 | 变更 | 更新 | 升级 | 迁移"
CONCEPT_problem_solution="问题 | 解决 | 修复 | 方案 | 办法"
CONCEPT_gotcha="注意 | 坑 | 陷阱 | 警告 | 限制 | 坑点"
CONCEPT_pattern="模式 | 模板 | 最佳实践 | 复用 | 规范"
CONCEPT_trade_off="权衡 | 取舍 | 优缺点 | 对比 | 选择"

# 计算匹配数量（使用多个 grep -o）
count_matches() {
    local content="$1"
    local pattern="$2"
    local count=0
    local keyword
    local matches

    # 将模式按 | 分割，逐个匹配
    IFS='|' read -ra keywords <<< "$pattern"
    for keyword in "${keywords[@]}"; do
        # 去除前后空格
        keyword=$(echo "$keyword" | xargs)
        if [ -n "$keyword" ]; then
            matches=$(echo "$content" | grep -o "$keyword" 2>/dev/null | wc -l)
            count=$((count + matches))
        fi
    done

    echo "$count"
}

# 自动识别概念标签
detect_concepts() {
    local content="$1"
    local min_matches="${2:-1}"
    local detected_concepts=""
    local count

    # how-it-works
    count=$(count_matches "$content" "$CONCEPT_how_it_works")
    if [ "$count" -ge "$min_matches" ]; then
        detected_concepts="${detected_concepts:+$detected_concepts,}how-it-works"
    fi

    # why-it-exists
    count=$(count_matches "$content" "$CONCEPT_why_it_exists")
    if [ "$count" -ge "$min_matches" ]; then
        detected_concepts="${detected_concepts:+$detected_concepts,}why-it-exists"
    fi

    # what-changed
    count=$(count_matches "$content" "$CONCEPT_what_changed")
    if [ "$count" -ge "$min_matches" ]; then
        detected_concepts="${detected_concepts:+$detected_concepts,}what-changed"
    fi

    # problem-solution
    count=$(count_matches "$content" "$CONCEPT_problem_solution")
    if [ "$count" -ge "$min_matches" ]; then
        detected_concepts="${detected_concepts:+$detected_concepts,}problem-solution"
    fi

    # gotcha
    count=$(count_matches "$content" "$CONCEPT_gotcha")
    if [ "$count" -ge "$min_matches" ]; then
        detected_concepts="${detected_concepts:+$detected_concepts,}gotcha"
    fi

    # pattern
    count=$(count_matches "$content" "$CONCEPT_pattern")
    if [ "$count" -ge "$min_matches" ]; then
        detected_concepts="${detected_concepts:+$detected_concepts,}pattern"
    fi

    # trade-off
    count=$(count_matches "$content" "$CONCEPT_trade_off")
    if [ "$count" -ge "$min_matches" ]; then
        detected_concepts="${detected_concepts:+$detected_concepts,}trade-off"
    fi

    echo "$detected_concepts"
}

# 压缩 Prompt 模板（参考 mem0 设计优化）
compress_prompt_template() {
    local session_content="$1"
    local category="$2"

    cat <<EOF
You are a Personal Information Organizer, specialized in accurately storing facts, user memories, and preferences.
Your primary role is to extract relevant pieces of information from conversations and organize them into structured memories.

# [IMPORTANT]: GENERATE MEMORIES SOLELY BASED ON THE USER'S MESSAGES.
# [IMPORTANT]: DON'T INCLUDE INFORMATION FROM ASSISTANT OR SYSTEM MESSAGES.
# [IMPORTANT]: AVOID duplicating existing information.

## Memory Types to Extract:

1. **Decisions**: Important technical choices, architecture decisions
2. **Solutions**: Problems solved, implementation methods
3. **Patterns**: Reusable code patterns, workflows, best practices
4. **Debug Records**: Errors encountered, troubleshooting process
5. **Context**: Background information, notes

## Output Format

Please output in the following JSON format:

{
    "summary": "One sentence summary (50 characters max)",
    "category": "decision|solution|pattern|debug|context",
    "key_points": ["key point 1", "key point 2", ...],
    "code_snippets": [{"language": "bash", "code": "..."}],
    "tags": ["tag1", "tag2"],
    "concepts": ["how-it-works", "problem-solution", "gotcha"],
    "context": "Related background information"
}

## Examples

**Example 1 - Decision:**
Input: "I decided to use SQLite instead of PostgreSQL because it's lighter and doesn't require a separate server."
Output: {
    "summary": "选择 SQLite 而非 PostgreSQL",
    "category": "decision",
    "key_points": ["SQLite 更轻量", "不需要独立服务器"],
    "tags": ["database", "architecture"],
    "concepts": ["trade-off"]
}

**Example 2 - Solution:**
Input: "The fix was to add a timeout parameter. Setting timeout=5000 solved the connection issue."
Output: {
    "summary": "通过添加 timeout 参数修复连接问题",
    "category": "solution",
    "key_points": ["添加 timeout 参数", "timeout=5000 解决问题"],
    "tags": ["bugfix", "connection"],
    "concepts": ["problem-solution"]
}

**Example 3 - Gotcha:**
Input: "Be careful with SQLite locking. It can timeout in concurrent scenarios."
Output: {
    "summary": "注意 SQLite 并发锁超时问题",
    "category": "context",
    "key_points": ["SQLite 可能锁超时", "并发场景需注意"],
    "tags": ["sqlite", "warning"],
    "concepts": ["gotcha"]
}

## Input Content

$session_content

---

Extract key memories from the input above (output JSON only, no other text):
EOF
}

# 使用 Anthropic API 进行压缩（支持 profile）
compress_with_anthropic() {
    local content="$1"
    local profile_name="${2:-compression}"  # 默认使用 compression profile

    # 加载 profile 配置
    local profile_info=$(load_llm_profile "$profile_name")
    local provider=$(echo "$profile_info" | cut -d'|' -f1)
    local model=$(echo "$profile_info" | cut -d'|' -f2)
    local max_tokens=$(echo "$profile_info" | cut -d'|' -f3)

    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo "错误：ANTHROPIC_API_KEY 未设置" >&2
        return 1
    fi

    local prompt=$(compress_prompt_template "$content")

    local response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"$model\",
            \"max_tokens\": $max_tokens,
            \"messages\": [
                {
                    \"role\": \"user\",
                    \"content\": \"$prompt\"
                }
            ]
        }")

    # 解析响应
    echo "$response" | jq -r '.content[0].text // empty'
}

# 简单的本地压缩（无 LLM 时的备选方案）
compress_local() {
    local content="$1"

    # 提取关键行（包含特定关键词）
    local keywords="decision|solution|fix|error|important|note|TODO|FIXME|key|remember"
    local compressed=$(echo "$content" | grep -iE "$keywords" | head -20)

    if [ -n "$compressed" ]; then
        echo "$compressed"
    else
        # 如果没有关键词匹配，取首尾各 5 行
        {
            echo "=== 开始 ==="
            echo "$content" | head -5
            echo "..."
            echo "$content" | tail -5
            echo "=== 结束 ==="
        } | tr '\n' ' ' | fold -w 80
    fi
}

# 主压缩函数（支持 profile）
compress_memory() {
    local content="$1"
    local use_llm="${2:-false}"
    local profile_name="${3:-compression}"

    if [ "$use_llm" = "true" ]; then
        compress_with_anthropic "$content" "$profile_name"
    else
        compress_local "$content"
    fi
}

# 从内容中自动识别类别
detect_category() {
    local content="$1"

    if echo "$content" | grep -qiE "error|exception|bug|fix|debug|troubleshoot"; then
        echo "debug"
    elif echo "$content" | grep -qiE "solution|resolve|workaround|implement"; then
        echo "solution"
    elif echo "$content" | grep -qiE "decision|choose|select|decide|option"; then
        echo "decision"
    elif echo "$content" | grep -qiE "pattern|template|boilerplate|reusable"; then
        echo "pattern"
    else
        echo "context"
    fi
}

# 从内容中提取标签
extract_tags() {
    local content="$1"

    # 提取技术相关关键词
    local tags=$(echo "$content" | \
        grep -oE '\b(python|javascript|typescript|react|node|docker|kubernetes|aws|gcp|azure|git|sql|nosql|api|rest|graphql|bash|shell|linux|macos|windows)\b' | \
        sort -u | \
        tr '\n' ',' | \
        sed 's/,$//')

    echo "$tags"
}

# 生成记忆摘要
generate_summary() {
    local content="$1"
    local max_length="${2:-100}"

    # 简单实现：取第一句非空行
    local first_line=$(echo "$content" | grep -v '^$' | head -1)
    echo "${first_line:0:$max_length}..."
}

# 过滤私有内容（<private> 标签内的内容）
filter_private_content() {
    local content="$1"

    # 移除 <private>...</private> 标签内的内容
    # 使用 perl 处理多行内容（如果可用），否则使用简单的 sed
    if command -v perl &> /dev/null; then
        echo "$content" | perl -0777 -pe 's/<private>.*?<\/private>//gs'
    else
        # 简单的单行 sed 处理
        echo "$content" | sed 's/<private>[^<]*<\/private>//g'
    fi
}

# 检查内容是否包含私有标记
has_private_content() {
    local content="$1"

    if echo "$content" | grep -q "<private>"; then
        return 0  # 包含私有内容
    else
        return 1  # 不包含私有内容
    fi
}
