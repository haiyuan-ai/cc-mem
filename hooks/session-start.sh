#!/bin/bash
# Session Start Hook - 会话启动时注入记忆
# 由 Claude Code hooks 系统调用

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 获取会话信息
SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
PROJECT_PATH="${PWD}"

# 静默初始化（如果数据库不存在）
source "$PLUGIN_DIR/lib/sqlite.sh" 2>/dev/null || true

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
    memories=$("$CLI" retrieve -p "$PROJECT_PATH" -l 5 2>/dev/null || true)
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
