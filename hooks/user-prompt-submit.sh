#!/bin/bash
# UserPromptSubmit Hook - 用户提交提示时捕获上一轮对话记忆
# 由 Claude Code hooks 系统调用

# 调试日志文件
DEBUG_LOG="/tmp/ccmem_debug.log"
echo "[user-prompt-submit] $(date): START" >> "$DEBUG_LOG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"
source "$PLUGIN_DIR/lib/hook_utils.sh"

# 从 stdin 读取 hook 输入（JSON 格式）- 可能为空
INPUT=$(cat)
hook_log "user-prompt-submit" "INPUT length=${#INPUT}"
SESSION_ID=$(resolve_hook_session_id "user-prompt-submit" "$INPUT")
PROJECT_PATH=$(resolve_hook_project_path "user-prompt-submit" "$INPUT")

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

# 检查是否有累积的日志
LOG_FILE="/tmp/ccmem_${SESSION_ID}.log"
hook_log "user-prompt-submit" "Checking LOG_FILE=$LOG_FILE"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    CONTENT=$(cat "$LOG_FILE")
    hook_log "user-prompt-submit" "Log file exists with content, lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0"), length=${#CONTENT}"

    classification_result=""
    classification_result=$(hook_classify_memory "user-prompt-submit" "user_prompt_submit" "" "$CONTENT" "auto-captured" "what-changed")
    CATEGORY=$(printf "%s\n" "$classification_result" | cut -d'|' -f1)
    CLASSIFICATION_CONFIDENCE=$(printf "%s\n" "$classification_result" | cut -d'|' -f2)
    policy_result=$(hook_classification_policy "user-prompt-submit" "user_prompt_submit" "$CATEGORY" "$CLASSIFICATION_CONFIDENCE")
    MEMORY_KIND=$(printf "%s\n" "$policy_result" | cut -d'|' -f1)
    AUTO_INJECT_POLICY=$(printf "%s\n" "$policy_result" | cut -d'|' -f2)

    # 标签提取
    TAGS="auto-captured"

    # 捕获记忆
    echo "$CONTENT" | "$CLI" capture \
        -p "$PROJECT_PATH" \
        -c "$CATEGORY" \
        -s "$SESSION_ID" \
        -t "$TAGS" \
        --source "user_prompt_submit" \
        --memory-kind "$MEMORY_KIND" \
        --inject-policy "$AUTO_INJECT_POLICY" \
        >/dev/null 2>&1 || true

    # 清空日志
    > "$LOG_FILE"
    hook_log "user-prompt-submit" "Memory saved"
else
    hook_log "user-prompt-submit" "No log file or empty"
fi

if [ -n "$USER_PROMPT" ] && [ -f "$PLUGIN_DIR/lib/sqlite.sh" ]; then
    load_sqlite_runtime "user-prompt-submit" "$PLUGIN_DIR" >/dev/null 2>&1 || true
    PROJECT_ROOT=$(resolve_hook_project_root "user-prompt-submit" "$PROJECT_PATH")
    related_preview=$(related_projects_preview "$PROJECT_ROOT")
    hook_log "user-prompt-submit" "RELATED_PROJECTS=${related_preview:-none}"
    recall_context=$(generate_query_recall_context "$PROJECT_PATH" "$USER_PROMPT" 3 2>/dev/null || true)
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
