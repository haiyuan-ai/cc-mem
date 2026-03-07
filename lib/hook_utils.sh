#!/bin/bash

HOOK_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_UTILS_DIR/classification.sh"
source "$HOOK_UTILS_DIR/memory_policy.sh"

hook_log() {
    local hook_name="$1"
    shift
    [ -z "${DEBUG_LOG:-}" ] && return 0
    echo "[$hook_name] $(date): $*" >> "$DEBUG_LOG"
}

hook_json_get() {
    local input="$1"
    local expr="$2"
    local fallback="${3:-}"
    local value=""

    if [ -z "$input" ] || ! command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$fallback"
        return
    fi

    value=$(printf '%s' "$input" | jq -r "$expr" 2>/dev/null || true)
    if [ -n "$value" ] && [ "$value" != "null" ]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

resolve_hook_session_id() {
    local hook_name="$1"
    local input="$2"
    local session_id=""

    session_id=$(hook_json_get "$input" '.session_id // empty')
    if [ -n "$session_id" ]; then
        hook_log "$hook_name" "session_id from stdin = $session_id"
        printf '%s\n' "$session_id"
        return
    fi

    session_id="${CLAUDE_SESSION_ID:-$$}"
    hook_log "$hook_name" "using fallback SESSION_ID=$session_id"
    printf '%s\n' "$session_id"
}

resolve_hook_project_path() {
    local hook_name="$1"
    local input="$2"
    local project_path=""

    project_path=$(hook_json_get "$input" '.cwd // empty' "$PWD")
    hook_log "$hook_name" "PROJECT_PATH=$project_path"
    printf '%s\n' "$project_path"
}

load_sqlite_runtime() {
    local hook_name="$1"
    local plugin_dir="$2"
    local sqlite_lib="$plugin_dir/lib/sqlite.sh"

    if [ -f "$sqlite_lib" ]; then
        # shellcheck source=/dev/null
        source "$sqlite_lib" 2>/dev/null || true
        hook_log "$hook_name" "Loaded sqlite.sh"
        return 0
    fi

    hook_log "$hook_name" "WARNING - sqlite.sh not found at $sqlite_lib"
    return 1
}

resolve_hook_project_root() {
    local hook_name="$1"
    local project_path="$2"
    local project_root="$project_path"

    if command -v resolve_project_root >/dev/null 2>&1; then
        project_root=$(resolve_project_root "$project_path")
    fi

    hook_log "$hook_name" "PROJECT_ROOT=$project_root"
    printf '%s\n' "$project_root"
}

related_projects_preview() {
    local project_root="$1"

    if ! command -v list_related_projects >/dev/null 2>&1; then
        return
    fi

    list_related_projects "$project_root" 3 70 | cut -d'|' -f1 | paste -sd ',' -
}

hook_classify_memory() {
    local hook_name="$1"
    local source="$2"
    local summary="$3"
    local content="$4"
    local tags="${5:-}"
    local concepts="${6:-}"
    local result=""
    local category=""
    local confidence=""
    local reason=""

    result=$(classify_memory "$source" "$summary" "$content" "$tags" "$concepts")
    category=$(printf "%s\n" "$result" | cut -d'|' -f1)
    confidence=$(printf "%s\n" "$result" | cut -d'|' -f2)
    reason=$(printf "%s\n" "$result" | cut -d'|' -f3-)

    hook_log "$hook_name" "CLASSIFICATION_SOURCE=rule CATEGORY=$category CONFIDENCE=$confidence REASON=$reason"
    printf "%s|%s|%s\n" "$category" "$confidence" "$reason"
}

hook_classification_policy() {
    local hook_name="$1"
    local source="$2"
    local category="$3"
    local confidence="$4"
    local memory_kind=""
    local inject_policy=""

    memory_kind=$(infer_memory_kind "$source" "$category" "$confidence")
    inject_policy=$(infer_auto_inject_policy "$source" "$category" "$confidence")

    hook_log "$hook_name" "MEMORY_KIND=$memory_kind AUTO_INJECT_POLICY=$inject_policy"
    printf "%s|%s\n" "$memory_kind" "$inject_policy"
}
