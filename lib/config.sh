#!/bin/bash
# Source guard - prevent double-loading
[[ -n "${_CCMEM_CONFIG_SH_LOADED:-}" ]] && return 0 2>/dev/null || true
_CCMEM_CONFIG_SH_LOADED=1

CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCMEM_ROOT_DIR="$(cd "$CONFIG_LIB_DIR/.." && pwd)"
CCMEM_DEFAULT_CONFIG_FILE="$CCMEM_ROOT_DIR/config/config.json"
CCMEM_CONFIG_STATUS=""
CCMEM_CONFIG_STATUS_FILE=""
CCMEM_CONFIG_WARNING_EMITTED=""

expand_config_path() {
    local path="$1"

    case "$path" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s/%s\n' "$HOME" "${path#~/}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

get_config_file_path() {
    printf '%s\n' "${CCMEM_CONFIG_FILE:-$CCMEM_DEFAULT_CONFIG_FILE}"
}

warn_config_once() {
    local message="$1"

    if [ -n "$CCMEM_CONFIG_WARNING_EMITTED" ]; then
        return
    fi

    CCMEM_CONFIG_WARNING_EMITTED="1"
    printf 'cc-mem: %s\n' "$message" >&2
}

ensure_config_state() {
    local config_file=""

    config_file=$(get_config_file_path)
    if [ "$CCMEM_CONFIG_STATUS_FILE" = "$config_file" ] && [ -n "$CCMEM_CONFIG_STATUS" ]; then
        return
    fi

    CCMEM_CONFIG_STATUS_FILE="$config_file"
    CCMEM_CONFIG_STATUS=""

    if [ ! -f "$config_file" ]; then
        CCMEM_CONFIG_STATUS="missing"
        return
    fi

    if ! command -v jq >/dev/null 2>&1; then
        CCMEM_CONFIG_STATUS="no_jq"
        warn_config_once "jq not found; ignoring config file $config_file and using defaults"
        return
    fi

    if ! jq empty "$config_file" >/dev/null 2>&1; then
        CCMEM_CONFIG_STATUS="invalid"
        warn_config_once "invalid config file $config_file; using defaults"
        return
    fi

    CCMEM_CONFIG_STATUS="ok"
}

config_get() {
    local key="$1"
    local default_value="${2:-}"
    local config_file=""
    local value=""

    config_file=$(get_config_file_path)
    ensure_config_state
    if [ "$CCMEM_CONFIG_STATUS" != "ok" ]; then
        printf '%s\n' "$default_value"
        return
    fi

    value=$(jq -r ".$key // empty" "$config_file" 2>/dev/null || true)
    if [ -n "$value" ] && [ "$value" != "null" ]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$default_value"
    fi
}

config_get_path() {
    local key="$1"
    local default_value="${2:-}"
    expand_config_path "$(config_get "$key" "$default_value")"
}

get_memory_db_path() {
    config_get_path "memory_db" "$HOME/.claude/cc-mem/memory.db"
}

get_failed_queue_dir() {
    config_get_path "failed_queue_dir" "/tmp/ccmem_failed_queue"
}

get_debug_log_path_runtime() {
    config_get_path "debug_log" "/tmp/ccmem_debug.log"
}

get_markdown_export_path() {
    config_get_path "markdown_export_path" "$HOME/cc-mem-export"
}

get_cleanup_throttle_seconds() {
    config_get "cleanup.throttle_seconds" "43200"
}

get_cleanup_growth_threshold() {
    config_get "cleanup.growth_threshold" "100"
}

get_cleanup_growth_window_seconds() {
    config_get "cleanup.growth_window_seconds" "3600"
}

get_injection_session_start_limit() {
    config_get "injection.session_start_limit" "3"
}

get_injection_recall_limit() {
    config_get "injection.recall_limit" "3"
}

get_injection_related_project_limit() {
    config_get "injection.related_project_limit" "1"
}

get_post_tool_use_flush_lines() {
    config_get "hooks.post_tool_use_flush_lines" "3"
}

get_preview_limit_for_kind() {
    local memory_kind="$1"

    case "$memory_kind" in
        durable)
            config_get "preview.durable_max_chars" "320"
            ;;
        temporary)
            config_get "preview.temporary_max_chars" "180"
            ;;
        working|*)
            config_get "preview.working_max_chars" "220"
            ;;
    esac
}

apply_runtime_config() {
    export CCMEM_MEMORY_DB="$(get_memory_db_path)"
    export CCMEM_FAILED_QUEUE_DIR="$(get_failed_queue_dir)"
    export CCMEM_DEBUG_LOG="$(get_debug_log_path_runtime)"
}
