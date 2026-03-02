#!/bin/bash
# UserPromptSubmit Hook - 用户提交提示时捕获上一轮对话记忆
# 由 Claude Code hooks 系统调用

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 获取会话信息
SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
PROJECT_PATH="${PWD}"

# 检查是否有累积的日志
LOG_FILE="/tmp/ccmem_${SESSION_ID}.log"

if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
    CONTENT=$(cat "$LOG_FILE")

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
fi

exit 0
