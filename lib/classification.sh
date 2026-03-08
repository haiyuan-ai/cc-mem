#!/bin/bash

classification_matches() {
    local text="$1"
    local pattern="$2"

    [ -z "$text" ] && return 1
    printf "%s" "$text" | grep -Eqi "$pattern"
}

classification_append_reason() {
    local current="$1"
    local addition="$2"

    if [ -z "$addition" ]; then
        printf "%s" "$current"
    elif [ -z "$current" ]; then
        printf "%s" "$addition"
    else
        printf "%s, %s" "$current" "$addition"
    fi
}

classification_add_score() {
    local score_var="$1"
    local reason_var="$2"
    local delta="$3"
    local reason="$4"
    local current_score="${!score_var}"
    local current_reason="${!reason_var}"
    local next_reason=""

    current_score="${current_score:-0}"
    current_score=$((current_score + delta))
    eval "$score_var=\"$current_score\""

    next_reason=$(classification_append_reason "$current_reason" "$reason")
    eval "$reason_var=\"\$next_reason\""
}

apply_keyword_scores() {
    local text="$1"
    local weight="${2:-1}"

    classification_matches "$text" '\b(decision|decided|choose|chosen|select|selected|adopt|adopted|trade-?off|policy|approach)\b|决定|采用|改为|选用|取舍|方案|策略' \
        && classification_add_score decision_score decision_reason $((4 * weight)) "decision keywords"

    classification_matches "$text" '\b(solution|resolved?|fixed?|implemented?|completed?|workaround|created|added support)\b|解决|修复|已完成|实现|完成|回退方案|补丁|workaround' \
        && classification_add_score solution_score solution_reason $((4 * weight)) "solution keywords"

    classification_matches "$text" '\b(error|errors|debug|debugging|fail|failed|crash|bug|trace|stack|investigat(e|ion)?|root cause|issue)\b|报错|错误|异常|失败|调试|排查|定位|原因|复现' \
        && classification_add_score debug_score debug_reason $((4 * weight)) "debug keywords"

    classification_matches "$text" '\b(pattern|convention|best practice|guideline|always|never|standardi[sz]e|consistent)\b|模式|约定|规范|最佳实践|统一|以后|规则' \
        && classification_add_score pattern_score pattern_reason $((4 * weight)) "pattern keywords"

    classification_matches "$text" '\b(context|background|status|summary|note)\b|背景|上下文|状态|说明|记录|摘要' \
        && classification_add_score context_score context_reason $((2 * weight)) "context keywords"
}

apply_source_bias() {
    local source="$1"

    case "$source" in
        manual)
            classification_add_score decision_score decision_reason 3 "manual source"
            classification_add_score pattern_score pattern_reason 2 "manual source"
            classification_add_score solution_score solution_reason 1 "manual source"
            ;;
        post_tool_use)
            classification_add_score debug_score debug_reason 3 "post_tool_use source"
            classification_add_score context_score context_reason 2 "post_tool_use source"
            ;;
        user_prompt_submit)
            classification_add_score debug_score debug_reason 2 "user_prompt_submit source"
            classification_add_score context_score context_reason 3 "user_prompt_submit source"
            ;;
        stop_summary)
            classification_add_score solution_score solution_reason 3 "stop_summary source"
            classification_add_score debug_score debug_reason 2 "stop_summary source"
            classification_add_score context_score context_reason 2 "stop_summary source"
            ;;
        stop_final_response)
            classification_add_score solution_score solution_reason 2 "stop_final_response source"
            classification_add_score context_score context_reason 3 "stop_final_response source"
            classification_add_score pattern_score pattern_reason 1 "stop_final_response source"
            ;;
        session_end)
            classification_add_score context_score context_reason 2 "session_end source"
            classification_add_score solution_score solution_reason 1 "session_end source"
            classification_add_score debug_score debug_reason 1 "session_end source"
            ;;
    esac
}

classification_text_length() {
    local text="$1"
    printf "%s" "$text" | tr -d '[:space:]' | wc -c | tr -d ' '
}

is_ephemeral_user_prompt() {
    local text="$1"
    local compact_length=0

    compact_length=$(classification_text_length "$text")
    if [ "$compact_length" -le 6 ]; then
        return 0
    fi

    classification_matches "$text" '^(可以|好|好的|继续|继续吧|开始吧|修复吧|提交并 ?push|push|commit|ok|okay|yes|no|行|先这样|先这样吧)[[:space:][:punct:]]*$'
}

apply_source_specific_scores() {
    local source="$1"
    local summary="$2"
    local content="$3"
    local combined="$summary $content"

    case "$source" in
        user_prompt_submit)
            if [ -n "$summary" ] && is_ephemeral_user_prompt "$summary"; then
                classification_add_score context_score context_reason 4 "ephemeral prompt"
            fi

            if [ -n "$summary" ] && classification_matches "$summary" '不要|别|统一|默认|优先|改成|改为|放进|保留|避免|以后|先.+再|不要单独|按.+处理|命名|风格|约束|规则|偏好'; then
                classification_add_score pattern_score pattern_reason 6 "reusable prompt pattern"
            fi

            if [ -n "$summary" ] && classification_matches "$summary" '决定|采用|选用|改为|先.+再|不再|方案|节奏|顺序|流程'; then
                classification_add_score decision_score decision_reason 5 "reusable prompt decision"
            fi
            ;;
        post_tool_use)
            if classification_matches "$combined" '\[BASH\].*(error|errors|failed|fail|not found|permission denied|syntax error)|报错|失败|异常'; then
                classification_add_score debug_score debug_reason 5 "tool error signal"
            fi

            if classification_matches "$combined" '(\[FILE_CHANGE\].*(fix|fixed|修复|回退|避免|workaround|resolved)|\b(fix|fixed|resolved|workaround)\b|修复|解决|回退方案|避免再次出现)'; then
                classification_add_score solution_score solution_reason 5 "tool fix signal"
            fi

            if classification_matches "$combined" '(test|tests|lint|build).*(passed|pass|succeeded|ok)|([0-9]+ passed, 0 failed)|测试通过|构建成功|验证通过'; then
                classification_add_score solution_score solution_reason 4 "tool verification signal"
            fi

            if classification_matches "$combined" '\[FILE_CHANGE\].*(统一|约定|规范|命名|structure|convention|pattern|best practice)'; then
                classification_add_score pattern_score pattern_reason 4 "tool pattern signal"
            fi
            ;;
        stop_summary)
            if classification_matches "$combined" '决定|改为|不再|原因|取舍|trade-?off|方案'; then
                classification_add_score decision_score decision_reason 4 "stop summary decision signal"
            fi

            if classification_matches "$combined" '已修复|已完成|实现了|增加了|支持|处理了|测试通过|验证通过'; then
                classification_add_score solution_score solution_reason 4 "stop summary outcome signal"
            fi
            ;;
    esac
}

