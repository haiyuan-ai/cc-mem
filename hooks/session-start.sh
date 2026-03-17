#!/bin/bash
# Session Start Hook - Inject memory when session starts
# Called by Claude Code hooks system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"
source "$PLUGIN_DIR/lib/hook_utils.sh"
echo "[session-start] $(date): START" >> "$CCMEM_DEBUG_LOG"

# Read hook input from stdin (JSON format)
INPUT=$(cat)
hook_log "session-start" "INPUT length=${#INPUT}"
hook_log "session-start" "PID=$$ PPID=$PPID"

SESSION_ID=$(resolve_hook_session_id "session-start" "$INPUT")
PROJECT_PATH=$(resolve_hook_project_path "session-start" "$INPUT")

# Silent initialization (if database doesn't exist)
load_sqlite_runtime "session-start" "$PLUGIN_DIR" >/dev/null 2>&1 || true
PROJECT_ROOT=$(resolve_hook_project_root "session-start" "$PROJECT_PATH")

# Record session start
if command -v upsert_session &> /dev/null; then
    upsert_session "$SESSION_ID" "$PROJECT_PATH" "$PROJECT_ROOT"
    hook_log "session-start" "Session upserted with project_root=$PROJECT_ROOT"
fi

# Update project access
if command -v update_project_access &> /dev/null; then
    update_project_access "$PROJECT_PATH" "$(basename "$PROJECT_PATH")" ""
fi

# Inject related memories (output to stdout, will be read by Claude Code)
if [ -f "$CLI" ]; then
    related_preview=$(related_projects_preview "$PROJECT_ROOT")
    hook_log "session-start" "RELATED_PROJECTS=${related_preview:-none}"
    "$CLI" inject-context -p "$PROJECT_PATH" -l "$(get_injection_session_start_limit)" 2>/dev/null || true
    hook_log "session-start" "inject-context invoked for project_root=$PROJECT_ROOT"
fi
