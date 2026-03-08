#!/bin/bash
# CC-Mem 一次性旧库迁移脚本
#
# 用途：
# - 将旧版数据库迁移到当前 1.5.1 schema
# - 回填 project_root / source / memory_kind / auto_inject_policy
# - 将 memories.timestamp 收敛为 timestamp_epoch
#
# 迁移完成后，正式运行链路不再包含兼容性迁移代码。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/sqlite.sh"

DO_BACKUP=true
SELF_TEST=false
DB_PATH="$(get_memory_db_path)"

show_help() {
    cat <<EOF
CC-Mem 一次性旧库迁移脚本

用法：
  $0 [选项]

选项：
  --db <path>      指定数据库路径（默认读取 config/config.json）
  --no-backup      不备份数据库
  --self-test      运行脚本自检
  -h, --help       显示帮助

说明：
  该脚本用于一次性将旧版 memory.db 迁移到当前 schema。
  迁移成功后，可删除本脚本；正式运行链路不再负责旧库兼容。
EOF
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --db)
            DB_PATH="$2"
            shift
            ;;
        --no-backup)
            DO_BACKUP=false
            ;;
        --self-test)
            SELF_TEST=true
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知选项：$1" >&2
            exit 1
            ;;
    esac
    shift
done

ensure_column_exists() {
    local table_name="$1"
    local column_name="$2"
    local column_def="$3"
    local exists

    exists=$(sqlite3 "$DB_PATH" "PRAGMA table_info($table_name);" | awk -F'|' -v col="$column_name" '$2 == col { print 1 }')
    if [ -z "$exists" ]; then
        sqlite3 "$DB_PATH" "ALTER TABLE $table_name ADD COLUMN $column_def;"
    fi
}

backfill_project_roots() {
    local path=""
    local root=""
    local path_escaped=""
    local root_escaped=""

    sqlite3 -noheader "$DB_PATH" "SELECT DISTINCT project_path FROM memories WHERE project_path IS NOT NULL AND project_path != '' UNION SELECT DISTINCT project_path FROM sessions WHERE project_path IS NOT NULL AND project_path != '';" | while IFS= read -r path; do
        [ -z "$path" ] && continue
        root=$(resolve_project_root "$path")
        path_escaped=$(sql_escape "$path")
        root_escaped=$(sql_escape "$root")

        sqlite3 "$DB_PATH" <<EOF
UPDATE memories
SET project_root = '$root_escaped'
WHERE project_path = '$path_escaped' AND (project_root IS NULL OR project_root = '' OR project_root = project_path);

UPDATE sessions
SET project_root = '$root_escaped'
WHERE project_path = '$path_escaped' AND (project_root IS NULL OR project_root = '' OR project_root = project_path);
EOF
    done
}

backfill_memory_metadata() {
    sqlite3 "$DB_PATH" <<'EOF'
UPDATE memories
SET source = CASE
    WHEN source IS NOT NULL AND source != '' AND source != 'manual' THEN source
    WHEN tags LIKE '%final-response%' THEN 'stop_final_response'
    WHEN tags LIKE '%session-end%' THEN 'session_end'
    WHEN tags LIKE '%stop%' THEN 'stop_summary'
    WHEN tags LIKE '%auto-captured%' THEN 'post_tool_use'
    ELSE COALESCE(NULLIF(source, ''), 'manual')
END;

UPDATE memories
SET memory_kind = CASE
    WHEN source = 'manual' AND category IN ('decision', 'solution', 'pattern') THEN 'durable'
    WHEN source IN ('user_prompt_submit', 'stop_summary') THEN 'working'
    WHEN source IN ('stop_final_response', 'post_tool_use', 'session_end') THEN 'temporary'
    ELSE 'working'
END;

UPDATE memories
SET auto_inject_policy = CASE
    WHEN source = 'manual' AND category IN ('decision', 'solution', 'pattern') THEN 'always'
    WHEN source IN ('manual', 'user_prompt_submit', 'stop_summary') THEN 'conditional'
    WHEN source = 'stop_final_response' THEN 'manual_only'
    WHEN source IN ('post_tool_use', 'session_end') THEN 'never'
    ELSE 'conditional'
END;

UPDATE memories
SET expires_at = CASE
    WHEN expires_at IS NOT NULL AND expires_at != '' THEN expires_at
    WHEN source = 'stop_summary' AND timestamp_epoch IS NOT NULL THEN datetime(timestamp_epoch, 'unixepoch', '+14 days')
    WHEN source IN ('post_tool_use', 'session_end') AND timestamp_epoch IS NOT NULL THEN datetime(timestamp_epoch, 'unixepoch', '+3 days')
    WHEN source = 'stop_final_response' AND timestamp_epoch IS NOT NULL THEN datetime(timestamp_epoch, 'unixepoch', '+7 days')
    ELSE NULL
END;
EOF
}

