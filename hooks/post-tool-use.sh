#!/bin/bash
# PostToolUse Hook - 工具使用后捕获观察记录
# 由 Claude Code hooks 系统调用

# 调试日志文件
DEBUG_LOG="/tmp/ccmem_debug.log"
echo "[post-tool-use] $(date): START" >> "$DEBUG_LOG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 从 stdin 读取 hook 输入（JSON 格式）
# Claude Code 的 command hook 可能不传递 stdin
INPUT=$(cat)
echo "[post-tool-use] $(date): INPUT length=${#INPUT}" >> "$DEBUG_LOG"

# 记录所有可用的环境变量（调试用）
echo "[post-tool-use] $(date): CLAUDE_CODE_ENTRYPOINT=$CLAUDE_CODE_ENTRYPOINT" >> "$DEBUG_LOG"
echo "[post-tool-use] $(date): PID=$$ PPID=$PPID" >> "$DEBUG_LOG"

# 解析工具类型 - 从 stdin JSON 或环境变量获取
TOOL_TYPE=""
TOOL_NAME=""

if [ -n "$INPUT" ] && [ "$INPUT" != "" ]; then
    TOOL_TYPE=$(echo "$INPUT" | jq -r '.tool_type // empty' 2>/dev/null || echo "")
    TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
    echo "[post-tool-use] $(date): From stdin - TOOL_TYPE=$TOOL_TYPE, TOOL_NAME=$TOOL_NAME" >> "$DEBUG_LOG"
fi

# 如果没有工具类型，尝试从 tool_input 推断
if [ -z "$TOOL_TYPE" ]; then
    TOOL_TYPE=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
fi
echo "[post-tool-use] $(date): Final TOOL_TYPE=$TOOL_TYPE" >> "$DEBUG_LOG"

# 只捕获关键工具
case "$TOOL_TYPE" in
    "Edit"|"Write"|"Bash"|"Bash (sudo)")
        # 继续处理
        ;;
    *)
        echo "[post-tool-use] $(date): Skipping non-tracked tool: $TOOL_TYPE" >> "$DEBUG_LOG"
        exit 0
        ;;
esac

# 获取会话信息 - 从 stdin JSON 解析 session_id
SESSION_ID=""
if [ -n "$INPUT" ] && [ "$INPUT" != "" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    echo "[post-tool-use] $(date): session_id from stdin = $SESSION_ID" >> "$DEBUG_LOG"
fi

# 回退到环境变量或 PID
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
    echo "[post-tool-use] $(date): using fallback SESSION_ID=$SESSION_ID" >> "$DEBUG_LOG"
fi

# 获取项目路径
PROJECT_PATH="${PWD}"
echo "[post-tool-use] $(date): PROJECT_PATH=$PROJECT_PATH" >> "$DEBUG_LOG"

# 提取关键信息
# 如果 INPUT 为空，尝试从其他来源获取工具信息
if [ -z "$INPUT" ] || [ "$INPUT" = "" ]; then
    echo "[post-tool-use] $(date): WARNING - stdin is empty, cannot get tool details" >> "$DEBUG_LOG"
    # 记录一个通用的工具调用记录
    echo "[TOOL_CALL] unknown tool" >> "/tmp/ccmem_${SESSION_ID}.log"
    echo "[post-tool-use] $(date): Logged generic tool call" >> "$DEBUG_LOG"
else
    case "$TOOL_TYPE" in
        "Edit"|"Write")
            FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
            DESCRIPTION=$(echo "$INPUT" | jq -r '.tool_input.description // empty' 2>/dev/null || echo "")

            if [ -n "$FILE_PATH" ]; then
                # 累积文件更改记录
                echo "[FILE_CHANGE] $FILE_PATH: $DESCRIPTION" >> "/tmp/ccmem_${SESSION_ID}.log"
                echo "[post-tool-use] $(date): Logged FILE_CHANGE: $FILE_PATH" >> "$DEBUG_LOG"
            fi
            ;;
        "Bash"|"Bash (sudo)")
            COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")
            DESCRIPTION=$(echo "$INPUT" | jq -r '.tool_input.description // empty' 2>/dev/null || echo "")

            if [ -n "$COMMAND" ]; then
                # 累积命令执行记录
                echo "[BASH] $COMMAND: $DESCRIPTION" >> "/tmp/ccmem_${SESSION_ID}.log"
                echo "[post-tool-use] $(date): Logged BASH: $COMMAND" >> "$DEBUG_LOG"
            fi
            ;;
    esac
fi

# 每 3 次操作保存一次（通过计数实现）
LOG_FILE="/tmp/ccmem_${SESSION_ID}.log"
if [ -f "$LOG_FILE" ]; then
    LINE_COUNT=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")

    # 达到阈值时批量保存
    if [ "$LINE_COUNT" -ge 3 ]; then
        CONTENT=$(cat "$LOG_FILE")
        echo "[post-tool-use] $(date): Threshold reached, saving memory" >> "$DEBUG_LOG"

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

echo "[post-tool-use] $(date): END" >> "$DEBUG_LOG"
exit 0
