#!/bin/bash
# Session Start Hook - 会话启动时注入记忆
# 由 Claude Code hooks 系统调用

# 调试日志文件
DEBUG_LOG="/tmp/ccmem_debug.log"
echo "[session-start] $(date): START" >> "$DEBUG_LOG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 从 stdin 读取 hook 输入（JSON 格式）
INPUT=$(cat)
echo "[session-start] $(date): INPUT length=${#INPUT}" >> "$DEBUG_LOG"
echo "[session-start] $(date): PID=$$ PPID=$PPID" >> "$DEBUG_LOG"

# 从 stdin JSON 中解析 session_id
SESSION_ID=""
if [ -n "$INPUT" ] && [ "$INPUT" != "" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    echo "[session-start] $(date): session_id from stdin = $SESSION_ID" >> "$DEBUG_LOG"
fi

# 回退到环境变量或 PID
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
    echo "[session-start] $(date): using fallback SESSION_ID=$SESSION_ID" >> "$DEBUG_LOG"
fi

# 获取项目路径
PROJECT_PATH="${PWD}"
echo "[session-start] $(date): PROJECT_PATH=$PROJECT_PATH" >> "$DEBUG_LOG"

# 获取项目路径
PROJECT_PATH=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [ -z "$PROJECT_PATH" ]; then
    PROJECT_PATH="${PWD}"
fi
echo "[session-start] $(date): PROJECT_PATH=$PROJECT_PATH" >> "$DEBUG_LOG"

# 静默初始化（如果数据库不存在）
if [ -f "$PLUGIN_DIR/lib/sqlite.sh" ]; then
    source "$PLUGIN_DIR/lib/sqlite.sh" 2>/dev/null || true
    echo "[session-start] $(date): Loaded sqlite.sh" >> "$DEBUG_LOG"
else
    echo "[session-start] $(date): WARNING - sqlite.sh not found" >> "$DEBUG_LOG"
fi

# 记录会话开始
if command -v upsert_session &> /dev/null; then
    upsert_session "$SESSION_ID" "$PROJECT_PATH"
fi

# 更新项目访问
if command -v update_project_access &> /dev/null; then
    update_project_access "$PROJECT_PATH" "$(basename "$PROJECT_PATH")" ""
fi

# 注入相关记忆（输出到 stdout，会被 Claude Code 读取）
echo "=== CC-Mem: 加载项目记忆 ==="

# 基于项目路径检索记忆
if [ -f "$CLI" ]; then
    memories=$("$CLI" search -p "$PROJECT_PATH" -l 5 2>/dev/null || true)
    if [ -n "$memories" ]; then
        echo ""
        echo "找到以下相关记忆："
        echo "$memories"
        echo ""
    fi
fi

# 输出会话信息
echo "会话 ID: $SESSION_ID"
echo "项目路径：$PROJECT_PATH"
echo "================================"
