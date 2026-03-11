#!/bin/bash
# SQLite 操作函数库

# Git for Windows 兼容性处理
if [[ "$(uname -s)" == "MSYS"* ]] || [[ "$(uname -s)" == "MINGW"* ]]; then
    # Git Bash 环境，使用 Windows 路径风格
    if [ -n "$USERPROFILE" ]; then
        HOME="${USERPROFILE}"
    fi
fi

SQLITE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SQLITE_LIB_DIR/config.sh"
apply_runtime_config

# 转义 SQL 字符串中的单引号。
sql_escape() {
    local value="$1"
    printf "%s" "$value" | sed "s/'/''/g"
}

# 转义 LIKE 子句中的通配符（%、_、\），防止用户输入被解释为通配符。
# 使用时需在 SQL 中添加 ESCAPE '\'。
sql_escape_like() {
    local value="$1"
    printf "%s" "$value" | sed "s/'/''/g" | sed 's/\\/\\\\/g; s/%/\\%/g; s/_/\\_/g'
}

# 检测查询中是否包含 CJK 字符，用于决定是否启用 LIKE 回退。
contains_cjk() {
    local value="$1"
    [[ "$value" =~ [一-龥] ]]
}

# 去掉自动注入的上下文块，避免被再次存回记忆库。
strip_injected_context_blocks() {
    local content="$1"

    if [ -z "$content" ]; then
        echo ""
        return
    fi

    if command -v perl >/dev/null 2>&1; then
        printf "%s" "$content" | perl -0777 -pe 's/<cc-mem-context>[\s\S]*?<\/cc-mem-context>//g; s/<cc-mem-recall>[\s\S]*?<\/cc-mem-recall>//g;'
        return
    fi

    printf "%s\n" "$content" | awk '
    /<cc-mem-context>/ { skip=1; next }
    /<\/cc-mem-context>/ { skip=0; next }
    /<cc-mem-recall>/ { skip=1; next }
    /<\/cc-mem-recall>/ { skip=0; next }
    !skip { print }
    '
}

normalize_preview_text() {
    local content="$1"
    local normalized=""

    normalized=$(printf "%s" "$content" | tr '\r\n\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')
    printf "%s" "$normalized"
}

truncate_preview_text() {
    local content="$1"
    local limit="${2:-200}"

    if [ "${#content}" -le "$limit" ]; then
        printf "%s" "$content"
    else
        printf "%s..." "${content:0:$limit}"
    fi
}

extract_signature_preview() {
    local content="$1"
    local signatures=""

    signatures=$(printf "%s\n" "$content" | grep -Eim 12 '^\[FILE_CHANGE\]|^\[BASH\]|error|errors|fail|failed|bug|fix|fixed|resolved|workaround|https?://|v[0-9]+(\.[0-9]+)*|version|trace|root cause' || true)
    if [ -z "$signatures" ]; then
        signatures="$content"
    fi

    normalize_preview_text "$signatures"
}

generate_content_preview() {
    local content="$1"
    local memory_kind="$2"
    local normalized=""
    local preview=""

    normalized=$(normalize_preview_text "$content")

    case "$memory_kind" in
        durable)
            preview=$(truncate_preview_text "$normalized" "$(get_preview_limit_for_kind durable)")
            ;;
        temporary)
            preview=$(extract_signature_preview "$content")
            preview=$(truncate_preview_text "$preview" "$(get_preview_limit_for_kind temporary)")
            ;;
        working|*)
            preview=$(truncate_preview_text "$normalized" "$(get_preview_limit_for_kind working)")
            ;;
    esac

    printf "%s" "$preview"
}

# 解析稳定的项目根路径，优先使用 git root。
resolve_project_root() {
    local project_path="$1"
    local git_root=""

    if [ -z "$project_path" ]; then
        project_path="$(pwd)"
    fi

    if [ -d "$project_path" ] && command -v git >/dev/null 2>&1; then
        git_root=$(git -C "$project_path" rev-parse --show-toplevel 2>/dev/null || true)
    fi

    if [ -n "$git_root" ]; then
        echo "$git_root"
    else
        echo "$project_path"
    fi
}

