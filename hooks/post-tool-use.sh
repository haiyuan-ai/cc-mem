#!/bin/bash
# PostToolUse Hook - Capture observation after tool use
# Called by Claude Code hooks system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"
source "$PLUGIN_DIR/lib/hook_utils.sh"
echo "[post-tool-use] $(date): START" >> "$CCMEM_DEBUG_LOG"

# 从 stdin 读取 hook 输入（JSON 格式）
# Claude Code 的 command hook 可能不传递 stdin
INPUT=$(cat)
hook_log "post-tool-use" "INPUT length=${#INPUT}"

# 记录所有可用的环境变量（调试用）
hook_log "post-tool-use" "CLAUDE_CODE_ENTRYPOINT=$CLAUDE_CODE_ENTRYPOINT"
hook_log "post-tool-use" "PID=$$ PPID=$PPID"

# 解析工具类型 - 从 stdin JSON 或环境变量获取
TOOL_TYPE=""
TOOL_NAME=""

if [ -n "$INPUT" ] && [ "$INPUT" != "" ]; then
    TOOL_TYPE=$(hook_json_get "$INPUT" '.tool_type // empty')
    TOOL_NAME=$(hook_json_get "$INPUT" '.tool_name // empty')
    hook_log "post-tool-use" "From stdin - TOOL_TYPE=$TOOL_TYPE, TOOL_NAME=$TOOL_NAME"
fi

# 如果没有工具类型，尝试从 tool_input 推断
if [ -z "$TOOL_TYPE" ]; then
    TOOL_TYPE=$(hook_json_get "$INPUT" '.tool_name // empty')
fi
hook_log "post-tool-use" "Final TOOL_TYPE=$TOOL_TYPE"

# 只捕获关键工具
case "$TOOL_TYPE" in
    "Edit"|"Write"|"Bash"|"Bash (sudo)")
        # 继续处理
        ;;
    *)
        hook_log "post-tool-use" "Skipping non-tracked tool: $TOOL_TYPE"
        exit 0
        ;;
esac

# 获取会话信息 - 从 stdin JSON 解析 session_id
SESSION_ID=$(resolve_hook_session_id "post-tool-use" "$INPUT")

# 获取安全的日志路径
LOG_FILE=$(get_operation_log_path "$SESSION_ID")

# 确保日志文件存在并设置安全权限
create_operation_log "$LOG_FILE"

# 获取项目路径
PROJECT_PATH=$(resolve_hook_project_path "post-tool-use" "$INPUT")

# 提取关键信息
# 如果 INPUT 为空，尝试从其他来源获取工具信息
if [ -z "$INPUT" ] || [ "$INPUT" = "" ]; then
    hook_log "post-tool-use" "WARNING - stdin is empty, cannot get tool details"
    # 记录一个通用的工具调用记录
    echo "[TOOL_CALL] unknown tool" >> "$LOG_FILE"
    hook_log "post-tool-use" "Logged generic tool call"
else
    case "$TOOL_TYPE" in
        "Edit"|"Write")
            FILE_PATH=$(hook_json_get "$INPUT" '.tool_input.file_path // empty')
            DESCRIPTION=$(hook_json_get "$INPUT" '.tool_input.description // empty')

            if [ -n "$FILE_PATH" ]; then
                # 累积文件更改记录
                echo "[FILE_CHANGE] $FILE_PATH: $DESCRIPTION" >> "$LOG_FILE"
                hook_log "post-tool-use" "Logged FILE_CHANGE: $FILE_PATH"
            fi
            ;;
        "Bash"|"Bash (sudo)")
            COMMAND=$(hook_json_get "$INPUT" '.tool_input.command // empty')
            DESCRIPTION=$(hook_json_get "$INPUT" '.tool_input.description // empty')

            if [ -n "$COMMAND" ]; then
                # 累积命令执行记录
                echo "[BASH] $COMMAND: $DESCRIPTION" >> "$LOG_FILE"
                hook_log "post-tool-use" "Logged BASH: $COMMAND"
            fi
            ;;
    esac
fi

# 每 3 次操作保存一次（通过计数实现）
if [ -f "$LOG_FILE" ]; then
    LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
    hook_log "post-tool-use" "LOG_FILE=$LOG_FILE line_count=$LINE_COUNT"

    # 达到阈值时批量保存
    if [ "$LINE_COUNT" -ge "$(get_post_tool_use_flush_lines)" ]; then
        CONTENT=$(cat "$LOG_FILE")
        hook_log "post-tool-use" "Threshold reached, saving memory"

        classification_result=""
        classification_result=$(hook_classify_memory "post-tool-use" "post_tool_use" "" "$CONTENT" "auto-captured" "what-changed")
        CATEGORY=$(printf "%s\n" "$classification_result" | cut -d'|' -f1)
        CLASSIFICATION_CONFIDENCE=$(printf "%s\n" "$classification_result" | cut -d'|' -f2)
        CLASSIFICATION_REASON=$(printf "%s\n" "$classification_result" | cut -d'|' -f3-)
        policy_result=$(hook_classification_policy "post-tool-use" "post_tool_use" "$CATEGORY" "$CLASSIFICATION_CONFIDENCE")
        MEMORY_KIND=$(printf "%s\n" "$policy_result" | cut -d'|' -f1)
        AUTO_INJECT_POLICY=$(printf "%s\n" "$policy_result" | cut -d'|' -f2)

        # 捕获记忆
        if echo "$CONTENT" | "$CLI" capture \
            -p "$PROJECT_PATH" \
            -c "$CATEGORY" \
            -s "$SESSION_ID" \
            --source "post_tool_use" \
            --memory-kind "$MEMORY_KIND" \
            --inject-policy "$AUTO_INJECT_POLICY" \
            --classification-confidence "$CLASSIFICATION_CONFIDENCE" \
            --classification-reason "$CLASSIFICATION_REASON" \
            --classification-source "rule" \
            --classification-version "$CLASSIFICATION_RULE_VERSION" \
            --concepts "what-changed" \
            2>/dev/null; then
            > "$LOG_FILE"
            hook_log "post-tool-use" "Buffered log cleared after capture"
        else
            queued_path=""
            queued_path=$(queue_failed_capture_log "post-tool-use" "$SESSION_ID" "$LOG_FILE" "capture_failed" "$PROJECT_PATH" "$(resolve_hook_project_root "post-tool-use" "$PROJECT_PATH")" || true)
            if [ -n "$queued_path" ]; then
                hook_log "post-tool-use" "Capture failed, buffered log moved to queue: $queued_path"
            else
                hook_log "post-tool-use" "Capture failed and queue fallback failed, keeping buffered log"
            fi
        fi
    fi
fi

hook_log "post-tool-use" "END"
exit 0
