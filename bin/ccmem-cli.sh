#!/bin/bash
# CC-Mem CLI - Lightweight memory management tool
# Usage: ccmem-cli.sh <command> [options]

set -e

# Restore PATH (if core tools are missing)
if ! command -v dirname &> /dev/null; then
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CONFIG_DIR="$SCRIPT_DIR/config"

source "$LIB_DIR/sqlite.sh"
source "$LIB_DIR/content_utils.sh"
source "$LIB_DIR/classification.sh"

load_config() {
    export CCMEM_CONFIG_FILE="${CCMEM_CONFIG_FILE:-$CONFIG_DIR/config.json}"
    apply_runtime_config
}

resolve_effective_project_path() {
    local project_path="$1"
    if [ -n "$project_path" ]; then
        printf '%s\n' "$project_path"
    else
        pwd
    fi
}

build_default_summary() {
    local content="$1"
    printf '%s...\n' "${content:0:100}"
}

print_unknown_option() {
    echo "Unknown option: $1"
    return 1
}

print_command_usage() {
    echo "Usage: ccmem $1"
}

handle_store_memory_result() {
    local id="$1"
    local prefix="${2:-}"
    local private_warning="${3:-}"
    local success_message="${4:-Memory stored}"
    if [[ "$id" == duplicate:* ]]; then
        echo "${prefix}Skipped: Content already exists (duplicate memory ID: ${id#duplicate:})"
        return 0
    fi
    if [[ "$id" == error:* ]]; then
        echo "${prefix}Error: Failed to store memory - ${id#error:}"
        return 1
    fi
    if [ -n "$private_warning" ]; then
        echo "$private_warning"
    fi
    echo "${prefix}${success_message}"
    return 0
}

ensure_db_ready() {
    mkdir -p "$(dirname "$CCMEM_MEMORY_DB")"

    if [ ! -f "$CCMEM_MEMORY_DB" ]; then
        init_db >/dev/null 2>&1
        return
    fi

    local has_memories
    has_memories=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='memories';" 2>/dev/null || true)
    if [ "$has_memories" != "memories" ]; then
        init_db >/dev/null 2>&1
    fi
}

get_failed_capture_queue_dir() {
    printf '%s\n' "$CCMEM_FAILED_QUEUE_DIR"
}

get_debug_log_path() {
    printf '%s\n' "$CCMEM_DEBUG_LOG"
}

format_epoch_local() {
    local epoch="$1"

    if [ -z "$epoch" ] || [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "unknown"
        return
    fi

    if date -r "$epoch" "+%Y-%m-%d %H:%M:%S" >/dev/null 2>&1; then
        date -r "$epoch" "+%Y-%m-%d %H:%M:%S"
    elif date -d "@$epoch" "+%Y-%m-%d %H:%M:%S" >/dev/null 2>&1; then
        date -d "@$epoch" "+%Y-%m-%d %H:%M:%S"
    else
        printf '%s\n' "$epoch"
    fi
}

format_ratio_percent() {
    local numerator="${1:-0}"
    local denominator="${2:-0}"

    if [ -z "$denominator" ] || [ "$denominator" = "0" ]; then
        printf '%s\n' "0.0%%"
        return
    fi

    awk -v num="$numerator" -v den="$denominator" 'BEGIN {
        printf "%.1f%%\n", (num / den) * 100
    }'
}

format_decimal() {
    local numerator="${1:-0}"
    local denominator="${2:-1}"

    if [ -z "$denominator" ] || [ "$denominator" = "0" ]; then
        printf '%s\n' "0.0"
        return
    fi

    awk -v num="$numerator" -v den="$denominator" 'BEGIN {
        printf "%.1f\n", num / den
    }'
}