migrate_memories_table_to_epoch_only() {
    local has_timestamp_column=""
    has_timestamp_column=$(sqlite3 "$DB_PATH" "PRAGMA table_info(memories);" | awk -F'|' '$2 == "timestamp" { print 1 }')
    [ -z "$has_timestamp_column" ] && return 0

    sqlite3 "$DB_PATH" <<'EOF'
UPDATE memories
SET timestamp_epoch = COALESCE(
    NULLIF(timestamp_epoch, 0),
    CAST(strftime('%s', timestamp) AS INTEGER),
    CAST(strftime('%s', 'now') AS INTEGER)
)
WHERE timestamp_epoch IS NULL OR timestamp_epoch = 0;

BEGIN TRANSACTION;

CREATE TABLE memories_new (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    timestamp_epoch INTEGER,
    project_path TEXT,
    project_root TEXT,
    category TEXT CHECK(category IN ('decision', 'solution', 'pattern', 'debug', 'context')),
    source TEXT DEFAULT 'manual',
    classification_confidence INTEGER,
    classification_reason TEXT,
    classification_source TEXT,
    classification_version TEXT,
    memory_kind TEXT DEFAULT 'working',
    auto_inject_policy TEXT DEFAULT 'conditional',
    expires_at TEXT,
    content_hash TEXT,
    concepts TEXT,
    content TEXT NOT NULL,
    content_preview TEXT,
    summary TEXT,
    tags TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO memories_new (
    id, session_id, timestamp_epoch, project_path, project_root, category, source,
    classification_confidence, classification_reason, classification_source, classification_version,
    memory_kind, auto_inject_policy, expires_at, content_hash, concepts, content,
    content_preview, summary, tags, created_at, updated_at
)
SELECT
    id, session_id, timestamp_epoch, project_path, project_root, category, source,
    classification_confidence, classification_reason, classification_source, classification_version,
    memory_kind, auto_inject_policy, expires_at, content_hash, concepts, content,
    content_preview, summary, tags, created_at, updated_at
FROM memories;

DROP TABLE memories;
ALTER TABLE memories_new RENAME TO memories;

COMMIT;
EOF
}

main() {
    if [ ! -f "$DB_PATH" ]; then
        echo "错误：数据库文件不存在：$DB_PATH" >&2
        exit 1
    fi

    local has_memories=""
    has_memories=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='memories';" 2>/dev/null || true)
    if [ "$has_memories" != "memories" ]; then
        echo "错误：数据库中不存在 memories 表，无法迁移旧库" >&2
        exit 1
    fi

    if [ "$DO_BACKUP" = true ]; then
        local backup="${DB_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$DB_PATH" "$backup"
        echo "已备份数据库到：$backup"
    fi

    ensure_column_exists "memories" "source" "source TEXT DEFAULT 'manual'"
    ensure_column_exists "memories" "classification_confidence" "classification_confidence INTEGER"
    ensure_column_exists "memories" "classification_reason" "classification_reason TEXT"
    ensure_column_exists "memories" "classification_source" "classification_source TEXT"
    ensure_column_exists "memories" "classification_version" "classification_version TEXT"
    ensure_column_exists "memories" "memory_kind" "memory_kind TEXT DEFAULT 'working'"
    ensure_column_exists "memories" "auto_inject_policy" "auto_inject_policy TEXT DEFAULT 'conditional'"
    ensure_column_exists "memories" "project_root" "project_root TEXT"
    ensure_column_exists "memories" "expires_at" "expires_at TEXT"
    ensure_column_exists "memories" "content_hash" "content_hash TEXT"
    ensure_column_exists "memories" "concepts" "concepts TEXT"
    ensure_column_exists "memories" "content_preview" "content_preview TEXT"
    ensure_column_exists "sessions" "project_root" "project_root TEXT"

    migrate_memories_table_to_epoch_only

    sqlite3 "$DB_PATH" <<'EOF'
CREATE INDEX IF NOT EXISTS idx_sessions_project_root ON sessions(project_root);

CREATE TABLE IF NOT EXISTS project_links (
    id TEXT PRIMARY KEY,
    source_root TEXT NOT NULL,
    target_root TEXT NOT NULL,
    link_type TEXT NOT NULL,
    strength INTEGER NOT NULL DEFAULT 50,
    reason TEXT,
    is_manual INTEGER NOT NULL DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_project_links_pair ON project_links(source_root, target_root);
CREATE INDEX IF NOT EXISTS idx_project_links_source ON project_links(source_root, strength DESC);
CREATE INDEX IF NOT EXISTS idx_project_links_target ON project_links(target_root);

UPDATE memories
SET source = COALESCE(NULLIF(source, ''), 'manual'),
    memory_kind = COALESCE(NULLIF(memory_kind, ''), 'working'),
    auto_inject_policy = COALESCE(NULLIF(auto_inject_policy, ''), 'conditional'),
    project_root = COALESCE(NULLIF(project_root, ''), project_path)
WHERE source IS NULL OR source = ''
   OR memory_kind IS NULL OR memory_kind = ''
   OR auto_inject_policy IS NULL OR auto_inject_policy = ''
   OR project_root IS NULL OR project_root = '';

UPDATE sessions
SET project_root = COALESCE(NULLIF(project_root, ''), project_path)
WHERE project_root IS NULL OR project_root = '';

UPDATE memories
SET classification_source = CASE
    WHEN classification_source IS NOT NULL AND classification_source != '' THEN classification_source
    WHEN source = 'manual' THEN 'manual'
    ELSE NULL
END,
classification_version = CASE
    WHEN classification_version IS NOT NULL AND classification_version != '' THEN classification_version
    WHEN source = 'manual' THEN 'manual'
    ELSE NULL
END,
classification_confidence = CASE
    WHEN classification_confidence IS NOT NULL THEN classification_confidence
    WHEN source = 'manual' THEN 100
    ELSE NULL
END,
classification_reason = CASE
    WHEN classification_reason IS NOT NULL AND classification_reason != '' THEN classification_reason
    WHEN source = 'manual' THEN 'user-specified'
    ELSE NULL
END;
EOF

    backfill_project_roots
    backfill_memory_metadata
    ensure_memories_runtime_objects

    echo "旧库迁移完成：$DB_PATH"
}

run_self_test() {
    local test_dir
    local test_db
    local columns
    local result
    local epoch
    local old_db="$DB_PATH"
    local old_backup="$DO_BACKUP"

    test_dir=$(mktemp -d /tmp/cc-mem-migrate-test.XXXXXX)
    test_db="$test_dir/legacy-memory.db"

    sqlite3 "$test_db" <<'EOF'
CREATE TABLE memories (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    timestamp_epoch INTEGER,
    project_path TEXT,
    category TEXT,
    content TEXT NOT NULL,
    content_preview TEXT,
    summary TEXT,
    tags TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    start_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    end_time DATETIME,
    project_path TEXT,
    message_count INTEGER DEFAULT 0,
    summary TEXT,
    status TEXT DEFAULT 'active'
);

INSERT INTO memories (
    id, session_id, timestamp, timestamp_epoch, project_path, category,
    content, content_preview, summary, tags, created_at, updated_at
)
VALUES (
    'mem_legacy_backfill', 'legacy_session', '2026-03-07 07:39:35', NULL, '/legacy/project', 'context',
    '旧 stop 记录', '旧 stop 记录', '旧 stop 摘要', 'stop,auto-captured',
    '2026-03-07 07:39:35', '2026-03-07 07:39:35'
);

INSERT INTO sessions (id, project_path, status)
VALUES ('legacy_session', '/legacy/project', 'active');
EOF

    DB_PATH="$test_db"
    DO_BACKUP=false
    main

    columns=$(sqlite3 "$test_db" "PRAGMA table_info(memories);" | cut -d'|' -f2 | tr '\n' ' ')
    [[ "$columns" == *" timestamp "* ]] && { echo "SELF-TEST FAILED: 迁移后仍保留旧 timestamp 列" >&2; return 1; }

    epoch=$(sqlite3 "$test_db" "SELECT timestamp_epoch FROM memories WHERE id='mem_legacy_backfill';")
    [[ -n "$epoch" && "$epoch" -gt 0 ]] || { echo "SELF-TEST FAILED: 未回填 timestamp_epoch" >&2; return 1; }

    result=$(sqlite3 "$test_db" "SELECT source, memory_kind, auto_inject_policy, project_root, expires_at FROM memories WHERE id='mem_legacy_backfill';")
    [[ "$result" == *"stop_summary"* ]] || { echo "SELF-TEST FAILED: 未回填 source=stop_summary" >&2; return 1; }
    [[ "$result" == *"working"* ]] || { echo "SELF-TEST FAILED: 未回填 memory_kind=working" >&2; return 1; }
    [[ "$result" == *"conditional"* ]] || { echo "SELF-TEST FAILED: 未回填 auto_inject_policy=conditional" >&2; return 1; }
    [[ "$result" == *"/legacy/project"* ]] || { echo "SELF-TEST FAILED: 未回填 project_root" >&2; return 1; }
    [[ "$result" == *"-"* || "$result" == *":"* ]] || { echo "SELF-TEST FAILED: 未回填 expires_at" >&2; return 1; }

    sqlite3 "$test_db" "SELECT name FROM sqlite_master WHERE type='table' AND name='project_links';" | grep -q "project_links" \
        || { echo "SELF-TEST FAILED: 未创建 project_links 表" >&2; return 1; }

    DB_PATH="$old_db"
    DO_BACKUP="$old_backup"
    echo "SELF-TEST PASSED"
}

if [ "$SELF_TEST" = true ]; then
    run_self_test
    exit 0
fi

main "$@"
