#!/bin/bash
# Session End Hook - 会话结束时捕获记忆
# 由 Claude Code hooks 系统调用

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 获取会话信息
SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
PROJECT_PATH="${PWD}"

# 从环境变量获取会话摘要（如果可用）
SESSION_SUMMARY="${CLAUDE_SESSION_SUMMARY:-}"
MESSAGE_COUNT="${CLAUDE_MESSAGE_COUNT:-0}"

# 加载 SQLite 函数库
source "$PLUGIN_DIR/lib/sqlite.sh"

# 结束会话记录
end_session "$SESSION_ID" "$MESSAGE_COUNT" "$SESSION_SUMMARY"

# 自动捕获会话记忆
if [ -f "$CLI" ]; then
    # 如果有会话历史文件，读取并捕获
    if [ -n "$SESSION_HISTORY_FILE" ] && [ -f "$SESSION_HISTORY_FILE" ]; then
        # 提取关键内容（简化版，实际可以更复杂）
        content=$(tail -100 "$SESSION_HISTORY_FILE" 2>/dev/null || echo "")

        if [ -n "$content" ]; then
            # 分类记忆（简化逻辑）
            category="context"
            if echo "$content" | grep -qi "error\|fix\|debug"; then
                category="debug"
            elif echo "$content" | grep -qi "solution\|resolve\|workaround"; then
                category="solution"
            elif echo "$content" | grep -qi "decision\|choose\|select"; then
                category="decision"
            fi

            # 捕获记忆
            echo "$content" | "$CLI" capture \
                -p "$PROJECT_PATH" \
                -c "$category" \
                -s "$SESSION_ID" \
                2>/dev/null || true
        fi
    fi
fi

echo "[CC-Mem] 会话记忆已保存：$SESSION_ID"