print_failed_queue_summary() {
    local queue_dir
    queue_dir=$(get_failed_capture_queue_dir)
    local total_count=0
    local latest_epoch=0
    local latest_time="none"
    local hook_summary=""

    echo "Failed queue: $queue_dir"
    if [ ! -d "$queue_dir" ]; then
        echo "  Status: empty"
        return
    fi

    total_count=$(find "$queue_dir" -type f -name 'failed_*' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$total_count" = "0" ]; then
        echo "  Status: empty"
        return
    fi

    latest_epoch=$(find "$queue_dir" -type f -name 'failed_*' -exec stat -f '%m' {} \; 2>/dev/null | sort -nr | head -1)
    if [ -z "$latest_epoch" ]; then
        latest_epoch=$(find "$queue_dir" -type f -name 'failed_*' -exec stat -c '%Y' {} \; 2>/dev/null | sort -nr | head -1)
    fi
    latest_time=$(format_epoch_local "$latest_epoch")
    hook_summary=$(find "$queue_dir" -type f -name 'failed_*' 2>/dev/null | sed -E 's|.*/failed_([^_]+).*|\1|' | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}' | sed 's/ $//')

    echo "  Files: $total_count"
    echo "  Latest failure: $latest_time"
    echo "  Hook distribution: ${hook_summary:-unknown}"
}

print_recent_cleanup_summary() {
    local debug_log
    debug_log=$(get_debug_log_path)
    local latest_cleanup=""
    local latest_result=""

    echo "Recent cleanup:"
    if [ ! -f "$debug_log" ]; then
        echo "  Status: no records"
        return
    fi

    latest_cleanup=$(grep '\[cleanup\].*mode=' "$debug_log" 2>/dev/null | tail -1 || true)
    latest_result=$(grep '\[cleanup\].*deleted=' "$debug_log" 2>/dev/null | tail -1 || true)

    if [ -z "$latest_cleanup" ] && [ -z "$latest_result" ]; then
        echo "  Status: no records"
        return
    fi

    if [ -n "$latest_cleanup" ]; then
        echo "  Latest trigger: $latest_cleanup"
    fi
    if [ -n "$latest_result" ]; then
        echo "  Latest result: $latest_result"
    fi
}

show_help() {
    cat <<EOF
CC-Mem CLI - Memory management tool for Claude Code

Usage: ccmem-cli.sh <command> [options]

Commands:
  init              Initialize database
  capture           Capture current session memory
  search            Search memories (3-step retrieval #1)
  recall            Generate query-aware recall context
  timeline          Get timeline context (3-step retrieval #2)
  get               Get memory details (3-step retrieval #3)
  history           View memory history
  list              List recent memories
  export            Export memories to Markdown
  retry             Retry failed memory writes
  inject-context    Generate session start context
  projects          List all projects
  related-projects  List related projects
  link-projects     Manually link projects
  unlink-projects   Remove project link
  refresh-project-links  Refresh auto project links
  cleanup           Cleanup expired memories (safe mode default)
  status            Show memory database status
  stats             Show recent memory statistics
  help              Show this help

Examples:
  ccmem-cli.sh search -p "/path/to/project" -q "API endpoint"
  ccmem-cli.sh recall -p "/path/to/project" -q "SQLite timeout"
  ccmem-cli.sh timeline -a mem_xxx -b 3 -A 3
  ccmem-cli.sh get mem_123 mem_456
  ccmem-cli.sh capture -c "decision" -t "important,core"
  echo "important pattern" | ccmem-cli.sh capture -c "pattern" -t "react,hooks" -m "custom summary"
  ccmem-cli.sh export -o "~/exports"
  ccmem-cli.sh retry --dry-run
  ccmem-cli.sh related-projects -p "/path/to/project"
  ccmem-cli.sh stats --days 7
Options:
  -p, --project     Project path
  -c, --category    Memory category (decision|solution|pattern|debug|context)
  -t, --tags        Tags (comma-separated)
  -m, --summary     Custom summary
  --concepts        Concept tags (how-it-works|problem-solution|gotcha|pattern|trade-off|why-it-exists|what-changed)
  -q, --query       Search query
  -o, --output      Export directory (default: \$HOME/cc-mem-export)
  -l, --limit       Limit results (default: 10)
  --hook            Only process failed items for specified hook
  --dry-run         Show what would be processed without writing
  -s, --session     Session ID
  -h, --help        Show help

EOF
}

cmd_capture() {
    local project_path=""
    local category="context"
    local tags=""
    local summary=""
    local concepts=""
    local session_id="${CLAUDE_SESSION_ID:-$$}"
    local source="manual"
    local memory_kind=""
    local auto_inject_policy=""
    local project_root=""
    local expires_at=""
    local classification_confidence=""
    local classification_reason=""
    local classification_source=""
    local classification_version=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -c|--category) category="$2"; shift ;;
            -t|--tags) tags="$2"; shift ;;
            -m|--summary) summary="$2"; shift ;;
            --concepts) concepts="$2"; shift ;;
            -s|--session) session_id="$2"; shift ;;
            --source) source="$2"; shift ;;
            --memory-kind) memory_kind="$2"; shift ;;
            --inject-policy) auto_inject_policy="$2"; shift ;;
            --project-root) project_root="$2"; shift ;;
            --expires-at) expires_at="$2"; shift ;;
            --classification-confidence) classification_confidence="$2"; shift ;;
            --classification-reason) classification_reason="$2"; shift ;;
            --classification-source) classification_source="$2"; shift ;;
            --classification-version) classification_version="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    echo "Capturing memory..."
    echo "  Session ID: $session_id"
    echo "  Project path: ${project_path:-not specified}"
    echo "  Category: $category"
    echo "  Tags: ${tags:-none}"
    echo "  Concepts: ${concepts:-none}"

    # If project path not specified, use current directory
    project_path="$(resolve_effective_project_path "$project_path")"

    # Update project access record
    update_project_access "$project_path" "$(basename "$project_path")" "$tags"

    # Create/update session
    upsert_session "$session_id" "$project_path"

    # If reading from stdin
    if [ ! -t 0 ]; then
        local content=$(cat)
        if [ -n "$content" ]; then
            # Check and filter private content
            local filtered_content="$content"
            local private_warning=""

            if has_private_content "$content"; then
                filtered_content=$(filter_private_content "$content")
                private_warning="  Warning: Filtered <private> tag content"

                # If filtered content is empty, don't save
                if [ -z "$(echo "$filtered_content" | tr -d '[:space:]')" ]; then
                    echo "  Skipped: No valid content after filtering private tags"
                    return
                fi
            fi

            filtered_content=$(strip_injected_context_blocks "$filtered_content")

            if [ -z "$summary" ]; then
                summary=$(build_default_summary "$filtered_content")
            fi

            # If concepts not specified, try auto-detect
            if [ -z "$concepts" ]; then
                concepts=$(detect_concepts "$filtered_content")
                if [ -n "$concepts" ]; then
                    echo "  Auto-detected concepts: $concepts"
                fi
            fi

            local id=$(store_memory "$session_id" "$project_path" "$category" "$filtered_content" "$summary" "$tags" "$concepts" "$source" "$memory_kind" "$auto_inject_policy" "$project_root" "$expires_at" "$classification_confidence" "$classification_reason" "$classification_source" "$classification_version")

            if ! handle_store_memory_result "$id" "  " "$private_warning" "Memory ID: $id"; then
                return 1
            fi
            echo "Memory stored"
            return 0
        fi
    fi

    echo "No content captured (stdin is empty)"
}
cmd_search() {
    local project_path=""
    local query=""
    local category=""
    local limit=10
    local min_results=3

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -q|--query) query="$2"; shift ;;
            -c|--category) category="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            --min) min_results="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    echo "Searching memories..."
    echo "  Project path: $project_path"
    echo "  Query: ${query:-all}"
    echo "  Category: ${category:-all}"
    echo "  Limit: $limit (min results: $min_results)"
    echo ""

    # 使用分阶段检索（带充分性检查）
    local tmp_results
    tmp_results=$(mktemp "${TMPDIR:-/tmp}/ccmem-search.XXXXXX")
    retrieve_memories_staged "$project_path" "$query" "$category" "$limit" "$min_results" > "$tmp_results"
    local results
    results=$(cat "$tmp_results")
    rm -f "$tmp_results"

    if [ -n "$query" ]; then
        if contains_cjk "$query" && [ "${RETRIEVE_CJK_FALLBACK_USED:-0}" -eq 1 ]; then
            echo "  CJK fallback: used"
        else
            echo "  CJK fallback: not used"
        fi
        echo ""
    fi
    echo "$results"
}

