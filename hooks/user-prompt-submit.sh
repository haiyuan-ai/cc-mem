#!/bin/bash
# UserPromptSubmit Hook - 用户提交提示时捕获上一轮对话记忆
# 由 Claude Code hooks 系统调用

# 调试日志文件
DEBUG_LOG="/tmp/ccmem_debug.log"
echo "[user-prompt-submit] $(date): START" >> "$DEBUG_LOG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 从 stdin 读取 hook 输入（JSON 格式）- 可能为空
INPUT=$(cat)
echo "[user-prompt-submit] $(date): INPUT length=${#INPUT}" >> "$DEBUG_LOG"

# 从 stdin JSON 中解析 session_id
SESSION_ID=""
if [ -n "$INPUT" ] && [ "$INPUT" != "" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    echo "[user-prompt-submit] $(date): session_id from stdin = $SESSION_ID" >> "$DEBUG_LOG"
fi

# 回退到环境变量或 PID
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
    echo "[user-prompt-submit] $(date): using fallback SESSION_ID=$SESSION_ID" >> "$DEBUG_LOG"
fi

# 获取项目路径
PROJECT_PATH="${PWD}"
echo "[user-prompt-submit] $(date): PROJECT_PATH=$PROJECT_PATH" >> "$DEBUG_LOG"

# 检查是否有累积的日志
LOG_FILE="/tmp/ccmem_${SESSION_ID}.log"
echo "[user-prompt-submit] $(date): Checking LOG_FILE=$LOG_FILE" >> "$DEBUG_LOG"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    CONTENT=$(cat "$LOG_FILE")
    echo "[user-prompt-submit] $(date): Log file exists with content" >> "$DEBUG_LOG"

    # 确定类别
    CATEGORY="context"
    if echo "$CONTENT" | grep -qi "error\|fix\|debug\|fail\|crash"; then
        CATEGORY="debug"
    elif echo "$CONTENT" | grep -qi "solution\|resolve\|workaround\|implemented\|created"; then
        CATEGORY="solution"
    elif echo "$CONTENT" | grep -qi "decision\|choose\|select\|decided"; then
        CATEGORY="decision"
    fi

    # 标签提取
    TAGS="auto-captured"

    # 捕获记忆
    echo "$CONTENT" | "$CLI" capture \
        -p "$PROJECT_PATH" \
        -c "$CATEGORY" \
        -s "$SESSION_ID" \
        -t "$TAGS" \
        2>/dev/null || true

    # 清空日志
    > "$LOG_FILE"

    echo "[CC-Mem] 已保存会话记忆"
    echo "[user-prompt-submit] $(date): Memory saved" >> "$DEBUG_LOG"
else
    echo "[user-prompt-submit] $(date): No log file or empty" >> "$DEBUG_LOG"
fi

exit 0
