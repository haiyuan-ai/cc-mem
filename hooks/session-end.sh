#!/bin/bash
# Session End Hook - 会话结束时捕获记忆
# 由 Claude Code hooks 系统调用

# 不设置 set -e，允许脚本继续执行即使部分命令失败

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 调试日志文件
DEBUG_LOG="/tmp/ccmem_debug.log"
echo "[session-end] $(date): START" >> "$DEBUG_LOG"

# 从 stdin 读取 hook 输入（JSON 格式）
# Claude Code 的 command hook 会传递 stdin JSON
INPUT=$(cat)
echo "[session-end] $(date): INPUT length=${#INPUT}" >> "$DEBUG_LOG"

# 从 stdin JSON 中解析 session_id
SESSION_ID=""
if [ -n "$INPUT" ] && [ "$INPUT" != "" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    echo "[session-end] $(date): session_id from stdin = $SESSION_ID" >> "$DEBUG_LOG"
fi

# 回退到环境变量或 PID
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
    echo "[session-end] $(date): using fallback SESSION_ID=$SESSION_ID" >> "$DEBUG_LOG"
fi

# 获取项目路径
PROJECT_PATH="${PWD}"
echo "[session-end] $(date): PROJECT_PATH=$PROJECT_PATH" >> "$DEBUG_LOG"

# 从环境变量获取会话摘要（如果可用）
SESSION_SUMMARY="${CLAUDE_SESSION_SUMMARY:-}"
MESSAGE_COUNT="${CLAUDE_MESSAGE_COUNT:-0}"

# 加载 SQLite 函数库
if [ -f "$PLUGIN_DIR/lib/sqlite.sh" ]; then
    source "$PLUGIN_DIR/lib/sqlite.sh"
    echo "[session-end] $(date): Loaded sqlite.sh" >> "$DEBUG_LOG"
else
    echo "[session-end] $(date): ERROR - sqlite.sh not found at $PLUGIN_DIR/lib/sqlite.sh" >> "$DEBUG_LOG"
    exit 1
fi

# 结束会话记录
end_session "$SESSION_ID" "$MESSAGE_COUNT" "$SESSION_SUMMARY"
echo "[session-end] $(date): Updated session record" >> "$DEBUG_LOG"

# 自动捕获会话记忆
if [ -f "$CLI" ]; then
    # 检查工具使用日志文件（由 post-tool-use.sh 创建）
    LOG_FILE="/tmp/ccmem_${SESSION_ID}.log"
    echo "[session-end] $(date): Checking LOG_FILE=$LOG_FILE" >> "$DEBUG_LOG"

    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        CONTENT=$(cat "$LOG_FILE")
        echo "[session-end] $(date): LOG_FILE content exists, capturing..." >> "$DEBUG_LOG"

        if [ -n "$CONTENT" ]; then
            if should_condense_operation_log "$CONTENT"; then
                CONTENT=$(summarize_operation_log "$CONTENT")
                echo "[session-end] $(date): Condensed long operation log before capture" >> "$DEBUG_LOG"
            fi

            # 确定类别
            CATEGORY="context"
            if echo "$CONTENT" | grep -qi "error\|fix\|debug\|fail"; then
                CATEGORY="debug"
            elif echo "$CONTENT" | grep -qi "solution\|resolve\|workaround"; then
                CATEGORY="solution"
            elif echo "$CONTENT" | grep -qi "decision\|choose\|select\|create\|add"; then
                CATEGORY="decision"
            fi

            # 捕获记忆
            echo "$CONTENT" | "$CLI" capture \
                -p "$PROJECT_PATH" \
                -c "$CATEGORY" \
                -s "$SESSION_ID" \
                -t "session-end,auto-captured" \
                --source "session_end" \
                --concepts "what-changed" \
                2>/dev/null || true

            # 清空日志
            > "$LOG_FILE"

            echo "[CC-Mem] 已保存会话记忆：$SESSION_ID"
            echo "[session-end] $(date): Memory saved" >> "$DEBUG_LOG"
        fi
    else
        echo "[CC-Mem] 会话结束，无待保存记忆：$SESSION_ID"
        echo "[session-end] $(date): No log file or empty" >> "$DEBUG_LOG"
    fi
else
    echo "[session-end] $(date): CLI not found at $CLI" >> "$DEBUG_LOG"
fi

echo "[CC-Mem] 会话已结束：$SESSION_ID"
echo "[session-end] $(date): END" >> "$DEBUG_LOG"