cmd_recall() {
    local project_path=""
    local query=""
    local limit
    limit=$(get_injection_recall_limit)

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -q|--query) query="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            -h|--help)
                print_command_usage "recall -p <project> -q <query> [-l limit]"
                echo "Generate query-aware recall context block"
                echo ""
                echo "Options:"
                echo "  -p, --project    Project path (default: current directory)"
                echo "  -q, --query      Current request keywords"
                echo "  -l, --limit      Recall result count (default from config, fallback 3)"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    if [ -z "$query" ]; then
        print_command_usage "recall -p <project> -q <query> [-l limit]"
        return 1
    fi

    project_path="$(resolve_effective_project_path "$project_path")"
    generate_query_recall_context "$project_path" "$query" "$limit"
}

cmd_list() {
    local limit=20
    local project_path=""
    local project_path_escaped=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -l|--limit) limit="$2"; shift ;;
            -p|--project) project_path="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    local where_clause="WHERE 1=1"
    if [ -n "$project_path" ]; then
        project_path_escaped=$(sql_escape "$project_path")
        where_clause="WHERE project_path = '$project_path_escaped'"
    fi

    sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, datetime(timestamp_epoch, 'unixepoch', 'localtime') AS timestamp, category, concepts, summary, project_path, tags
FROM memories
$where_clause
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
}

cmd_export() {
    local output_dir=""
    local project_path=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -o|--output) output_dir="$2"; shift ;;
            -p|--project) project_path="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    # Config priority: CLI args > config file > defaults
    if [ -z "$output_dir" ]; then
        output_dir=$(get_markdown_export_path)

        # Final default
        if [ -z "$output_dir" ] || [ "$output_dir" = "null" ]; then
            output_dir="$HOME/cc-mem-export"
        fi
    fi

    echo "Exporting memories to: $output_dir"

    # Use safe Markdown export to avoid delimiter pollution
    export_to_markdown_safe "$output_dir" "$project_path"

    echo "Export complete"
}

retry_map_hook_metadata() {
    local hook_name="$1"

    case "$hook_name" in
        post-tool-use)
            printf '%s|%s|%s\n' "post_tool_use" "auto-captured" "what-changed"
            ;;
        user-prompt-submit)
            printf '%s|%s|%s\n' "user_prompt_submit" "auto-captured" "what-changed"
            ;;
        session-end)
            printf '%s|%s|%s\n' "session_end" "auto-captured,session-end" "what-changed"
            ;;
        stop)
            printf '%s|%s|%s\n' "stop_summary" "auto-captured,stop" "what-changed"
            ;;
        stop-final-response)
            printf '%s|%s|%s\n' "stop_final_response" "final-response,stop" "what-changed"
            ;;
        *)
            return 1
            ;;
    esac
}

