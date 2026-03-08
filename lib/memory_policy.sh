#!/bin/bash

infer_memory_kind() {
    local source="$1"
    local category="$2"
    local confidence="${3:-0}"

    case "$source" in
        manual)
            case "$category" in
                decision|solution|pattern) echo "durable" ;;
                *) echo "working" ;;
            esac
            ;;
        user_prompt_submit|stop_summary)
            case "$category" in
                decision|pattern)
                    if [ "$confidence" -ge 70 ]; then echo "durable"; else echo "working"; fi
                    ;;
                solution)
                    if [ "$confidence" -ge 85 ]; then echo "durable"; else echo "working"; fi
                    ;;
                debug)
                    echo "working"
                    ;;
                context)
                    if [ "$confidence" -ge 80 ]; then echo "working"; else echo "temporary"; fi
                    ;;
                *)
                    echo "working"
                    ;;
            esac
            ;;
        post_tool_use|session_end)
            case "$category" in
                decision|pattern)
                    if [ "$confidence" -ge 85 ]; then echo "working"; else echo "temporary"; fi
                    ;;
                solution)
                    if [ "$confidence" -ge 65 ]; then echo "working"; else echo "temporary"; fi
                    ;;
                debug)
                    if [ "$confidence" -ge 90 ]; then echo "working"; else echo "temporary"; fi
                    ;;
                *)
                    echo "temporary"
                    ;;
            esac
            ;;
        stop_final_response)
            case "$category" in
                decision|pattern)
                    if [ "$confidence" -ge 85 ]; then echo "working"; else echo "temporary"; fi
                    ;;
                solution)
                    if [ "$confidence" -ge 90 ]; then echo "working"; else echo "temporary"; fi
                    ;;
                *)
                    echo "temporary"
                    ;;
            esac
            ;;
        *) echo "working" ;;
    esac
}

infer_auto_inject_policy() {
    local source="$1"
    local category="$2"
    local confidence="${3:-0}"

    case "$source" in
        manual)
            case "$category" in
                decision|solution|pattern) echo "always" ;;
                *) echo "conditional" ;;
            esac
            ;;
        user_prompt_submit|stop_summary)
            case "$category" in
                decision|pattern)
                    if [ "$confidence" -ge 75 ]; then echo "always"; else echo "conditional"; fi
                    ;;
                solution)
                    if [ "$confidence" -ge 90 ]; then echo "always"; else echo "conditional"; fi
                    ;;
                debug)
                    echo "conditional"
                    ;;
                context)
                    if [ "$confidence" -ge 80 ]; then echo "conditional"; else echo "never"; fi
                    ;;
                *)
                    echo "conditional"
                    ;;
            esac
            ;;
        post_tool_use|session_end)
            case "$category" in
                decision|pattern)
                    if [ "$confidence" -ge 85 ]; then echo "conditional"; else echo "never"; fi
                    ;;
                solution)
                    if [ "$confidence" -ge 65 ]; then echo "conditional"; else echo "never"; fi
                    ;;
                debug)
                    if [ "$confidence" -ge 90 ]; then echo "conditional"; else echo "never"; fi
                    ;;
                *)
                    echo "never"
                    ;;
            esac
            ;;
        stop_final_response)
            case "$category" in
                decision|pattern|solution)
                    if [ "$confidence" -ge 90 ]; then echo "conditional"; else echo "manual_only"; fi
                    ;;
                *)
                    echo "manual_only"
                    ;;
            esac
            ;;
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

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF | tail -n 1
CREATE TEMP TABLE IF NOT EXISTS cleanup_candidates (id TEXT PRIMARY KEY);
DELETE FROM cleanup_candidates;
INSERT INTO cleanup_candidates(id)
SELECT id
FROM memories
WHERE memory_kind = 'temporary'
  AND auto_inject_policy IN ('never', 'manual_only')
  AND (
      (expires_at IS NOT NULL AND expires_at != '' AND expires_at < datetime('now'))
      OR timestamp_epoch < CAST(strftime('%s', 'now', '-$days days') AS INTEGER)
  )
ORDER BY
  CASE WHEN expires_at IS NOT NULL AND expires_at != '' THEN 0 ELSE 1 END ASC,
  COALESCE(expires_at, '') ASC,
  timestamp_epoch ASC
LIMIT $limit;
DELETE FROM memories WHERE id IN (SELECT id FROM cleanup_candidates);
SELECT changes();
DROP TABLE cleanup_candidates;
EOF
}

cleanup_aggressive_memories() {
    local days="${1:-30}"
    local limit="${2:-100}"

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF | tail -n 1
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
          AND timestamp_epoch < CAST(strftime('%s', 'now', '-$days days') AS INTEGER)
      )
      OR (
          memory_kind = 'working'
          AND auto_inject_policy = 'conditional'
          AND timestamp_epoch < CAST(strftime('%s', 'now', '-$days days') AS INTEGER)
      )
  )
