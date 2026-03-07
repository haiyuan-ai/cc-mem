#!/bin/bash
# Session Start Hook - 会话启动时注入记忆
# 由 Claude Code hooks 系统调用

# 调试日志文件
DEBUG_LOG="/tmp/ccmem_debug.log"
echo "[session-start] $(date): START" >> "$DEBUG_LOG"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"
source "$PLUGIN_DIR/lib/hook_utils.sh"

# 从 stdin 读取 hook 输入（JSON 格式）
INPUT=$(cat)
hook_log "session-start" "INPUT length=${#INPUT}"
hook_log "session-start" "PID=$$ PPID=$PPID"

SESSION_ID=$(resolve_hook_session_id "session-start" "$INPUT")
PROJECT_PATH=$(resolve_hook_project_path "session-start" "$INPUT")

# 静默初始化（如果数据库不存在）
load_sqlite_runtime "session-start" "$PLUGIN_DIR" >/dev/null 2>&1 || true
PROJECT_ROOT=$(resolve_hook_project_root "session-start" "$PROJECT_PATH")

# 记录会话开始
if command -v upsert_session &> /dev/null; then
    upsert_session "$SESSION_ID" "$PROJECT_PATH" "$PROJECT_ROOT"
    hook_log "session-start" "Session upserted with project_root=$PROJECT_ROOT"
fi

# 更新项目访问
if command -v update_project_access &> /dev/null; then
    update_project_access "$PROJECT_PATH" "$(basename "$PROJECT_PATH")" ""
fi

# 注入相关记忆（输出到 stdout，会被 Claude Code 读取）
if [ -f "$CLI" ]; then
    related_preview=$(related_projects_preview "$PROJECT_ROOT")
    hook_log "session-start" "RELATED_PROJECTS=${related_preview:-none}"
    "$CLI" inject-context -p "$PROJECT_PATH" -l 3 2>/dev/null || true
    hook_log "session-start" "inject-context invoked for project_root=$PROJECT_ROOT"
fi