retry_read_metadata() {
    local file_path="$1"
    local key="$2"

    awk -v target="$key" '
        /^# / {
            line = substr($0, 3)
            n = split(line, parts, " ")
            for (i = 1; i <= n; i++) {
                split(parts[i], pair, "=")
                if (pair[1] == target) {
                    print substr(parts[i], length(target) + 2)
                    exit
                }
            }
            next
        }
        { exit }
    ' "$file_path"
}

retry_read_content() {
    local file_path="$1"

    awk '
        header = 1
        header && /^# [A-Za-z0-9_]+=.*$/ { next }
        { header = 0; print }
    ' "$file_path"
}

retry_decode_metadata_value() {
    local value="$1"

    if [ -z "$value" ]; then
        return
    fi

    if command -v base64 >/dev/null 2>&1; then
        if printf '%s' "$value" | base64 --decode >/dev/null 2>&1; then
            printf '%s' "$value" | base64 --decode
            return
        fi
        if printf '%s' "$value" | base64 -d >/dev/null 2>&1; then
            printf '%s' "$value" | base64 -d
            return
        fi
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - <<PY 2>/dev/null || printf '%s' "$value"
import base64
print(base64.b64decode("""$value""").decode("utf-8"), end="")
PY
        return
    fi

    printf '%s' "$value"
}

export_to_markdown_safe() {
    local output_dir="$1"
    local project_path="$2"
    local where_clause="WHERE 1=1"
    local project_path_escaped=""
    local memory_id=""
    local memory_id_escaped=""
    local timestamp=""
    local category=""
    local summary=""
    local tags=""
    local content=""
    local stored_project_path=""
    local safe_timestamp=""
    local filename=""

    mkdir -p "$output_dir"

    if [ -n "$project_path" ]; then
        project_path_escaped=$(sql_escape "$project_path")
        where_clause="$where_clause AND project_path = '$project_path_escaped'"
    fi

    while IFS= read -r memory_id; do
        [ -z "$memory_id" ] && continue
        memory_id_escaped=$(sql_escape "$memory_id")
        timestamp=$(sqlite3 -noheader "$CCMEM_MEMORY_DB" "SELECT $(memory_display_timestamp_sql) FROM memories WHERE id = '$memory_id_escaped';")
        category=$(sqlite3 -noheader "$CCMEM_MEMORY_DB" "SELECT COALESCE(category, '') FROM memories WHERE id = '$memory_id_escaped';")
        summary=$(sqlite3 -noheader "$CCMEM_MEMORY_DB" "SELECT COALESCE(summary, '') FROM memories WHERE id = '$memory_id_escaped';")
        tags=$(sqlite3 -noheader "$CCMEM_MEMORY_DB" "SELECT COALESCE(tags, '') FROM memories WHERE id = '$memory_id_escaped';")
        content=$(sqlite3 -noheader "$CCMEM_MEMORY_DB" "SELECT COALESCE(content, '') FROM memories WHERE id = '$memory_id_escaped';")
        stored_project_path=$(sqlite3 -noheader "$CCMEM_MEMORY_DB" "SELECT COALESCE(project_path, '') FROM memories WHERE id = '$memory_id_escaped';")

        [ -z "$timestamp" ] && continue
        safe_timestamp="${timestamp//:/-}"
        safe_timestamp="${safe_timestamp// /_}"
        filename="$output_dir/${safe_timestamp}_${memory_id}.md"

        cat > "$filename" <<MDEOF
---
id: $memory_id
timestamp: $timestamp
category: $category
tags: $tags
project: $stored_project_path
---

# $summary

$content
MDEOF
    done < <(sqlite3 -noheader "$CCMEM_MEMORY_DB" "SELECT id FROM memories $where_clause AND id GLOB 'mem_*' ORDER BY timestamp_epoch DESC;")
}

