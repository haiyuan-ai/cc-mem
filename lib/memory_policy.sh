#!/bin/bash

infer_memory_kind() {
    local source="$1"
    local category="$2"

    case "$source" in
        manual)
            case "$category" in
                decision|solution|pattern) echo "durable" ;;
                *) echo "working" ;;
            esac
            ;;
        user_prompt_submit|stop_summary) echo "working" ;;
        stop_final_response|post_tool_use|session_end) echo "temporary" ;;
        *) echo "working" ;;
    esac
}

infer_auto_inject_policy() {
    local source="$1"
    local category="$2"

    case "$source" in
        manual)
            case "$category" in
                decision|solution|pattern) echo "always" ;;
                *) echo "conditional" ;;
            esac
            ;;
        user_prompt_submit|stop_summary) echo "conditional" ;;
        stop_final_response) echo "manual_only" ;;
        post_tool_use|session_end) echo "never" ;;
        *) echo "conditional" ;;
    esac
}

generate_future_sqlite_timestamp() {
    local days="$1"

    if date -u -d "+${days} days" +"%Y-%m-%d %H:%M:%S" >/dev/null 2>&1; then
        date -u -d "+${days} days" +"%Y-%m-%d %H:%M:%S"
    elif date -u -v+"${days}"d +"%Y-%m-%d %H:%M:%S" >/dev/null 2>&1; then
        date -u -v+"${days}"d +"%Y-%m-%d %H:%M:%S"
    else
        echo ""
    fi
}

infer_expires_at() {
    local source="$1"
    local memory_kind="$2"

    if [ "$memory_kind" != "temporary" ]; then
        case "$source" in
            stop_summary) generate_future_sqlite_timestamp 14 ;;
            *) echo "" ;;
        esac
        return
    fi

    case "$source" in
        post_tool_use|session_end) generate_future_sqlite_timestamp 3 ;;
        stop_final_response) generate_future_sqlite_timestamp 7 ;;
        *) echo "" ;;
    esac
}

cleanup_low_priority_memories() {
    local days="${1:-30}"
    local limit="${2:-100}"

    sqlite3 "$MEMORY_DB" <<EOF | tail -n 1
CREATE TEMP TABLE IF NOT EXISTS cleanup_candidates (id TEXT PRIMARY KEY);
DELETE FROM cleanup_candidates;
INSERT INTO cleanup_candidates(id)
SELECT id
FROM memories
WHERE memory_kind = 'temporary'
  AND auto_inject_policy IN ('never', 'manual_only')
  AND (
      (expires_at IS NOT NULL AND expires_at != '' AND expires_at < datetime('now'))
      OR timestamp < datetime('now', '-$days days')
  )
ORDER BY
  CASE
    WHEN expires_at IS NOT NULL AND expires_at != '' THEN expires_at
    ELSE timestamp
  END ASC
LIMIT $limit;
DELETE FROM memories WHERE id IN (SELECT id FROM cleanup_candidates);
SELECT changes();
DROP TABLE cleanup_candidates;
EOF
}

cleanup_aggressive_memories() {
    local days="${1:-30}"
    local limit="${2:-100}"

    sqlite3 "$MEMORY_DB" <<EOF | tail -n 1
CREATE TEMP TABLE IF NOT EXISTS cleanup_candidates (id TEXT PRIMARY KEY);
DELETE FROM cleanup_candidates;
INSERT INTO cleanup_candidates(id)
SELECT id
FROM memories
WHERE NOT (memory_kind = 'durable' AND auto_inject_policy = 'always')
  AND (
      (expires_at IS NOT NULL AND expires_at != '' AND expires_at < datetime('now'))
      OR (
          memory_kind = 'temporary'
          AND auto_inject_policy IN ('never', 'manual_only')
          AND timestamp < datetime('now', '-$days days')
      )
      OR (
          memory_kind = 'working'
          AND auto_inject_policy = 'conditional'
          AND timestamp < datetime('now', '-$days days')
      )
  )
ORDER BY
  CASE
    WHEN expires_at IS NOT NULL AND expires_at != '' THEN expires_at
    ELSE timestamp
  END ASC
LIMIT $limit;
DELETE FROM memories WHERE id IN (SELECT id FROM cleanup_candidates);
SELECT changes();
DROP TABLE cleanup_candidates;
EOF
}

cleanup_memories() {
    local mode="${1:-safe}"
    local days="${2:-30}"
    local limit="${3:-100}"

    case "$mode" in
        safe)
            cleanup_low_priority_memories "$days" "$limit"
            ;;
        aggressive)
            cleanup_aggressive_memories "$days" "$limit"
            ;;
        *)
            echo "error:unknown cleanup mode '$mode'"
            return 1
            ;;
    esac
}

should_run_opportunistic_cleanup() {
    local throttle_seconds="${1:-43200}"
    local state_file="${CCMEM_CLEANUP_STATE_FILE:-/tmp/ccmem_cleanup_state}"
    local now_ts=""
    local last_ts=""

    now_ts=$(date +%s 2>/dev/null || echo "0")
    [ ! -f "$state_file" ] && return 0

    last_ts=$(cat "$state_file" 2>/dev/null || echo "")
    [[ ! "$last_ts" =~ ^[0-9]+$ ]] && return 0

    if [ $((now_ts - last_ts)) -ge "$throttle_seconds" ]; then
        return 0
    fi

    return 1
}

mark_opportunistic_cleanup_run() {
    local state_file="${CCMEM_CLEANUP_STATE_FILE:-/tmp/ccmem_cleanup_state}"
    date +%s 2>/dev/null > "$state_file"
}

run_opportunistic_cleanup() {
    local trigger="$1"
    local days="${2:-30}"
    local limit="${3:-50}"
    local throttle_seconds="${4:-43200}"
    local state_file="${CCMEM_CLEANUP_STATE_FILE:-/tmp/ccmem_cleanup_state}"
    local deleted_count=""
    local now_ts=""
    local last_ts=""
    local age_seconds=""

    if ! should_run_opportunistic_cleanup "$throttle_seconds"; then
        if [ -n "${DEBUG_LOG:-}" ]; then
            now_ts=$(date +%s 2>/dev/null || echo "0")
            last_ts=$(cat "$state_file" 2>/dev/null || echo "0")
            age_seconds=$((now_ts - last_ts))
            echo "[cleanup] $(date): trigger=$trigger skipped=throttle last_run=$last_ts age_seconds=$age_seconds" >> "$DEBUG_LOG"
        fi
        return 0
    fi

    if [ -n "${DEBUG_LOG:-}" ]; then
        echo "[cleanup] $(date): trigger=$trigger mode=safe days=$days limit=$limit" >> "$DEBUG_LOG"
    fi

    deleted_count=$(cleanup_memories "safe" "$days" "$limit" 2>/dev/null || echo "error")
    if [[ ! "$deleted_count" =~ ^[0-9]+$ ]]; then
        if [ -n "${DEBUG_LOG:-}" ]; then
            echo "[cleanup] $(date): trigger=$trigger failed result=$deleted_count" >> "$DEBUG_LOG"
        fi
        return 1
    fi

    mark_opportunistic_cleanup_run

    if [ -n "${DEBUG_LOG:-}" ]; then
        echo "[cleanup] $(date): trigger=$trigger deleted=$deleted_count scope=temporary never/manual_only" >> "$DEBUG_LOG"
    fi
}
