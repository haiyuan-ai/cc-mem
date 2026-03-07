#!/bin/bash

get_recent_project_memories() {
    local project_path="$1"
    local limit="${2:-12}"

    if [ -z "$project_path" ]; then
        return
    fi

    local project_root
    local project_root_escaped
    project_root=$(resolve_project_root "$project_path")
    project_root_escaped=$(sql_escape "$project_root")

    sqlite3 -separator '|' "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, summary, tags, concepts, source, memory_kind, auto_inject_policy
FROM memories
WHERE project_root = '$project_root_escaped'
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
}

rank_memory_for_sessionstart() {
    local category="$1"
    local tags="$2"
    local concepts="$3"

    local score=0

    case "$category" in
        "decision") score=$((score + 100)) ;;
        "debug") score=$((score + 90)) ;;
        "solution") score=$((score + 80)) ;;
        "pattern") score=$((score + 50)) ;;
        "context") score=$((score + 20)) ;;
    esac

    if [ -n "$concepts" ]; then
        score=$((score + 10))
    fi

    echo "$score"
}

select_sessionstart_memories() {
    local project_path="$1"
    local limit="${2:-3}"
    local project_root
    local project_root_escaped

    project_root=$(resolve_project_root "$project_path")
    project_root_escaped=$(sql_escape "$project_root")

    sqlite3 -separator '|' "$MEMORY_DB" <<EOF | awk -F'|' -v limit="$limit" '
BEGIN { count = 0 }
{
    summary = $4
    if (summary == "" || seen[summary]) next
    seen[summary] = 1
    print $0
    count++
    if (count >= limit) exit
}'
SELECT id, timestamp, category, summary, tags, concepts, source, memory_kind, auto_inject_policy
FROM memories
WHERE project_root = '$project_root_escaped'
  AND summary IS NOT NULL
  AND summary != ''
  AND auto_inject_policy IN ('always', 'conditional')
  AND (expires_at IS NULL OR expires_at = '' OR expires_at > datetime('now'))
ORDER BY
  CASE auto_inject_policy
    WHEN 'always' THEN 4
    WHEN 'conditional' THEN 3
    WHEN 'manual_only' THEN 2
    ELSE 1
  END DESC,
  CASE memory_kind
    WHEN 'durable' THEN 3
    WHEN 'working' THEN 2
    ELSE 1
  END DESC,
  CASE category
    WHEN 'decision' THEN 100
    WHEN 'debug' THEN 90
    WHEN 'solution' THEN 80
    WHEN 'pattern' THEN 50
    ELSE 20
  END DESC,
  CASE source
    WHEN 'manual' THEN 5
    WHEN 'stop_summary' THEN 4
    WHEN 'user_prompt_submit' THEN 3
    ELSE 1
  END DESC,
  timestamp_epoch DESC
LIMIT 20;
EOF
}

select_related_sessionstart_memories() {
    local project_path="$1"
    local limit="${2:-1}"
    local related_roots
    local related_root=""
    local related_root_escaped

    related_roots=$(resolve_related_projects "$project_path" "$limit")
    related_root=$(printf "%s\n" "$related_roots" | head -1)
    if [ -z "$related_root" ]; then
        return
    fi

    related_root_escaped=$(sql_escape "$related_root")

    sqlite3 -separator '|' "$MEMORY_DB" <<EOF | awk -F'|' '
{
    if ($4 == "" || seen[$4]) next
    seen[$4] = 1
    print $0
}'
SELECT id, timestamp, category, summary, tags, concepts, source, memory_kind, auto_inject_policy, project_root
FROM memories
WHERE project_root = '$related_root_escaped'
  AND summary IS NOT NULL
  AND summary != ''
  AND auto_inject_policy IN ('always', 'conditional')
  AND (expires_at IS NULL OR expires_at = '' OR expires_at > datetime('now'))
ORDER BY
  CASE auto_inject_policy
    WHEN 'always' THEN 4
    WHEN 'conditional' THEN 3
    WHEN 'manual_only' THEN 2
    ELSE 1
  END DESC,
  CASE memory_kind
    WHEN 'durable' THEN 3
    WHEN 'working' THEN 2
    ELSE 1
  END DESC,
  CASE category
    WHEN 'decision' THEN 100
    WHEN 'debug' THEN 90
    WHEN 'solution' THEN 80
    WHEN 'pattern' THEN 50
    ELSE 20
  END DESC,
  timestamp_epoch DESC
LIMIT $limit;
EOF
}