retry_process_file() {
    local file_path="$1"
    local hook_name=""
    local session_id=""
    local meta=""
    local source=""
    local tags=""
    local concepts=""
    local content=""
    local filtered_content=""
    local summary=""
    local classification_result=""
    local category=""
    local confidence=""
    local reason=""
    local memory_kind=""
    local auto_inject_policy=""
    local project_path=""
    local project_root=""
    local queued_source=""
    local queued_tags=""
    local queued_concepts=""
    local queued_summary=""
    local store_result=""

    hook_name=$(retry_read_metadata "$file_path" "hook")
    session_id=$(retry_read_metadata "$file_path" "session_id")
    project_path=$(retry_decode_metadata_value "$(retry_read_metadata "$file_path" "project_path_b64")")
    project_root=$(retry_decode_metadata_value "$(retry_read_metadata "$file_path" "project_root_b64")")
    queued_source=$(retry_decode_metadata_value "$(retry_read_metadata "$file_path" "source_b64")")
    queued_tags=$(retry_decode_metadata_value "$(retry_read_metadata "$file_path" "tags_b64")")
    queued_concepts=$(retry_decode_metadata_value "$(retry_read_metadata "$file_path" "concepts_b64")")
    queued_summary=$(retry_decode_metadata_value "$(retry_read_metadata "$file_path" "summary_b64")")

    if [ -z "$hook_name" ]; then
        printf '%s\n' "skip:missing-hook"
        return 0
    fi

    meta=$(retry_map_hook_metadata "$hook_name" || true)
    if [ -z "$meta" ]; then
        printf '%s\n' "skip:unsupported-hook"
        return 0
    fi

    source=$(printf '%s' "$meta" | cut -d'|' -f1)
    tags=$(printf '%s' "$meta" | cut -d'|' -f2)
    concepts=$(printf '%s' "$meta" | cut -d'|' -f3)
    [ -n "$queued_source" ] && source="$queued_source"
    [ -n "$queued_tags" ] && tags="$queued_tags"
    [ -n "$queued_concepts" ] && concepts="$queued_concepts"
    content=$(retry_read_content "$file_path")
    filtered_content=$(strip_injected_context_blocks "$content")

    if [ -z "$(printf '%s' "$filtered_content" | tr -d '[:space:]')" ]; then
        printf '%s\n' "fail:empty-content"
        return 1
    fi

    summary="$queued_summary"
    if [ -z "$summary" ]; then
        summary=$(build_default_summary "$filtered_content")
    fi
    classification_result=$(classify_memory "$source" "$summary" "$filtered_content" "$tags" "$concepts")
    category=$(printf '%s' "$classification_result" | cut -d'|' -f1)
    confidence=$(printf '%s' "$classification_result" | cut -d'|' -f2)
    reason=$(printf '%s' "$classification_result" | cut -d'|' -f3-)
    memory_kind=$(infer_memory_kind "$source" "$category" "$confidence")
    auto_inject_policy=$(infer_auto_inject_policy "$source" "$category" "$confidence")

    if [ -z "$session_id" ]; then
        session_id="retry_$$"
    fi

    store_result=$(store_memory \
        "$session_id" \
        "$project_path" \
        "$category" \
        "$filtered_content" \
        "$summary" \
        "$tags" \
        "$concepts" \
        "$source" \
        "$memory_kind" \
        "$auto_inject_policy" \
        "$project_root" \
        "" \
        "$confidence" \
        "$reason" \
        "rule" \
        "rule-v2")

    case "$store_result" in
        duplicate:*)
            rm -f "$file_path"
            printf '%s\n' "duplicate:${store_result#duplicate:}"
            ;;
        error:*)
            printf '%s\n' "fail:${store_result#error:}"
            return 1
            ;;
        *)
            rm -f "$file_path"
            printf '%s\n' "success:$store_result"
            ;;
    esac
}

cmd_retry() {
    local queue_dir=""
    local dry_run=false
    local limit=""
    local hook_filter=""
    local files=()
    local file_path=""
    local scanned=0
    local matched=0
    local recovered=0
    local duplicates=0
    local failed=0
    local skipped=0
    local result=""
    local hook_name=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --dry-run) dry_run=true ;;
            --limit) limit="$2"; shift ;;
            --hook) hook_filter="$2"; shift ;;
            -h|--help)
                print_command_usage "retry [--dry-run] [--limit count] [--hook name]"
                echo "Retry failed capture queue items."
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    queue_dir=$(get_failed_capture_queue_dir)
    if [ ! -d "$queue_dir" ]; then
        echo "Failed queue is empty"
        return 0
    fi

    while IFS= read -r file_path; do
        [ -n "$file_path" ] && files+=("$file_path")
    done < <(find "$queue_dir" -type f -name 'failed_*' | sort)

    if [ "${#files[@]}" -eq 0 ]; then
        echo "Failed queue is empty"
        return 0
    fi

    for file_path in "${files[@]}"; do
        scanned=$((scanned + 1))
        hook_name=$(retry_read_metadata "$file_path" "hook")
        if [ -n "$hook_filter" ] && [ "$hook_name" != "$hook_filter" ]; then
            continue
        fi
        matched=$((matched + 1))
        if [ -n "$limit" ] && [ "$matched" -gt "$limit" ]; then
            matched=$((matched - 1))
            break
        fi

        if [ "$dry_run" = true ]; then
            echo "Will process: $(basename "$file_path") hook=${hook_name:-unknown}"
            continue
        fi

        result=$(retry_process_file "$file_path" || true)
        case "$result" in
            success:*)
                recovered=$((recovered + 1))
                ;;
            duplicate:*)
                duplicates=$((duplicates + 1))
                ;;
            skip:*)
                skipped=$((skipped + 1))
                ;;
            fail:*)
                failed=$((failed + 1))
                echo "Retry failed: $(basename "$file_path") ${result#fail:}"
                ;;
            *)
                failed=$((failed + 1))
                echo "Retry failed: $(basename "$file_path") unknown"
                ;;
        esac
    done

    if [ "$dry_run" = true ]; then
        echo "Will process failed items: $matched"
        return 0
    fi

    echo "Scanned: $scanned"
    echo "Matched: $matched"
    echo "Recovered: $recovered"
    echo "Duplicates skipped: $duplicates"
    echo "Skipped: $skipped"
    echo "Failed: $failed"
}

