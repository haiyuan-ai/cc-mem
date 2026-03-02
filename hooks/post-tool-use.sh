#!/bin/bash
# PostToolUse Hook - 工具使用后捕获观察记录
# 由 Claude Code hooks 系统调用

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 从 stdin 读取工具使用信息
if [ -t 0 ]; then
    # 非管道输入，跳过
    exit 0
fi

TOOL_DATA=$(cat)

# 解析工具类型
TOOL_TYPE=$(echo "$TOOL_DATA" | jq -r '.tool_type // empty' 2>/dev/null || echo "")
TOOL_NAME=$(echo "$TOOL_DATA" | jq -r '.tool_name // empty' 2>/dev/null || echo "")

# 只捕获关键工具
case "$TOOL_TYPE" in
    "Edit"|"Write"|"Bash")
        # 继续处理
        ;;
    *)
        exit 0
        ;;
esac

# 获取会话信息
SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
PROJECT_PATH="${PWD}"

# 提取关键信息
case "$TOOL_TYPE" in
    "Edit"|"Write")
        FILE_PATH=$(echo "$TOOL_DATA" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
        DESCRIPTION=$(echo "$TOOL_DATA" | jq -r '.tool_input.description // empty' 2>/dev/null || echo "")

        if [ -n "$FILE_PATH" ]; then
            # 累积文件更改记录
            echo "[FILE_CHANGE] $FILE_PATH: $DESCRIPTION" >> "/tmp/ccmem_${SESSION_ID}.log"
        fi
        ;;
    "Bash")
        COMMAND=$(echo "$TOOL_DATA" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
        DESCRIPTION=$(echo "$TOOL_DATA" | jq -r '.tool_input.description // empty' 2>/dev/null || echo "")

        if [ -n "$COMMAND" ]; then
            # 累积命令执行记录
            echo "[BASH] $COMMAND: $DESCRIPTION" >> "/tmp/ccmem_${SESSION_ID}.log"
        fi
        ;;
esac

# 每 5 次操作保存一次（通过计数实现）
LOG_FILE="/tmp/ccmem_${SESSION_ID}.log"
if [ -f "$LOG_FILE" ]; then
    LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")

    # 达到阈值时批量保存
    if [ "$LINE_COUNT" -ge 5 ]; then
        CONTENT=$(cat "$LOG_FILE")

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
            --concepts "what-changed" \
            2>/dev/null || true

        # 清空日志
        > "$LOG_FILE"
    fi
fi

exit 0
