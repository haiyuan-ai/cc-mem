#!/bin/bash
# UserPromptSubmit Hook - Capture previous conversation when user submits prompt
# Called by Claude Code hooks system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"
source "$PLUGIN_DIR/lib/hook_utils.sh"
echo "[user-prompt-submit] $(date): START" >> "$CCMEM_DEBUG_LOG"

# 从 stdin 读取 hook 输入（JSON 格式）- 可能为空
INPUT=$(cat)
hook_log "user-prompt-submit" "INPUT length=${#INPUT}"
SESSION_ID=$(resolve_hook_session_id "user-prompt-submit" "$INPUT")
PROJECT_PATH=$(resolve_hook_project_path "user-prompt-submit" "$INPUT")

# 获取安全的日志路径
LOG_FILE=$(get_operation_log_path "$SESSION_ID")

# 确保日志文件存在并设置安全权限
create_operation_log "$LOG_FILE"

USER_PROMPT=""
if [ -n "$INPUT" ] && [ "$INPUT" != "" ]; then
    USER_PROMPT=$(echo "$INPUT" | jq -r '
        .prompt // .user_prompt // .text // .query //
        (if (.message? | type) == "string" then .message
         elif (.message.content? | type) == "string" then .message.content
         elif (.message.content? | type) == "array" then ([.message.content[]? | select(.type == "text") | .text] | join(" "))
         else empty end) // empty
    ' 2>/dev/null)
fi
hook_log "user-prompt-submit" "USER_PROMPT length=${#USER_PROMPT}"

if [ -n "$USER_PROMPT" ]; then
    prompt_summary=""
    prompt_summary=$(build_reusable_prompt_summary "$USER_PROMPT")
    if [ -n "$prompt_summary" ]; then
        prompt_classification_result=""
        prompt_classification_result=$(hook_classify_memory "user-prompt-submit" "user_prompt_submit" "$USER_PROMPT" "$USER_PROMPT" "user-prompt,reusable" "user-preference")
        PROMPT_CATEGORY=$(printf "%s\n" "$prompt_classification_result" | cut -d'|' -f1)
        PROMPT_CONFIDENCE=$(printf "%s\n" "$prompt_classification_result" | cut -d'|' -f2)
        PROMPT_REASON=$(printf "%s\n" "$prompt_classification_result" | cut -d'|' -f3-)

        if [ "$PROMPT_CATEGORY" != "context" ] && [ "${PROMPT_CONFIDENCE:-0}" -ge 70 ]; then
            prompt_policy_result=$(hook_classification_policy "user-prompt-submit" "user_prompt_submit" "$PROMPT_CATEGORY" "$PROMPT_CONFIDENCE")
            PROMPT_MEMORY_KIND=$(printf "%s\n" "$prompt_policy_result" | cut -d'|' -f1)
            PROMPT_AUTO_INJECT_POLICY=$(printf "%s\n" "$prompt_policy_result" | cut -d'|' -f2)

            if printf "%s" "$USER_PROMPT" | "$CLI" capture \
                -p "$PROJECT_PATH" \
                -c "$PROMPT_CATEGORY" \
                -s "$SESSION_ID" \
                -t "auto-captured,user-prompt,reusable" \
                -m "$prompt_summary" \
                --concepts "user-preference" \
                --source "user_prompt_submit" \
                --memory-kind "$PROMPT_MEMORY_KIND" \
                --inject-policy "$PROMPT_AUTO_INJECT_POLICY" \
                --classification-confidence "$PROMPT_CONFIDENCE" \
                --classification-reason "$PROMPT_REASON" \
                --classification-source "rule" \
                --classification-version "$CLASSIFICATION_RULE_VERSION" \
                >/dev/null 2>&1; then
                hook_log "user-prompt-submit" "Reusable prompt saved"
            else
                reusable_prompt_queue=""
                reusable_prompt_queue=$(queue_failed_capture_content "user-prompt-submit" "$SESSION_ID" "$USER_PROMPT" "reusable_prompt_capture_failed" "$PROJECT_PATH" "$(resolve_hook_project_root "user-prompt-submit" "$PROJECT_PATH")" "user_prompt_submit" "auto-captured,user-prompt,reusable" "user-preference" "$prompt_summary" || true)
                if [ -n "$reusable_prompt_queue" ]; then
                    hook_log "user-prompt-submit" "Reusable prompt capture failed, queued at: $reusable_prompt_queue"
                else
                    hook_log "user-prompt-submit" "Reusable prompt capture failed and queue fallback failed"
                fi
            fi
        else
            hook_log "user-prompt-submit" "Prompt ignored as non-reusable: category=$PROMPT_CATEGORY confidence=$PROMPT_CONFIDENCE"
        fi
    else
        hook_log "user-prompt-submit" "Prompt ignored as ephemeral"
    fi
fi

# 检查是否有累积的日志
hook_log "user-prompt-submit" "Checking LOG_FILE=$LOG_FILE"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    CONTENT=$(cat "$LOG_FILE")
    hook_log "user-prompt-submit" "Log file exists with content, lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0"), length=${#CONTENT}"

    classification_result=""
    classification_result=$(hook_classify_memory "user-prompt-submit" "user_prompt_submit" "" "$CONTENT" "auto-captured" "what-changed")
    CATEGORY=$(printf "%s\n" "$classification_result" | cut -d'|' -f1)
    CLASSIFICATION_CONFIDENCE=$(printf "%s\n" "$classification_result" | cut -d'|' -f2)
    CLASSIFICATION_REASON=$(printf "%s\n" "$classification_result" | cut -d'|' -f3-)
    policy_result=$(hook_classification_policy "user-prompt-submit" "user_prompt_submit" "$CATEGORY" "$CLASSIFICATION_CONFIDENCE")
    MEMORY_KIND=$(printf "%s\n" "$policy_result" | cut -d'|' -f1)
    AUTO_INJECT_POLICY=$(printf "%s\n" "$policy_result" | cut -d'|' -f2)

    # 标签提取
    TAGS="auto-captured"

    # 捕获记忆
    if echo "$CONTENT" | "$CLI" capture \
        -p "$PROJECT_PATH" \
        -c "$CATEGORY" \
        -s "$SESSION_ID" \
        -t "$TAGS" \
        --source "user_prompt_submit" \
        --memory-kind "$MEMORY_KIND" \
        --inject-policy "$AUTO_INJECT_POLICY" \
        --classification-confidence "$CLASSIFICATION_CONFIDENCE" \
        --classification-reason "$CLASSIFICATION_REASON" \
        --classification-source "rule" \
        --classification-version "$CLASSIFICATION_RULE_VERSION" \
        >/dev/null 2>&1; then
        > "$LOG_FILE"
        hook_log "user-prompt-submit" "Memory saved"
    else
        queued_path=""
        queued_path=$(queue_failed_capture_log "user-prompt-submit" "$SESSION_ID" "$LOG_FILE" "capture_failed" "$PROJECT_PATH" "$(resolve_hook_project_root "user-prompt-submit" "$PROJECT_PATH")" || true)
        if [ -n "$queued_path" ]; then
            hook_log "user-prompt-submit" "Capture failed, buffered log moved to queue: $queued_path"
        else
            hook_log "user-prompt-submit" "Capture failed and queue fallback failed, keeping buffered log"
        fi
    fi
else
    hook_log "user-prompt-submit" "No log file or empty"
fi

if [ -n "$USER_PROMPT" ] && [ -f "$PLUGIN_DIR/lib/sqlite.sh" ]; then
    load_sqlite_runtime "user-prompt-submit" "$PLUGIN_DIR" >/dev/null 2>&1 || true
    PROJECT_ROOT=$(resolve_hook_project_root "user-prompt-submit" "$PROJECT_PATH")
    related_preview=$(related_projects_preview "$PROJECT_ROOT")
    hook_log "user-prompt-submit" "RELATED_PROJECTS=${related_preview:-none}"
    recall_context=$(generate_query_recall_context "$PROJECT_PATH" "$USER_PROMPT" "$(get_injection_recall_limit)" 2>/dev/null || true)
    if [ -n "$recall_context" ]; then
        recall_items=""
        recall_items=$(printf "%s\n" "$recall_context" | grep -c '^- \[' 2>/dev/null || echo "0")
        hook_log "user-prompt-submit" "Recall generated, items=$recall_items, length=${#recall_context}"
        echo "$recall_context"
    else
        hook_log "user-prompt-submit" "Recall skipped or empty for current prompt"
    fi
fi

exit 0