cmd_cleanup() {
    local days=30
    local mode="safe"
    local limit=100

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -d|--days) days="$2"; shift ;;
            --aggressive) mode="aggressive" ;;
            --limit) limit="$2"; shift ;;
            -h|--help)
                print_command_usage "cleanup [-d days] [--limit count] [--aggressive]"
                echo "Default: safe cleanup, only removes low-priority temporary memories."
                echo ""
                echo "Options:"
                echo "  -d, --days        Age threshold in days (default: 30)"
                echo "  --limit           Max items to delete per run (default: 100)"
                echo "  --aggressive      Also remove expired and aged working memories"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    local deleted_count
    deleted_count=$(cleanup_memories "$mode" "$days" "$limit")

    if [[ ! "$deleted_count" =~ ^[0-9]+$ ]]; then
        echo "Error: Cleanup failed - $deleted_count"
        return 1
    fi

    if [ "$mode" = "aggressive" ]; then
        echo "Cleaned $deleted_count expired/aged memories (aggressive, days=$days, limit=$limit)"
    else
        echo "Cleaned $deleted_count low-priority temporary memories (safe, days=$days, limit=$limit)"
    fi
}

cmd_projects() {
    echo "=== Project List ==="
    echo ""
    list_projects
}

cmd_related_projects() {
    local project_path=""
    local limit=5
    local min_strength=70

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            --min-strength) min_strength="$2"; shift ;;
            -h|--help)
                print_command_usage "related-projects [-p project] [-l limit] [--min-strength score]"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    refresh_project_links "$project_path" >/dev/null 2>&1 || true

    local project_root
    project_root=$(resolve_project_root "$project_path")
    echo "=== Related Projects ==="
    echo "Primary: $project_root"
    echo ""
    printf "%-40s %-14s %-8s %s\n" "target_root" "link_type" "strength" "reason"
    list_related_projects "$project_root" "$limit" "$min_strength" | awk -F'|' '
    {
        printf "%-40s %-14s %-8s %s\n", $1, $2, $3, $4
    }'
}

cmd_link_projects() {
    local source_root=""
    local target_root=""
    local link_type="manual"
    local strength=95
    local reason="manual link"
    local bidirectional=1

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --type) link_type="$2"; shift ;;
            --strength) strength="$2"; shift ;;
            --reason) reason="$2"; shift ;;
            --one-way) bidirectional=0 ;;
            -h|--help)
                print_command_usage "link-projects <source_root> <target_root> [--type manual] [--strength 95] [--reason 文本] [--one-way]"
                return
                ;;
            *)
                if [ -z "$source_root" ]; then
                    source_root="$1"
                elif [ -z "$target_root" ]; then
                    target_root="$1"
                else
                    echo "Unknown argument: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [ -z "$source_root" ] || [ -z "$target_root" ]; then
        print_command_usage "link-projects <source_root> <target_root> [--type manual] [--strength 95] [--reason text] [--one-way]"
        return 1
    fi

    link_projects "$source_root" "$target_root" "$link_type" "$strength" "$reason" "$bidirectional"
    echo "Project link created: $source_root -> $target_root ($link_type, strength=$strength)"
    if [ "$bidirectional" = "1" ]; then
        echo "Bidirectional link also created"
    fi
}

cmd_unlink_projects() {
    local source_root=""
    local target_root=""
    local bidirectional=1

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --one-way) bidirectional=0 ;;
            -h|--help)
                print_command_usage "unlink-projects <source_root> <target_root> [--one-way]"
                return
                ;;
            *)
                if [ -z "$source_root" ]; then
                    source_root="$1"
                elif [ -z "$target_root" ]; then
                    target_root="$1"
                else
                    echo "Unknown argument: $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [ -z "$source_root" ] || [ -z "$target_root" ]; then
        print_command_usage "unlink-projects <source_root> <target_root> [--one-way]"
        return 1
    fi

    unlink_projects "$source_root" "$target_root" "$bidirectional"
    echo "Project link removed: $source_root -> $target_root"
    if [ "$bidirectional" = "1" ]; then
        echo "Bidirectional link also removed"
    fi
}

cmd_refresh_project_links() {
    local project_path=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -h|--help)
                print_command_usage "refresh-project-links [-p project]"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    refresh_project_links "$project_path"
    echo "Project links refreshed: $(resolve_project_root "$project_path")"
}