resolve_git_common_dir() {
    local project_path="$1"
    local common_dir=""

    if [ -z "$project_path" ] || [ ! -d "$project_path" ] || ! command -v git >/dev/null 2>&1; then
        return
    fi

    common_dir=$(git -C "$project_path" rev-parse --git-common-dir 2>/dev/null || true)
    [ -z "$common_dir" ] && return

    if [[ "$common_dir" = /* ]]; then
        [ -d "$common_dir" ] && (cd "$common_dir" 2>/dev/null && pwd)
        return
    fi

    (cd "$project_path" 2>/dev/null && cd "$common_dir" 2>/dev/null && pwd)
}

memory_display_timestamp_sql() {
    echo "datetime(timestamp_epoch, 'unixepoch', 'localtime')"
}

ensure_memories_runtime_objects() {
    # 创建索引（幂等操作）
    sqlite3 "$CCMEM_MEMORY_DB" <<'EOF'
CREATE INDEX IF NOT EXISTS idx_memories_content_hash ON memories(content_hash);
CREATE INDEX IF NOT EXISTS idx_memories_content_hash_scope ON memories(content_hash, project_root);
CREATE INDEX IF NOT EXISTS idx_memories_session ON memories(session_id);
CREATE INDEX IF NOT EXISTS idx_memories_project ON memories(project_path);
CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category);
CREATE INDEX IF NOT EXISTS idx_memories_tags ON memories(tags);
CREATE INDEX IF NOT EXISTS idx_memories_timestamp_epoch ON memories(timestamp_epoch DESC);
CREATE INDEX IF NOT EXISTS idx_memories_source ON memories(source);
CREATE INDEX IF NOT EXISTS idx_memories_memory_kind ON memories(memory_kind);
CREATE INDEX IF NOT EXISTS idx_memories_auto_inject_policy ON memories(auto_inject_policy);
CREATE INDEX IF NOT EXISTS idx_memories_project_root ON memories(project_root);
CREATE INDEX IF NOT EXISTS idx_memories_expires_at ON memories(expires_at);
EOF

    # 检查 FTS 表和触发器是否已存在，避免每次调用都 DROP + rebuild
    local fts_exists
    local trigger_exists
    fts_exists=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='memories_fts';" 2>/dev/null || echo "0")
    trigger_exists=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT count(*) FROM sqlite_master WHERE type='trigger' AND name='memories_ai';" 2>/dev/null || echo "0")

    if [ "$fts_exists" = "1" ] && [ "$trigger_exists" = "1" ]; then
        return
    fi

    # FTS 表或触发器不存在，需要完整创建
    sqlite3 "$CCMEM_MEMORY_DB" <<'EOF'
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    content,
    summary,
    tags,
    content='memories',
    content_rowid='rowid'
);

CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, content, summary, tags)
    VALUES (NEW.rowid, NEW.content, NEW.summary, NEW.tags);
END;

CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content, summary, tags)
    VALUES ('delete', OLD.rowid, OLD.content, OLD.summary, OLD.tags);
END;

CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content, summary, tags)
    VALUES ('delete', OLD.rowid, OLD.content, OLD.summary, OLD.tags);
    INSERT INTO memories_fts(rowid, content, summary, tags)
    VALUES (NEW.rowid, NEW.content, NEW.summary, NEW.tags);
END;
EOF

    # 只在 FTS 表刚创建时执行 rebuild
    sqlite3 "$CCMEM_MEMORY_DB" "INSERT INTO memories_fts(memories_fts) VALUES('rebuild');" 2>/dev/null || true
}

# 强制重建 FTS 索引（供 init 和 repair 场景使用）
force_rebuild_fts() {
    sqlite3 "$CCMEM_MEMORY_DB" <<'EOF'
DROP TABLE IF EXISTS memories_fts;
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    content,
    summary,
    tags,
    content='memories',
    content_rowid='rowid'
);
INSERT INTO memories_fts(memories_fts) VALUES('rebuild');

DROP TRIGGER IF EXISTS memories_ai;
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, content, summary, tags)
    VALUES (NEW.rowid, NEW.content, NEW.summary, NEW.tags);
END;

DROP TRIGGER IF EXISTS memories_ad;
CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content, summary, tags)
    VALUES ('delete', OLD.rowid, OLD.content, OLD.summary, OLD.tags);
END;

DROP TRIGGER IF EXISTS memories_au;
CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content, summary, tags)
    VALUES ('delete', OLD.rowid, OLD.content, OLD.summary, OLD.tags);
    INSERT INTO memories_fts(rowid, content, summary, tags)
    VALUES (NEW.rowid, NEW.content, NEW.summary, NEW.tags);
END;
EOF
}

SQLITE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SQLITE_LIB_DIR/classification.sh"
source "$SQLITE_LIB_DIR/memory_policy.sh"
source "$SQLITE_LIB_DIR/injection.sh"

# 统计带表头的 sqlite 输出中实际数据行数量。
count_result_rows() {
    local results="$1"
    echo "$results" | grep '^mem_' 2>/dev/null | wc -l | tr -d ' '
}

should_condense_operation_log() {
    local content="$1"
    local line_count=0

    [ -z "$content" ] && return 1
    line_count=$(printf "%s\n" "$content" | wc -l | tr -d ' ')

    if [ "${#content}" -gt 1500 ] || [ "$line_count" -gt 12 ]; then
        return 0
    fi

    return 1
}

summarize_operation_log() {
    local content="$1"
    local max_items="${2:-4}"
    local file_change_count=0
    local bash_count=0
    local file_changes=""
    local bash_commands=""

    if [ -z "$content" ]; then
        echo ""
        return
    fi

    file_change_count=$(printf "%s\n" "$content" | grep '^\[FILE_CHANGE\]' 2>/dev/null | wc -l | tr -d ' ')
    bash_count=$(printf "%s\n" "$content" | grep '^\[BASH\]' 2>/dev/null | wc -l | tr -d ' ')

    file_changes=$(printf "%s\n" "$content" | grep '^\[FILE_CHANGE\]' 2>/dev/null | tail -n "$max_items" | sed 's/^\[FILE_CHANGE\] /- /')
    bash_commands=$(printf "%s\n" "$content" | grep '^\[BASH\]' 2>/dev/null | tail -n "$max_items" | sed 's/^\[BASH\] /- /')

    echo "操作摘要: Files=${file_change_count} Bash=${bash_count}"

    if [ -n "$file_changes" ]; then
        echo ""
        echo "最近文件变更:"
        printf "%s\n" "$file_changes"
    fi

    if [ -n "$bash_commands" ]; then
        echo ""
        echo "最近命令:"
        printf "%s\n" "$bash_commands"
    fi
}

condense_final_response() {
    local content="$1"
    local max_chars="${2:-1200}"
    local first_line=""
    local key_points=""
    local last_line=""
    local condensed=""

    if [ -z "$content" ]; then
        echo ""
        return
    fi

    first_line=$(printf "%s\n" "$content" | grep -v '^[[:space:]]*$' | head -1)
    key_points=$(printf "%s\n" "$content" | grep -E '^[[:space:]]*([-*•]|[0-9]+[.)])[[:space:]]+' 2>/dev/null | head -n 5)

    if [ -z "$key_points" ]; then
        key_points=$(printf "%s\n" "$content" | grep -E '修复|增加|改为|支持|处理|优化|回退|测试|结论|原因|问题' 2>/dev/null | grep -v '^[[:space:]]*$' | head -n 5 | sed 's/^/- /')
    fi

    last_line=$(printf "%s\n" "$content" | grep -v '^[[:space:]]*$' | tail -1)

    condensed="$first_line"

    if [ -n "$key_points" ]; then
        condensed="${condensed}"$'\n\n'"关键点:"$'\n'"$key_points"
    fi

    if [ -n "$last_line" ] && [ "$last_line" != "$first_line" ]; then
        condensed="${condensed}"$'\n\n'"结尾:"$'\n'"$last_line"
    fi

    if [ "${#condensed}" -gt "$max_chars" ]; then
        condensed="${condensed:0:$max_chars}..."
    fi

    echo "$condensed"
}

RETRIEVE_CJK_FALLBACK_USED=0

# 初始化数据库
init_db() {
    sqlite3 "$CCMEM_MEMORY_DB" <<EOF
-- 记忆表
CREATE TABLE IF NOT EXISTS memories (
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

-- 会话表
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    start_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    end_time DATETIME,
    project_path TEXT,
    project_root TEXT,
    message_count INTEGER DEFAULT 0,
    summary TEXT,
    status TEXT DEFAULT 'active'
);

-- 项目配置表（用于项目级记忆隔离）
CREATE TABLE IF NOT EXISTS projects (
    path TEXT PRIMARY KEY,
    name TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_accessed DATETIME DEFAULT CURRENT_TIMESTAMP,
    tags TEXT
);

-- 项目关联表（用于受控跨项目记忆关联）
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

-- 记忆历史表（记录记忆的创建/更新/删除事件）
CREATE TABLE IF NOT EXISTS memory_history (
    id TEXT PRIMARY KEY,
    memory_id TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK(event_type IN ('create', 'update', 'delete')),
    old_value TEXT,
    new_value TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    session_id TEXT,
    FOREIGN KEY (memory_id) REFERENCES memories(id)
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_history_memory ON memory_history(memory_id);
CREATE INDEX IF NOT EXISTS idx_history_timestamp ON memory_history(timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_path);
CREATE INDEX IF NOT EXISTS idx_sessions_project_root ON sessions(project_root);

EOF
    force_rebuild_fts
    echo "Database initialized at $CCMEM_MEMORY_DB"
}

# 存储记忆
store_memory() {
    local session_id="$1"
    local project_path="$2"
    local category="$3"
    local content="$4"
    local summary="$5"
    local tags="$6"
    local concepts="$7"
    local source="${8:-manual}"
    local memory_kind="$9"
    local auto_inject_policy="${10}"
    local project_root="${11}"
    local expires_at="${12}"
    local classification_confidence="${13}"
    local classification_reason="${14}"
    local classification_source="${15}"
    local classification_version="${16}"

    content=$(strip_injected_context_blocks "$content")
    summary=$(strip_injected_context_blocks "$summary")

    # 拒绝空内容和纯空白内容，避免写入无效记忆。
    if [ -z "$(echo "$content" | tr -d '[:space:]')" ]; then
        echo "error:content cannot be empty"
        return 1
    fi

    local id=$(generate_id)
    local epoch=$(generate_epoch_timestamp)
    local content_preview=""
    local content_hash=$(generate_content_hash "$content" "$category")
    local id_escaped
    local session_id_escaped
    local project_path_escaped
    local category_escaped
    local content_escaped
    local content_preview_escaped
    local summary_escaped
    local tags_escaped
    local concepts_escaped
    local content_hash_escaped
    local source_escaped
    local classification_reason_escaped
    local classification_source_escaped
    local classification_version_escaped
    local memory_kind_escaped
    local auto_inject_policy_escaped
    local project_root_escaped
    local expires_at_escaped

    if [ -z "$project_path" ]; then
        project_path="$(pwd)"
    fi

    if [ -z "$project_root" ]; then
        project_root=$(resolve_project_root "$project_path")
    fi

    if [ -z "$memory_kind" ]; then
        memory_kind=$(infer_memory_kind "$source" "$category")
    fi

    if [ -z "$auto_inject_policy" ]; then
        auto_inject_policy=$(infer_auto_inject_policy "$source" "$category")
    fi

    if [ -z "$expires_at" ]; then
        expires_at=$(infer_expires_at "$source" "$memory_kind")
    fi

    content_preview=$(generate_content_preview "$content" "$memory_kind")

    if [ -z "$classification_source" ] && [ "$source" = "manual" ]; then
        classification_source="manual"
    fi

    if [ -z "$classification_version" ] && [ "$source" = "manual" ]; then
        classification_version="manual"
    fi

    if [ -z "$classification_confidence" ] && [ "$source" = "manual" ]; then
        classification_confidence="100"
    fi

    if [ -z "$classification_reason" ] && [ "$source" = "manual" ]; then
        classification_reason="user-specified"
    fi

    if [ -z "$summary" ]; then
        summary="${content:0:100}..."
    fi

    # 检查是否重复
    local existing_id
    existing_id=$(check_duplicate_memory "$content_hash" "$project_root")
    if [ -n "$existing_id" ]; then
        echo "duplicate:$existing_id"
        return
    fi

    id_escaped=$(sql_escape "$id")
    session_id_escaped=$(sql_escape "$session_id")
    project_path_escaped=$(sql_escape "$project_path")
    category_escaped=$(sql_escape "$category")
    content_escaped=$(sql_escape "$content")
    content_preview_escaped=$(sql_escape "$content_preview")
    summary_escaped=$(sql_escape "$summary")
    tags_escaped=$(sql_escape "$tags")
    concepts_escaped=$(sql_escape "$concepts")
    content_hash_escaped=$(sql_escape "$content_hash")
    source_escaped=$(sql_escape "$source")
    classification_reason_escaped=$(sql_escape "$classification_reason")
    classification_source_escaped=$(sql_escape "$classification_source")
    classification_version_escaped=$(sql_escape "$classification_version")
    memory_kind_escaped=$(sql_escape "$memory_kind")
    auto_inject_policy_escaped=$(sql_escape "$auto_inject_policy")
    project_root_escaped=$(sql_escape "$project_root")
    expires_at_escaped=$(sql_escape "$expires_at")

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF
INSERT INTO memories (
    id, session_id, project_path, project_root, category, source, memory_kind,
    auto_inject_policy, expires_at, classification_confidence, classification_reason,
    classification_source, classification_version, content, content_preview, summary,
    tags, concepts, timestamp_epoch, content_hash
)
VALUES (
    '$id_escaped', '$session_id_escaped', '$project_path_escaped', '$project_root_escaped',
    '$category_escaped', '$source_escaped', '$memory_kind_escaped',
    '$auto_inject_policy_escaped', NULLIF('$expires_at_escaped', ''),
    NULLIF('${classification_confidence}', ''),
    NULLIF('$classification_reason_escaped', ''),
    NULLIF('$classification_source_escaped', ''),
    NULLIF('$classification_version_escaped', ''),
    '$content_escaped', '$content_preview_escaped', '$summary_escaped',
    '$tags_escaped', '$concepts_escaped', $epoch, '$content_hash_escaped'
);
EOF
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "error:INSERT failed with exit code $exit_code"
        return 1
    fi

    # 记录历史
    log_memory_event "$id" "create" "" "$content" "$session_id"

    echo "$id"
}

# 检索记忆（支持全文检索和充分性检查）
retrieve_memories() {
    local project_path="$1"
    local query="$2"
    local category="$3"
    local limit="${4:-10}"
    local min_results="${5:-3}"  # 最小结果数，用于充分性检查

    local where_clause="WHERE 1=1"
    local project_path_escaped=""
    local category_escaped=""

    if [ -n "$project_path" ]; then
        project_path_escaped=$(sql_escape "$project_path")
    fi

    if [ -n "$category" ]; then
        category_escaped=$(sql_escape "$category")
    fi

    if [ -n "$project_path" ]; then
        where_clause="$where_clause AND (project_path = '$project_path_escaped' OR project_path LIKE '$project_path_escaped/%')"
    fi

    if [ -n "$category" ]; then
        where_clause="$where_clause AND category = '$category_escaped'"
    fi

    if [ -n "$query" ]; then
        local query_escaped
        local query_like_escaped
        query_escaped=$(sql_escape "$query")
        query_like_escaped=$(sql_escape_like "$query")

        if contains_cjk "$query"; then
            # CJK 查询：先走 FTS，同时允许 LIKE 回退。
            where_clause="$where_clause AND (rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped') OR (content LIKE '%${query_like_escaped}%' ESCAPE '\\' OR summary LIKE '%${query_like_escaped}%' ESCAPE '\\' OR tags LIKE '%${query_like_escaped}%' ESCAPE '\\'))"
        else
            # 非 CJK 查询：使用全文检索 (注意：必须使用 rowid 而不是 id)
            where_clause="$where_clause AND rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')"
        fi
    fi

    sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags,
       CASE
           WHEN project_path = '$project_path_escaped' THEN 3
           WHEN project_path LIKE '$project_path_escaped/%' THEN 2
           ELSE 1
       END as relevance
FROM memories
$where_clause
ORDER BY relevance DESC, timestamp_epoch DESC
LIMIT $limit;
EOF
}

# 分阶段检索（带充分性检查）
# 阶段 1: 精确匹配（项目 + 类别）
# 阶段 2: 全文检索
# 阶段 3: 放宽条件检索
retrieve_memories_staged() {
    local project_path="$1"
    local query="$2"
    local category="$3"
    local limit="${4:-10}"
    local min_results="${5:-3}"
    local results=""
    local count=0
    local project_path_escaped=""
    local category_escaped=""
    RETRIEVE_CJK_FALLBACK_USED=0

    if [ -n "$project_path" ]; then
        project_path_escaped=$(sql_escape "$project_path")
    fi

    if [ -n "$category" ]; then
        category_escaped=$(sql_escape "$category")
    fi

    # 阶段 1: 精确匹配（项目路径 + 类别）
    if [ -n "$project_path" ] && [ -n "$category" ]; then
        results=$(sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
WHERE project_path = '$project_path_escaped' AND category = '$category_escaped'
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
        count=$(count_result_rows "$results")
        if [ "$count" -ge "$min_results" ]; then
            echo "$results"
            return
        fi
    fi

    # 阶段 2: 项目路径匹配 + 全文检索
    if [ -n "$query" ] && [ -n "$project_path" ]; then
        local query_escaped
        local query_like_escaped
        query_escaped=$(sql_escape "$query")
        query_like_escaped=$(sql_escape_like "$query")

        if contains_cjk "$query"; then
            # CJK 查询：先尝试 FTS，结果不足时再退回 LIKE。
            results=$(sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
WHERE (project_path = '$project_path_escaped' OR project_path LIKE '$project_path_escaped/%')
  AND rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
            count=$(count_result_rows "$results")
            if [ "$count" -lt "$min_results" ]; then
                RETRIEVE_CJK_FALLBACK_USED=1
                results=$(sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
WHERE (project_path = '$project_path_escaped' OR project_path LIKE '$project_path_escaped/%')
  AND (rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')
       OR content LIKE '%${query_like_escaped}%' ESCAPE '\\' OR summary LIKE '%${query_like_escaped}%' ESCAPE '\\' OR tags LIKE '%${query_like_escaped}%' ESCAPE '\\')
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
            fi
        else
            results=$(sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
WHERE (project_path = '$project_path_escaped' OR project_path LIKE '$project_path_escaped/%')
  AND rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
        fi
        count=$(count_result_rows "$results")
        if [ "$count" -ge "$min_results" ]; then
            echo "$results"
            return
        fi
    fi

    # 阶段 3: 全文检索（不限项目）
    if [ -n "$query" ]; then
        local query_escaped
        local query_like_escaped
        query_escaped=$(sql_escape "$query")
        query_like_escaped=$(sql_escape_like "$query")

        if contains_cjk "$query"; then
            # CJK 查询：先尝试 FTS，结果不足时再退回 LIKE。
            results=$(sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
WHERE rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
            count=$(count_result_rows "$results")
            if [ "$count" -lt "$min_results" ]; then
                RETRIEVE_CJK_FALLBACK_USED=1
                results=$(sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
WHERE rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')
   OR content LIKE '%${query_like_escaped}%' ESCAPE '\\' OR summary LIKE '%${query_like_escaped}%' ESCAPE '\\' OR tags LIKE '%${query_like_escaped}%' ESCAPE '\\'
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
            fi
        else
            results=$(sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
WHERE rowid IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query_escaped')
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
        fi
        count=$(count_result_rows "$results")
        if [ "$count" -ge "$min_results" ]; then
            echo "$results"
            return
        fi
    fi

    # 阶段 4: 仅按项目检索
    if [ -n "$project_path" ]; then
        results=$(sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
WHERE project_path = '$project_path_escaped' OR project_path LIKE '$project_path_escaped/%'
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
        echo "$results"
        return
    fi

    # 阶段 5: 返回所有结果
    sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags
FROM memories
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
}

# 获取单条记忆详情
get_memory() {
    local memory_id="$1"
    local memory_id_escaped
    memory_id_escaped=$(sql_escape "$memory_id")

    sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, session_id, $(memory_display_timestamp_sql) AS timestamp, project_path, project_root, category, source, memory_kind,
       auto_inject_policy, expires_at, content, summary, concepts, tags
FROM memories
WHERE id = '$memory_id_escaped';
EOF
}

# 获取时间线上下文（某条记忆前后的记忆）
get_timeline() {
    local anchor_id="$1"
    local depth_before="${2:-3}"
    local depth_after="${3:-3}"
    local anchor_id_escaped
    anchor_id_escaped=$(sql_escape "$anchor_id")

    # 获取锚点记忆的 epoch 时间戳
    local anchor_epoch=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT timestamp_epoch FROM memories WHERE id = '$anchor_id_escaped';")

    if [ -z "$anchor_epoch" ]; then
        echo "未找到记忆：$anchor_id"
        return 1
    fi

    # 获取锚点前后的记忆
    sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, concepts, tags,
       CASE WHEN timestamp_epoch < $anchor_epoch THEN 'before'
            WHEN timestamp_epoch > $anchor_epoch THEN 'after'
            ELSE 'anchor' END as position
FROM memories
WHERE timestamp_epoch BETWEEN ($anchor_epoch - 86400 * $depth_before) AND ($anchor_epoch + 86400 * $depth_after)
ORDER BY timestamp_epoch;
EOF
}

# 创建/更新会话
upsert_session() {
    local session_id="$1"
    local project_path="$2"
    local project_root="$3"
    local session_id_escaped
    local project_path_escaped
    local project_root_escaped

    if [ -z "$project_path" ]; then
        project_path="$(pwd)"
    fi

    if [ -z "$project_root" ]; then
        project_root=$(resolve_project_root "$project_path")
    fi

    session_id_escaped=$(sql_escape "$session_id")
    project_path_escaped=$(sql_escape "$project_path")
    project_root_escaped=$(sql_escape "$project_root")

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF
INSERT OR REPLACE INTO sessions (id, project_path, project_root, start_time, status)
VALUES ('$session_id_escaped', '$project_path_escaped', '$project_root_escaped', CURRENT_TIMESTAMP, 'active');
EOF
}

# 结束会话
end_session() {
    local session_id="$1"
    local message_count="$2"
    local summary="$3"
    local session_id_escaped
    local summary_escaped
    session_id_escaped=$(sql_escape "$session_id")
    summary_escaped=$(sql_escape "$summary")

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF
UPDATE sessions
SET end_time = CURRENT_TIMESTAMP,
    message_count = $message_count,
    summary = '$summary_escaped',
    status = 'completed'
WHERE id = '$session_id_escaped';
EOF
}

# 更新项目访问
update_project_access() {
    local project_path="$1"
    local name="$2"
    local tags="$3"
    local project_path_escaped
    local name_escaped
    local tags_escaped
    project_path_escaped=$(sql_escape "$project_path")
    name_escaped=$(sql_escape "$name")
    tags_escaped=$(sql_escape "$tags")

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF
INSERT OR REPLACE INTO projects (path, name, tags, last_accessed)
VALUES ('$project_path_escaped', '$name_escaped', '$tags_escaped', CURRENT_TIMESTAMP);
EOF
}

# 导出记忆为 Markdown（简单格式，不需要 Obsidian）
export_to_markdown() {
    local output_dir="$1"
    local project_path="$2"
    local project_path_escaped=""

    mkdir -p "$output_dir"

    local where_clause="WHERE 1=1"
    if [ -n "$project_path" ]; then
        project_path_escaped=$(sql_escape "$project_path")
        where_clause="$where_clause AND project_path = '$project_path_escaped'"
    fi

    # 只导出有效的记忆记录（id 以 mem_开头）
    sqlite3 -separator '|' "$CCMEM_MEMORY_DB" "SELECT id, $(memory_display_timestamp_sql) AS timestamp, category, summary, tags, content FROM memories $where_clause AND id GLOB 'mem_*' ORDER BY timestamp_epoch DESC;" | while IFS='|' read -r id timestamp category summary tags content; do
        # 跳过空 ID
        [ -z "$id" ] && continue

        local safe_timestamp="${timestamp//:/-}"
        safe_timestamp="${safe_timestamp// /_}"
        local filename="$output_dir/${safe_timestamp}_${id}.md"
        cat > "$filename" <<MDEOF
---
id: $id
timestamp: $timestamp
category: $category
tags: $tags
project: $project_path
---

# $summary

$content
MDEOF
    done
}

# 列出所有项目
list_projects() {
    sqlite3 -header -column "$CCMEM_MEMORY_DB" "
        SELECT project_path, COUNT(*) as count, datetime(MAX(timestamp_epoch), 'unixepoch', 'localtime') as last_updated
        FROM memories
        GROUP BY project_path
        ORDER BY count DESC;
    "
}

# 记录记忆历史事件
log_memory_event() {
    local memory_id="$1"
    local event_type="$2"  # create|update|delete
    local old_value="$3"
    local new_value="$4"
    local session_id="${5:-$$}"

    local id=$(generate_id)
    local id_escaped
    local memory_id_escaped
    local event_type_escaped
    local old_value_escaped
    local new_value_escaped
    local session_id_escaped

    id_escaped=$(sql_escape "$id")
    memory_id_escaped=$(sql_escape "$memory_id")
    event_type_escaped=$(sql_escape "$event_type")
    old_value_escaped=$(sql_escape "$old_value")
    new_value_escaped=$(sql_escape "$new_value")
    session_id_escaped=$(sql_escape "$session_id")

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF
INSERT INTO memory_history (id, memory_id, event_type, old_value, new_value, session_id)
VALUES ('$id_escaped', '$memory_id_escaped', '$event_type_escaped', '$old_value_escaped', '$new_value_escaped', '$session_id_escaped');
EOF
}

# 获取记忆的历史记录
get_memory_history() {
    local memory_id="$1"
    local limit="${2:-10}"
    local memory_id_escaped
    memory_id_escaped=$(sql_escape "$memory_id")

    sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, memory_id, event_type, old_value, new_value, datetime(timestamp, 'localtime') AS timestamp, session_id
FROM memory_history
WHERE memory_id = '$memory_id_escaped'
ORDER BY timestamp DESC
LIMIT $limit;
EOF
}

# 获取最近的记忆历史
get_recent_history() {
    local limit="${1:-20}"
    local project_path="$2"

    local where_clause=""
    if [ -n "$project_path" ]; then
        local project_path_escaped
        project_path_escaped=$(sql_escape "$project_path")
        where_clause="WHERE m.project_path = '$project_path_escaped'"
    fi

    sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT h.id, h.memory_id, h.event_type, h.old_value, h.new_value, datetime(h.timestamp, 'localtime') AS timestamp, h.session_id, m.project_path
FROM memory_history h
LEFT JOIN memories m ON h.memory_id = m.id
$where_clause
ORDER BY h.timestamp DESC
LIMIT $limit;
EOF
}

# 生成 ISO8601 格式时间戳（兼容 macOS 和 Linux）
format_iso8601() {
    if date -Iseconds &> /dev/null 2>&1; then
        # GNU date (Linux)
        date -Iseconds
    elif date -u +"%Y-%m-%dT%H:%M:%S%z" &> /dev/null; then
        # BSD date (macOS)
        date -u +"%Y-%m-%dT%H:%M:%S%z"
    else
        # 通用格式
        date +"%Y-%m-%dT%H:%M:%S"
    fi
}

# 生成 epoch 时间戳
generate_epoch_timestamp() {
    if command -v date &> /dev/null; then
        date +%s
    else
        echo "0"
    fi
}

# 生成内容哈希（用于去重）
generate_content_hash() {
    local content="$1"
    local category="$2"

    # 规范化内容：小写、去除多余空格
    local normalized=$(echo "$content" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ //;s/ $//')

    # 生成哈希：category:normalized_content
    local hash_input="${category}:${normalized}"

    # 使用 sha256sum 或 shasum
    if command -v sha256sum &> /dev/null; then
        echo "$hash_input" | sha256sum | cut -c1-16
    elif command -v shasum &> /dev/null; then
        echo "$hash_input" | shasum -a 256 | cut -c1-16
    else
        # 回退到 md5 (macOS) 或 md5sum (Linux)
        if command -v md5 &> /dev/null; then
            echo "$hash_input" | md5 | cut -c1-16
        elif command -v md5sum &> /dev/null; then
            echo "$hash_input" | md5sum | cut -c1-16
        else
            # 最终回退到简单哈希
            echo "${#hash_input}"
        fi
    fi
}

# 检查内容是否已存在（通过哈希）
check_duplicate_memory() {
    local content_hash="$1"
    local project_root="$2"
    local content_hash_escaped

    if [ -z "$content_hash" ]; then
        echo ""
        return
    fi

    content_hash_escaped=$(sql_escape "$content_hash")
    if [ -n "$project_root" ]; then
        local project_root_escaped
        project_root_escaped=$(sql_escape "$project_root")
        sqlite3 "$CCMEM_MEMORY_DB" "SELECT id FROM memories WHERE content_hash = '$content_hash_escaped' AND project_root = '$project_root_escaped' LIMIT 1;"
    else
        sqlite3 "$CCMEM_MEMORY_DB" "SELECT id FROM memories WHERE content_hash = '$content_hash_escaped' LIMIT 1;"
    fi
}

# 生成唯一 ID（兼容 macOS 和 Linux）
generate_id() {
    local random_str=""

    # 尝试使用 /dev/urandom
    if [ -e /dev/urandom ]; then
        random_str=$(head /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 8)
    else
        # 回退到 $RANDOM
        random_str="${RANDOM}${RANDOM}"
        random_str=$(echo "$random_str" | tr -dc 'a-z0-9' | head -c 8)
    fi

    echo "mem_$(date +%s)_${random_str}"
}

make_project_link_id() {
    local source_root="$1"
    local target_root="$2"
    local hash_input="${source_root}|${target_root}"
    local short_hash=""

    if command -v sha256sum >/dev/null 2>&1; then
        short_hash=$(printf "%s" "$hash_input" | sha256sum | cut -c1-16)
    elif command -v shasum >/dev/null 2>&1; then
        short_hash=$(printf "%s" "$hash_input" | shasum -a 256 | cut -c1-16)
    elif command -v md5 >/dev/null 2>&1; then
        short_hash=$(printf "%s" "$hash_input" | md5 | cut -c1-16)
    elif command -v md5sum >/dev/null 2>&1; then
        short_hash=$(printf "%s" "$hash_input" | md5sum | cut -c1-16)
    else
        short_hash=$(printf "%s" "${#hash_input}")
    fi

    echo "plink_${short_hash}"
}

known_project_roots() {
    sqlite3 -noheader "$CCMEM_MEMORY_DB" "SELECT DISTINCT project_root FROM memories WHERE project_root IS NOT NULL AND project_root != '' UNION SELECT DISTINCT project_root FROM sessions WHERE project_root IS NOT NULL AND project_root != '' ORDER BY project_root;"
}

upsert_project_link() {
    local source_root="$1"
    local target_root="$2"
    local link_type="$3"
    local strength="${4:-50}"
    local reason="$5"
    local is_manual="${6:-0}"
    local link_id=""
    local source_escaped=""
    local target_escaped=""
    local type_escaped=""
    local reason_escaped=""

    [ -z "$source_root" ] && return
    [ -z "$target_root" ] && return
    [ "$source_root" = "$target_root" ] && return

    link_id=$(make_project_link_id "$source_root" "$target_root")
    source_escaped=$(sql_escape "$source_root")
    target_escaped=$(sql_escape "$target_root")
    type_escaped=$(sql_escape "$link_type")
    reason_escaped=$(sql_escape "$reason")

    sqlite3 "$CCMEM_MEMORY_DB" <<EOF
INSERT INTO project_links (
    id, source_root, target_root, link_type, strength, reason, is_manual, created_at, updated_at
)
VALUES (
    '$(sql_escape "$link_id")', '$source_escaped', '$target_escaped', '$type_escaped',
    $strength, '$reason_escaped', $is_manual, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
)
ON CONFLICT(source_root, target_root) DO UPDATE SET
    link_type = CASE
        WHEN project_links.is_manual = 1 AND excluded.is_manual = 0 THEN project_links.link_type
        ELSE excluded.link_type
    END,
    strength = CASE
        WHEN project_links.is_manual = 1 AND excluded.is_manual = 0 THEN project_links.strength
        ELSE excluded.strength
    END,
    reason = CASE
        WHEN project_links.is_manual = 1 AND excluded.is_manual = 0 THEN project_links.reason
        ELSE excluded.reason
    END,
    is_manual = CASE
        WHEN project_links.is_manual = 1 AND excluded.is_manual = 0 THEN project_links.is_manual
        ELSE excluded.is_manual
    END,
    updated_at = CURRENT_TIMESTAMP;
EOF
}

delete_project_link() {
    local source_root="$1"
    local target_root="$2"
    local source_escaped=""
    local target_escaped=""

    [ -z "$source_root" ] && return
    [ -z "$target_root" ] && return

    source_escaped=$(sql_escape "$source_root")
    target_escaped=$(sql_escape "$target_root")
    sqlite3 "$CCMEM_MEMORY_DB" "DELETE FROM project_links WHERE source_root = '$source_escaped' AND target_root = '$target_escaped';"
}

delete_auto_project_links_for_root() {
    local source_root="$1"
    local source_escaped=""

    [ -z "$source_root" ] && return
    source_escaped=$(sql_escape "$source_root")
    sqlite3 "$CCMEM_MEMORY_DB" "DELETE FROM project_links WHERE source_root = '$source_escaped' AND is_manual = 0;"
}

link_projects() {
    local source_root="$1"
    local target_root="$2"
    local link_type="${3:-manual}"
    local strength="${4:-95}"
    local reason="${5:-manual link}"
    local bidirectional="${6:-1}"

    upsert_project_link "$source_root" "$target_root" "$link_type" "$strength" "$reason" 1
    if [ "$bidirectional" = "1" ]; then
        upsert_project_link "$target_root" "$source_root" "$link_type" "$strength" "$reason" 1
    fi
}

unlink_projects() {
    local source_root="$1"
    local target_root="$2"
    local bidirectional="${3:-1}"

    delete_project_link "$source_root" "$target_root"
    if [ "$bidirectional" = "1" ]; then
        delete_project_link "$target_root" "$source_root"
    fi
}

list_related_projects() {
    local project_root="$1"
    local limit="${2:-5}"
    local min_strength="${3:-70}"
    local project_root_escaped=""

    [ -z "$project_root" ] && return
    project_root_escaped=$(sql_escape "$project_root")

    sqlite3 -separator '|' "$CCMEM_MEMORY_DB" <<EOF
SELECT target_root, link_type, strength, reason, is_manual
FROM project_links
WHERE source_root = '$project_root_escaped'
  AND strength >= $min_strength
ORDER BY
  strength DESC,
  is_manual DESC,
  target_root ASC
LIMIT $limit;
EOF
}

refresh_project_links() {
    local project_path="$1"
    local project_root=""
    local current_common_dir=""
    local current_git_root=""
    local candidate_root=""
    local candidate_common_dir=""
    local candidate_git_root=""

    project_root=$(resolve_project_root "$project_path")
    [ -z "$project_root" ] && return

    current_common_dir=$(resolve_git_common_dir "$project_path")
    if command -v git >/dev/null 2>&1 && [ -d "$project_path" ]; then
        current_git_root=$(git -C "$project_path" rev-parse --show-toplevel 2>/dev/null || true)
    fi

    delete_auto_project_links_for_root "$project_root"

    while IFS= read -r candidate_root; do
        [ -z "$candidate_root" ] && continue
        [ "$candidate_root" = "$project_root" ] && continue

        candidate_common_dir=$(resolve_git_common_dir "$candidate_root")
        candidate_git_root=""
        if command -v git >/dev/null 2>&1 && [ -d "$candidate_root" ]; then
            candidate_git_root=$(git -C "$candidate_root" rev-parse --show-toplevel 2>/dev/null || true)
        fi

        if [ -n "$current_common_dir" ] && [ -n "$candidate_common_dir" ] && [ "$current_common_dir" = "$candidate_common_dir" ]; then
            upsert_project_link "$project_root" "$candidate_root" "worktree" 100 "shared git common-dir" 0
            upsert_project_link "$candidate_root" "$project_root" "worktree" 100 "shared git common-dir" 0
            continue
        fi

        if [ -n "$current_git_root" ] && [ -n "$candidate_git_root" ] && [ "$current_git_root" = "$candidate_git_root" ] && [ "$candidate_root" != "$project_root" ]; then
            upsert_project_link "$project_root" "$candidate_root" "same_repo" 90 "shared git root" 0
            upsert_project_link "$candidate_root" "$project_root" "same_repo" 90 "shared git root" 0
            continue
        fi

        if [[ "$candidate_root" == "$project_root"/* ]] || [[ "$project_root" == "$candidate_root"/* ]]; then
            upsert_project_link "$project_root" "$candidate_root" "parent_child" 70 "parent/child project path" 0
            upsert_project_link "$candidate_root" "$project_root" "parent_child" 70 "parent/child project path" 0
        fi
    done < <(known_project_roots)
}

resolve_related_projects() {
    local project_path="$1"
    local limit="${2:-1}"
    local project_root=""

    project_root=$(resolve_project_root "$project_path")
    refresh_project_links "$project_path" >/dev/null 2>&1 || true
    list_related_projects "$project_root" "$limit" 70 | cut -d'|' -f1
}