get_last_stop_summary() {
    local project_path="$1"

    if [ -z "$project_path" ]; then
        return
    fi

    local project_root
    local project_root_escaped
    project_root=$(resolve_project_root "$project_path")
    project_root_escaped=$(sql_escape "$project_root")

    sqlite3 "$MEMORY_DB" <<EOF
SELECT summary FROM sessions
WHERE (project_root = '$project_root_escaped'
   OR project_path = '$(sql_escape "$project_path")'
   OR project_path LIKE '$(sql_escape "$project_path")/%')
  AND status = 'stopped'
  AND summary IS NOT NULL
  AND summary != ''
ORDER BY end_time DESC
LIMIT 1;
EOF
}

get_timeline_hint_candidates() {
    local project_path="$1"
    local limit="${2:-4}"
    local project_root
    local project_root_escaped

    project_root=$(resolve_project_root "$project_path")
    project_root_escaped=$(sql_escape "$project_root")

    sqlite3 -separator '|' "$MEMORY_DB" <<EOF
SELECT timestamp, category, summary
FROM memories
WHERE project_root = '$project_root_escaped'
  AND summary IS NOT NULL
  AND summary != ''
  AND auto_inject_policy IN ('always', 'conditional')
  AND (expires_at IS NULL OR expires_at = '' OR expires_at > datetime('now'))
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
}