cmd_history() {
    local memory_id=""
    local limit=10
    local recent=false

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -m|--memory) memory_id="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            -r|--recent) recent=true; shift ;;
            -h|--help) show_help; return ;;
            *)
                # If no flag specified, treat as memory_id
                if [ -z "$memory_id" ]; then
                    memory_id="$1"
                fi
                ;;
        esac
        shift
    done

    if [ "$recent" = true ]; then
        echo "=== Recent Memory History ==="
        echo ""
        get_recent_history "$limit"
    elif [ -n "$memory_id" ]; then
        echo "=== History for $memory_id ==="
        echo ""
        get_memory_history "$memory_id" "$limit"
    else
        echo "=== Recent Memory History ==="
        echo ""
        get_recent_history "$limit"
    fi
}

cmd_timeline() {
    local anchor_id=""
    local depth_before=3
    local depth_after=3

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -a|--anchor) anchor_id="$2"; shift ;;
            -b|--before) depth_before="$2"; shift ;;
            -A|--after) depth_after="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    if [ -z "$anchor_id" ]; then
        print_command_usage "timeline -a <memory_id> [-b before] [-A after]"
        return 1
    fi

    echo "=== Timeline Context ==="
    echo "  Anchor: $anchor_id"
    echo "  Range: $depth_before / $depth_after"
    echo ""

    get_timeline "$anchor_id" "$depth_before" "$depth_after"
}

cmd_get() {
    local memory_ids=()

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help) show_help; return ;;
            *) memory_ids+=("$1") ;;
        esac
        shift
    done

    if [ ${#memory_ids[@]} -eq 0 ]; then
        print_command_usage "get <memory_id> [memory_id2] ..."
        return 1
    fi

    echo "=== Memory Details ==="
    echo ""

    for id in "${memory_ids[@]}"; do
        echo "--- $id ---"
        get_memory "$id"
        echo ""
    done
}

cmd_status() {
    echo "=== CC-Mem Status ==="
    echo ""
    echo "Database: $CCMEM_MEMORY_DB"
    if [ -f "$CCMEM_MEMORY_DB" ]; then
        local mem_count=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT COUNT(*) FROM memories;")
        local session_count=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT COUNT(*) FROM sessions;")
        local project_count=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT COUNT(*) FROM projects;")

        # Compatible with macOS and Linux du
        local db_size=""
        if du -h "$CCMEM_MEMORY_DB" &> /dev/null; then
            db_size=$(du -h "$CCMEM_MEMORY_DB" | cut -f1)
        elif du -k "$CCMEM_MEMORY_DB" &> /dev/null; then
            # macOS fallback
            local size_kb=$(du -k "$CCMEM_MEMORY_DB" | cut -f1)
            if [ "$size_kb" -lt 1024 ]; then
                db_size="${size_kb}K"
            else
                db_size="$((size_kb / 1024))M"
            fi
        else
            # Use stat 命令
            if stat -f%z "$CCMEM_MEMORY_DB" &> /dev/null; then
                local size_bytes=$(stat -f%z "$CCMEM_MEMORY_DB")
                db_size="$((size_bytes / 1024))K"
            elif stat -c%s "$CCMEM_MEMORY_DB" &> /dev/null; then
                local size_bytes=$(stat -c%s "$CCMEM_MEMORY_DB")
                db_size="$((size_bytes / 1024))K"
            else
                db_size="unknown"
            fi
        fi

        echo "  Memories: $mem_count"
        echo "  Sessions: $session_count"
        echo "  Projects: $project_count"
        echo "  DB size: $db_size"
    else
        echo "  Status: not initialized"
    fi
    echo ""

    print_failed_queue_summary
    echo ""
    print_recent_cleanup_summary
    echo ""

    echo "Config dir: $CONFIG_DIR"
    echo "Script dir: $SCRIPT_DIR"
}

cmd_stats() {
    local days=7
    local project_path=""
    local project_root=""
    local where_clause="timestamp_epoch >= CAST(strftime('%s', 'now', '-7 days') AS INTEGER)"
    local summary_row=""
    local mem_count=0
    local content_bytes=0
    local preview_bytes=0
    local durable_count=0
    local working_count=0
    local temporary_count=0
    local preview_ratio="0.0%"
    local durable_ratio="0.0%"
    local working_ratio="0.0%"
    local temporary_ratio="0.0%"
    local avg_per_day="0.0"
    local active_days=0
    local daily_rows=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -d|--days) days="$2"; shift ;;
            -p|--project) project_path="$2"; shift ;;
            -h|--help)
                print_command_usage "stats [--days n] [--project path]"
                echo "Show recent memory statistics"
                echo ""
                echo "Options:"
                echo "  -d, --days       Statistics for last N days (default: 7)"
                echo "  -p, --project    Only for specified project"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    if [[ ! "$days" =~ ^[0-9]+$ ]] || [ "$days" -le 0 ]; then
        echo "Error: days must be a positive integer"
        return 1
    fi

    where_clause="timestamp_epoch >= CAST(strftime('%s', 'now', '-$days days') AS INTEGER)"
    if [ -n "$project_path" ]; then
        project_root=$(resolve_project_root "$(resolve_effective_project_path "$project_path")")
        where_clause="$where_clause AND project_root = '$(sql_escape "$project_root")'"
    fi

    summary_row=$(sqlite3 -separator '|' "$CCMEM_MEMORY_DB" <<EOF
SELECT
  COUNT(*),
  COALESCE(SUM(LENGTH(content)), 0),
  COALESCE(SUM(LENGTH(content_preview)), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'durable' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'working' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'temporary' THEN 1 ELSE 0 END), 0)