ORDER BY
  CASE WHEN expires_at IS NOT NULL AND expires_at != '' THEN 0 ELSE 1 END ASC,
  COALESCE(expires_at, '') ASC,
  timestamp_epoch ASC
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

count_recent_memories() {
    local project_path="$1"
    local window_seconds="${2:-3600}"
    local where_clause=""
    local project_root=""
    local project_root_escaped=""

    if [ -n "$project_path" ]; then
        project_root=$(resolve_project_root "$project_path")
        project_root_escaped=$(sql_escape "$project_root")
        where_clause="project_root = '$project_root_escaped' AND "
    fi

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF
SELECT COUNT(*)
FROM memories
WHERE ${where_clause}timestamp_epoch >= CAST(strftime('%s', 'now') AS INTEGER) - $window_seconds;
EOF
}

should_force_opportunistic_cleanup() {
    local project_path="$1"
    local recent_threshold
    local window_seconds
    local recent_count=0

    recent_threshold=$(get_cleanup_growth_threshold)
    window_seconds=$(get_cleanup_growth_window_seconds)

    if [[ ! "$recent_threshold" =~ ^[0-9]+$ ]] || [ "$recent_threshold" -le 0 ]; then
        return 1
    fi

    recent_count=$(count_recent_memories "$project_path" "$window_seconds" 2>/dev/null || echo "0")
    [[ ! "$recent_count" =~ ^[0-9]+$ ]] && recent_count=0

    if [ "$recent_count" -ge "$recent_threshold" ]; then
        export CCMEM_CLEANUP_RECENT_COUNT="$recent_count"
        export CCMEM_CLEANUP_RECENT_WINDOW="$window_seconds"
        export CCMEM_CLEANUP_RECENT_THRESHOLD="$recent_threshold"
        return 0
    fi

    return 1
}

should_run_opportunistic_cleanup() {
    local throttle_seconds="${1:-$(get_cleanup_throttle_seconds)}"
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
    local throttle_seconds="${4:-$(get_cleanup_throttle_seconds)}"
    local project_path="$5"
    local state_file="${CCMEM_CLEANUP_STATE_FILE:-/tmp/ccmem_cleanup_state}"
    local deleted_count=""
    local now_ts=""
    local last_ts=""
    local age_seconds=""
    local cleanup_reason="schedule"

    if ! should_run_opportunistic_cleanup "$throttle_seconds"; then
        if should_force_opportunistic_cleanup "$project_path"; then
            cleanup_reason="growth"
            if [ -n "${CCMEM_DEBUG_LOG:-}" ]; then
                echo "[cleanup] $(date): trigger=$trigger bypass=growth recent_count=${CCMEM_CLEANUP_RECENT_COUNT:-0} threshold=${CCMEM_CLEANUP_RECENT_THRESHOLD:-0} window_seconds=${CCMEM_CLEANUP_RECENT_WINDOW:-0} project=$(resolve_project_root "${project_path:-}")" >> "$CCMEM_DEBUG_LOG"
            fi
        else
            if [ -n "${CCMEM_DEBUG_LOG:-}" ]; then
                now_ts=$(date +%s 2>/dev/null || echo "0")
                last_ts=$(cat "$state_file" 2>/dev/null || echo "0")
                age_seconds=$((now_ts - last_ts))
                echo "[cleanup] $(date): trigger=$trigger skipped=throttle last_run=$last_ts age_seconds=$age_seconds" >> "$CCMEM_DEBUG_LOG"
            fi
            return 0
        fi
    fi

    if [ -n "${CCMEM_DEBUG_LOG:-}" ]; then
        echo "[cleanup] $(date): trigger=$trigger mode=safe days=$days limit=$limit reason=$cleanup_reason" >> "$CCMEM_DEBUG_LOG"
    fi

    deleted_count=$(cleanup_memories "safe" "$days" "$limit" 2>/dev/null || echo "error")
    if [[ ! "$deleted_count" =~ ^[0-9]+$ ]]; then
        if [ -n "${CCMEM_DEBUG_LOG:-}" ]; then
            echo "[cleanup] $(date): trigger=$trigger failed result=$deleted_count" >> "$CCMEM_DEBUG_LOG"
        fi
        return 1
    fi

    mark_opportunistic_cleanup_run

    if [ -n "${CCMEM_DEBUG_LOG:-}" ]; then
        echo "[cleanup] $(date): trigger=$trigger deleted=$deleted_count scope=temporary never/manual_only" >> "$CCMEM_DEBUG_LOG"
    fi
}
