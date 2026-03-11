#!/bin/bash
# 内容处理辅助函数库
# Source guard - prevent double-loading
[[ -n "${_CCMEM_CONTENT_UTILS_SH_LOADED:-}" ]] && return 0 2>/dev/null || true
_CCMEM_CONTENT_UTILS_SH_LOADED=1

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
        keyword=$(printf "%s" "$keyword" | xargs)
        if [ -n "$keyword" ]; then
            matches=$(printf "%s\n" "$content" | grep -o "$keyword" 2>/dev/null | wc -l)
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

# 过滤私有内容（<private> 标签内的内容）
filter_private_content() {
    local content="$1"

    # 移除 <private>...</private> 标签内的内容
    # 使用 perl 处理多行内容（如果可用），否则使用简单的 sed
    if command -v perl &> /dev/null; then
        printf "%s" "$content" | perl -0777 -pe 's/<private>.*?<\/private>//gs'
    else
        # 简单的单行 sed 处理
        printf "%s\n" "$content" | sed 's/<private>[^<]*<\/private>//g'
    fi
}

# 检查内容是否包含私有标记
has_private_content() {
    local content="$1"

    if printf "%s" "$content" | grep -q "<private>"; then
        return 0  # 包含私有内容
    else
        return 1  # 不包含私有内容
    fi
}