FROM memories
WHERE $where_clause;
EOF
)

    mem_count=$(printf "%s" "$summary_row" | cut -d'|' -f1)
    content_bytes=$(printf "%s" "$summary_row" | cut -d'|' -f2)
    preview_bytes=$(printf "%s" "$summary_row" | cut -d'|' -f3)
    durable_count=$(printf "%s" "$summary_row" | cut -d'|' -f4)
    working_count=$(printf "%s" "$summary_row" | cut -d'|' -f5)
    temporary_count=$(printf "%s" "$summary_row" | cut -d'|' -f6)
    preview_ratio=$(format_ratio_percent "$preview_bytes" "$content_bytes")
    durable_ratio=$(format_ratio_percent "$durable_count" "$mem_count")
    working_ratio=$(format_ratio_percent "$working_count" "$mem_count")
    temporary_ratio=$(format_ratio_percent "$temporary_count" "$mem_count")
    avg_per_day=$(format_decimal "$mem_count" "$days")

    daily_rows=$(sqlite3 -separator '|' "$CCMEM_MEMORY_DB" <<EOF
SELECT
  date(datetime(timestamp_epoch, 'unixepoch', 'localtime')) AS day,
  COUNT(*),
  COALESCE(SUM(LENGTH(content)), 0),
  COALESCE(SUM(LENGTH(content_preview)), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'durable' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'working' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'temporary' THEN 1 ELSE 0 END), 0)
FROM memories
WHERE $where_clause
GROUP BY day
ORDER BY day DESC;
EOF
)

    if [ -n "$daily_rows" ]; then
        active_days=$(printf "%s\n" "$daily_rows" | grep -c . | tr -d ' ')
    fi

    echo "=== CC-Mem Stats ==="
    echo ""
    echo "Range: last ${days} days"
    echo "Project: ${project_root:-all projects}"
    echo ""
    echo "Overview:"
    echo "  Memories: $mem_count"
    echo "  Avg per day: $avg_per_day"
    echo "  Active days: $active_days/$days"
    echo "  Content bytes: $content_bytes"
    echo "  Preview bytes: $preview_bytes"
    echo "  Preview ratio: $preview_ratio"
    echo "  Distribution: durable=$durable_count working=$working_count temporary=$temporary_count"
    echo "  Ratio: durable=$durable_ratio working=$working_ratio temporary=$temporary_ratio"
    echo ""
    echo "Daily breakdown:"
    if [ -z "$daily_rows" ]; then
        echo "  (no data)"
        return
    fi

    echo "  Date | Count | Preview ratio | durable | working | temporary"
    printf "%s\n" "$daily_rows" | while IFS='|' read -r day day_count day_content day_preview day_durable day_working day_temporary; do
        echo "  $day | $day_count | $(format_ratio_percent "$day_preview" "$day_content") | $day_durable | $day_working | $day_temporary"
    done
}

cmd_inject_context() {
    local project_path=""
    local limit
    limit=$(get_injection_session_start_limit)

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            -h|--help)
                print_command_usage "inject-context [-p project] [-l limit]"
                echo "Generate session start context injection"
                echo ""
                echo "Options:"
                echo "  -p, --project    Project path (default: current directory)"
                echo "  -l, --limit      High-value memory count (default from config, fallback 3)"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    generate_injection_context "$project_path" "$limit"
}

main() {
    load_config

    local command="${1:-help}"
    shift || true

    case $command in
        init|help|--help|-h)
            ;;
        *)
            ensure_db_ready
            ;;
    esac

    case $command in
        init)
            init_db
            ;;
        capture)
            cmd_capture "$@"
            ;;
        search)
            cmd_search "$@"
            ;;
        recall)
            cmd_recall "$@"
            ;;
        timeline)
            cmd_timeline "$@"
            ;;
        get)
            cmd_get "$@"
            ;;
        history)
            cmd_history "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        export)
            cmd_export "$@"
            ;;
        retry)
            cmd_retry "$@"
            ;;
        projects)
            cmd_projects
            ;;
        related-projects)
            cmd_related_projects "$@"
            ;;
        link-projects)
            cmd_link_projects "$@"
            ;;
        unlink-projects)
            cmd_unlink_projects "$@"
            ;;
        refresh-project-links)
            cmd_refresh_project_links "$@"
            ;;
        cleanup)
            cmd_cleanup "$@"
            ;;
        status)
            cmd_status
            ;;
        stats)
            cmd_stats "$@"
            ;;
        inject-context)
            cmd_inject_context "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Run 'ccmem-cli.sh help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