apply_tag_and_concept_scores() {
    local tags="$1"
    local concepts="$2"
    local combined="$tags $concepts"

    classification_matches "$combined" 'trade-?off|decision|policy|选择|取舍|决策' \
        && classification_add_score decision_score decision_reason 3 "tag/concept match"
    classification_matches "$combined" 'fix|resolved?|workaround|solution|修复|解决' \
        && classification_add_score solution_score solution_reason 3 "tag/concept match"
    classification_matches "$combined" 'debug|error|issue|bug|调试|错误|问题' \
        && classification_add_score debug_score debug_reason 3 "tag/concept match"
    classification_matches "$combined" 'pattern|best practice|convention|规范|模式|最佳实践' \
        && classification_add_score pattern_score pattern_reason 3 "tag/concept match"
}

classification_confidence_for_scores() {
    local top_score="$1"
    local second_score="$2"
    local top_category="$3"
    local delta=$((top_score - second_score))

    if [ "$top_category" = "context" ] && [ "$top_score" -le 6 ]; then
        echo "45"
    elif [ "$delta" -ge 8 ]; then
        echo "95"
    elif [ "$delta" -ge 5 ]; then
        echo "85"
    elif [ "$delta" -ge 3 ]; then
        echo "75"
    elif [ "$delta" -ge 1 ]; then
        echo "65"
    else
        echo "55"
    fi
}

classify_memory() {
    local source="$1"
    local summary="$2"
    local content="$3"
    local tags="$4"
    local concepts="$5"

    CLASSIFY_DECISION_SCORE=0
    CLASSIFY_SOLUTION_SCORE=0
    CLASSIFY_DEBUG_SCORE=0
    CLASSIFY_PATTERN_SCORE=0
    CLASSIFY_CONTEXT_SCORE=1

    CLASSIFY_DECISION_REASON=""
    CLASSIFY_SOLUTION_REASON=""
    CLASSIFY_DEBUG_REASON=""
    CLASSIFY_PATTERN_REASON=""
    CLASSIFY_CONTEXT_REASON="default fallback"

    local top_category="context"
    local top_score=0
    local second_score=0
    local confidence=""
    local reason=""

    decision_score="$CLASSIFY_DECISION_SCORE"
    solution_score="$CLASSIFY_SOLUTION_SCORE"
    debug_score="$CLASSIFY_DEBUG_SCORE"
    pattern_score="$CLASSIFY_PATTERN_SCORE"
    context_score="$CLASSIFY_CONTEXT_SCORE"

    decision_reason="$CLASSIFY_DECISION_REASON"
    solution_reason="$CLASSIFY_SOLUTION_REASON"
    debug_reason="$CLASSIFY_DEBUG_REASON"
    pattern_reason="$CLASSIFY_PATTERN_REASON"
    context_reason="$CLASSIFY_CONTEXT_REASON"

    apply_source_bias "$source"
    apply_keyword_scores "$summary" 2
    apply_keyword_scores "$content" 1
    apply_tag_and_concept_scores "$tags" "$concepts"
    apply_source_specific_scores "$source" "$summary" "$content"

    if classification_matches "$content $summary" '^(?:\[FILE_CHANGE\]|\[BASH\])' ; then
        classification_add_score context_score context_reason 1 "operation log shape"
    fi

    for category in decision solution debug pattern context; do
        local score_var="${category}_score"
        local score="${!score_var}"
        if [ "$score" -gt "$top_score" ]; then
            second_score="$top_score"
            top_score="$score"
            top_category="$category"
        elif [ "$score" -gt "$second_score" ]; then
            second_score="$score"
        fi
    done

    case "$top_category" in
        decision) reason="$decision_reason" ;;
        solution) reason="$solution_reason" ;;
        debug) reason="$debug_reason" ;;
        pattern) reason="$pattern_reason" ;;
        *) reason="$context_reason" ;;
    esac

    [ -z "$reason" ] && reason="fallback:no_strong_signal"
    confidence=$(classification_confidence_for_scores "$top_score" "$second_score" "$top_category")

    printf "%s|%s|%s\n" "$top_category" "$confidence" "$reason"
}

classify_memory_category() {
    local result=""
    result=$(classify_memory "$@")
    printf "%s\n" "$result" | cut -d'|' -f1
}

classify_memory_confidence() {
    local result=""
    result=$(classify_memory "$@")
    printf "%s\n" "$result" | cut -d'|' -f2
}

classify_memory_reason() {
    local result=""
    result=$(classify_memory "$@")
    printf "%s\n" "$result" | cut -d'|' -f3-
}
