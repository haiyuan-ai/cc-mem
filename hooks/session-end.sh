#!/bin/bash
# Session End Hook - 会话结束时捕获记忆
# 由 Claude Code hooks 系统调用

# 不设置 set -e，允许脚本继续执行即使部分命令失败

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

source "$PLUGIN_DIR/lib/hook_utils.sh"
echo "[session-end] $(date): START" >> "$CCMEM_DEBUG_LOG"

# 从 stdin 读取 hook 输入（JSON 格式）
# Claude Code 的 command hook 会传递 stdin JSON
INPUT=$(cat)
hook_log "session-end" "INPUT length=${#INPUT}"
SESSION_ID=$(resolve_hook_session_id "session-end" "$INPUT")
PROJECT_PATH=$(resolve_hook_project_path "session-end" "$INPUT")

# 从环境变量获取会话摘要（如果可用）
SESSION_SUMMARY="${CLAUDE_SESSION_SUMMARY:-}"
MESSAGE_COUNT="${CLAUDE_MESSAGE_COUNT:-0}"

if ! load_sqlite_runtime "session-end" "$PLUGIN_DIR"; then
    exit 1
fi

PROJECT_ROOT=$(resolve_hook_project_root "session-end" "$PROJECT_PATH")

# 结束会话记录
end_session "$SESSION_ID" "$MESSAGE_COUNT" "$SESSION_SUMMARY"
hook_log "session-end" "Updated session record"

# 自动捕获会话记忆
if [ -f "$CLI" ]; then
    # 检查工具使用日志文件（由 post-tool-use.sh 创建）
    LOG_FILE="/tmp/ccmem_${SESSION_ID}.log"
    hook_log "session-end" "Checking LOG_FILE=$LOG_FILE"

    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        CONTENT=$(cat "$LOG_FILE")
        hook_log "session-end" "LOG_FILE content exists, lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0"), length=${#CONTENT}"

        if [ -n "$CONTENT" ]; then
            if should_condense_operation_log "$CONTENT"; then
                CONTENT=$(summarize_operation_log "$CONTENT")
                hook_log "session-end" "Condensed long operation log before capture"
            fi

            classification_result=""
            classification_result=$(hook_classify_memory "session-end" "session_end" "" "$CONTENT" "session-end,auto-captured" "what-changed")
            CATEGORY=$(printf "%s\n" "$classification_result" | cut -d'|' -f1)
            CLASSIFICATION_CONFIDENCE=$(printf "%s\n" "$classification_result" | cut -d'|' -f2)
            CLASSIFICATION_REASON=$(printf "%s\n" "$classification_result" | cut -d'|' -f3-)
            policy_result=$(hook_classification_policy "session-end" "session_end" "$CATEGORY" "$CLASSIFICATION_CONFIDENCE")
            MEMORY_KIND=$(printf "%s\n" "$policy_result" | cut -d'|' -f1)
            AUTO_INJECT_POLICY=$(printf "%s\n" "$policy_result" | cut -d'|' -f2)

            # 捕获记忆
            if echo "$CONTENT" | "$CLI" capture \
                -p "$PROJECT_PATH" \
                -c "$CATEGORY" \
                -s "$SESSION_ID" \
                -t "session-end,auto-captured" \
                --source "session_end" \
                --memory-kind "$MEMORY_KIND" \
                --inject-policy "$AUTO_INJECT_POLICY" \
                --classification-confidence "$CLASSIFICATION_CONFIDENCE" \
                --classification-reason "$CLASSIFICATION_REASON" \
                --classification-source "rule" \
                --classification-version "$CLASSIFICATION_RULE_VERSION" \
                --concepts "what-changed" \
                2>/dev/null; then
                > "$LOG_FILE"
                hook_log "session-end" "Buffered log cleared after session-end capture"
                echo "[CC-Mem] 已保存会话记忆：$SESSION_ID"
                hook_log "session-end" "Memory saved"
            else
                queued_path=""
                queued_path=$(queue_failed_capture_log "session-end" "$SESSION_ID" "$LOG_FILE" "capture_failed" || true)
                if [ -n "$queued_path" ]; then
                    hook_log "session-end" "Capture failed, buffered log moved to queue: $queued_path"
                else
                    hook_log "session-end" "Capture failed and queue fallback failed, keeping buffered log"
                fi
                echo "[CC-Mem] 会话记忆保存失败，已入队待重试：$SESSION_ID"
            fi
        fi
    else
        echo "[CC-Mem] 会话结束，无待保存记忆：$SESSION_ID"
        hook_log "session-end" "No log file or empty"
    fi
else
    hook_log "session-end" "CLI not found at $CLI"
fi

run_opportunistic_cleanup "session-end" 30 50 "$(get_cleanup_throttle_seconds)" "$PROJECT_PATH" || true

echo "[CC-Mem] 会话已结束：$SESSION_ID"
hook_log "session-end" "END"