should_include_timeline_hint() {
    local project_path="$1"
    local candidates
    local debug_count=0
    local categories=""
    local last_session=""

    candidates=$(get_timeline_hint_candidates "$project_path" 4)
    [ -z "$candidates" ] && return 1

    debug_count=$(printf "%s\n" "$candidates" | grep '|debug|' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$debug_count" -ge 2 ]; then
        return 0
    fi

    last_session=$(get_last_stop_summary "$project_path")
    if printf "%s" "$last_session" | grep -Eq '继续|排查|回退|修复|验证'; then
        return 0
    fi

    categories=$(printf "%s\n" "$candidates" | cut -d'|' -f2 | paste -sd ',' -)
    if printf "%s" "$categories" | grep -Eq 'debug,solution|solution,debug|decision,pattern|pattern,decision'; then
        return 0
    fi

    return 1
}

generate_timeline_hint() {
    local project_path="$1"
    local limit="${2:-3}"

    get_timeline_hint_candidates "$project_path" "$limit" | awk -F'|' '
    {
        rows[NR] = sprintf("- [%s] %s", $2, $3)
    }
    END {
        for (i = NR; i >= 1; i--) {
            print rows[i]
        }
    }'
}

query_recall_memories_for_root() {
    local project_root="$1"
    local query="$2"
    local limit="${3:-3}"
    local query_escaped
    local project_root_escaped

    project_root_escaped=$(sql_escape "$project_root")
    query_escaped=$(sql_escape "$query")

    if contains_cjk "$query"; then
        sqlite3 -separator '|' "$MEMORY_DB" <<EOF
SELECT id, category, summary, tags, source, project_root
FROM memories
WHERE project_root = '$project_root_escaped'
  AND auto_inject_policy IN ('always', 'conditional')
  AND (expires_at IS NULL OR expires_at = '' OR expires_at > datetime('now'))
  AND (
      rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')
      OR content LIKE '%${query_escaped}%'
      OR summary LIKE '%${query_escaped}%'
      OR tags LIKE '%${query_escaped}%'
      OR concepts LIKE '%${query_escaped}%'
  )
ORDER BY
  CASE auto_inject_policy WHEN 'always' THEN 4 WHEN 'conditional' THEN 3 ELSE 1 END DESC,
  CASE memory_kind WHEN 'durable' THEN 3 WHEN 'working' THEN 2 ELSE 1 END DESC,
  timestamp_epoch DESC
LIMIT $limit;
EOF
        return
    fi

    sqlite3 -separator '|' "$MEMORY_DB" <<EOF
SELECT id, category, summary, tags, source, project_root
FROM memories
WHERE project_root = '$project_root_escaped'
  AND auto_inject_policy IN ('always', 'conditional')
  AND (expires_at IS NULL OR expires_at = '' OR expires_at > datetime('now'))
  AND (
      rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')
      OR concepts LIKE '%${query_escaped}%'
  )
ORDER BY
  CASE auto_inject_policy WHEN 'always' THEN 4 WHEN 'conditional' THEN 3 ELSE 1 END DESC,
  CASE memory_kind WHEN 'durable' THEN 3 WHEN 'working' THEN 2 ELSE 1 END DESC,
  timestamp_epoch DESC
LIMIT $limit;
EOF
}

select_query_recall_memories() {
    local project_path="$1"
    local query="$2"
    local limit="${3:-3}"
    local project_root
    local primary_memories=""
    local related_root=""
    local related_memories=""
    local current_count=0
    local remaining=0

    if [ -z "$query" ]; then
        return
    fi

    project_root=$(resolve_project_root "$project_path")
    primary_memories=$(query_recall_memories_for_root "$project_root" "$query" "$limit")
    current_count=$(count_result_rows "$primary_memories")

    if [ "$current_count" -lt "$limit" ]; then
        remaining=$((limit - current_count))
        related_root=$(resolve_related_projects "$project_path" 1 | head -1)
        if [ -n "$related_root" ] && [ "$related_root" != "$project_root" ]; then
            related_memories=$(query_recall_memories_for_root "$related_root" "$query" "$remaining")
        fi
    fi

    {
        printf "%s\n" "$primary_memories"
        printf "%s\n" "$related_memories"
    } | awk -F'|' -v limit="$limit" '
BEGIN { count = 0 }
{
    if ($0 == "") next
    if (seen[$3]) next
    seen[$3] = 1
    print $0
    count++
    if (count >= limit) exit
}'
}

generate_query_recall_context() {
    local project_path="$1"
    local query="$2"
    local limit="${3:-3}"
    local recall_memories

    recall_memories=$(select_query_recall_memories "$project_path" "$query" "$limit")
    if [ -z "$recall_memories" ]; then
        return
    fi

    echo "<cc-mem-recall>"
    echo "Relevant project context for the current request (use only if relevant):"
    echo "$recall_memories" | awk -F'|' -v current_root="$(resolve_project_root "$project_path")" '
    {
        if (seen[$3]) next
        seen[$3] = 1
        if ($6 != "" && $6 != current_root) {
            printf("- [%s] %s (related: %s)\n", $2, $3, $6)
        } else {
            printf("- [%s] %s\n", $2, $3)
        }
    }'
    echo "</cc-mem-recall>"
}

generate_injection_context() {
    local project_path="$1"
    local limit="${2:-3}"

    if [ -z "$project_path" ]; then
        project_path="$(pwd)"
    fi

    local timestamp
    timestamp=$(format_iso8601)

    local high_value_memories
    high_value_memories=$(select_sessionstart_memories "$project_path" "$limit")
    local related_memories
    related_memories=$(select_related_sessionstart_memories "$project_path" 1)
    local last_session
    last_session=$(get_last_stop_summary "$project_path")

    cat <<EOF
<cc-mem-context>
Project: $(resolve_project_root "$project_path")
Updated: $timestamp

Current Focus
EOF

    if [ -n "$high_value_memories" ]; then
        local main_category
        main_category=$(echo "$high_value_memories" | head -1 | cut -d'|' -f3)
        echo "- 最近工作集中在：${main_category:-项目开发}"
        echo "- 当前上下文重点：查看下方高价值记忆"
    else
        echo "- 暂无历史记忆记录"
        echo "- 建议先进行工作，记忆会自动捕获"
    fi

    echo ""
    echo "Recent High-Value Memory"

    if [ -n "$high_value_memories" ]; then
        local i=1
        echo "$high_value_memories" | while IFS='|' read -r id timestamp category summary tags concepts source memory_kind auto_inject_policy; do
            echo "$i. [$category] $summary"
            if [ -n "$tags" ]; then
                echo "   tags: $tags"
            fi
            i=$((i + 1))
        done
    else
        echo "（无）"
    fi

    if [ -n "$related_memories" ]; then
        echo ""
        echo "Related Project Memory"
        echo "$related_memories" | while IFS='|' read -r id timestamp category summary tags concepts source memory_kind auto_inject_policy related_root; do
            echo "- [$category] $summary"
            echo "  related project: $related_root"
        done
    fi

    echo ""
    echo "Last Session"

    if [ -n "$last_session" ]; then
        echo "- stopped at: $last_session"
        echo "- next likely step: 继续当前工作流"
    else
        echo "- 无最近会话记录"
    fi

    if should_include_timeline_hint "$project_path"; then
        echo ""
        echo "Recent Timeline Hint"
        generate_timeline_hint "$project_path" 3
    fi

    echo ""
    echo "If more detail is needed"
    echo "- search: 查相关关键词"
    echo "- timeline: 看某条记忆前后脉络"
    echo "- get: 查看单条完整内容"
    echo "</cc-mem-context>"
}
