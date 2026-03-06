#!/bin/bash
# SQLite 操作函数库

# Git for Windows 兼容性处理
if [[ "$(uname -s)" == "MSYS"* ]] || [[ "$(uname -s)" == "MINGW"* ]]; then
    # Git Bash 环境，使用 Windows 路径风格
    if [ -n "$USERPROFILE" ]; then
        HOME="${USERPROFILE}"
    fi
fi

MEMORY_DB="${MEMORY_DB:-$HOME/.claude/cc-mem/memory.db}"

# 初始化数据库
init_db() {
    sqlite3 "$MEMORY_DB" <<EOF
-- 记忆表
CREATE TABLE IF NOT EXISTS memories (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    timestamp_epoch INTEGER,
    project_path TEXT,
    category TEXT CHECK(category IN ('decision', 'solution', 'pattern', 'debug', 'context')),
    content_hash TEXT,
    concepts TEXT,
    content TEXT NOT NULL,
    content_preview TEXT,
    summary TEXT,
    tags TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 为 content_hash 创建索引（用于去重检查）
CREATE INDEX IF NOT EXISTS idx_memories_content_hash ON memories(content_hash);

-- 会话表
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    start_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    end_time DATETIME,
    project_path TEXT,
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

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_memories_session ON memories(session_id);
CREATE INDEX IF NOT EXISTS idx_memories_project ON memories(project_path);
CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category);
CREATE INDEX IF NOT EXISTS idx_memories_tags ON memories(tags);
CREATE INDEX IF NOT EXISTS idx_memories_timestamp_epoch ON memories(timestamp_epoch DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_path);

-- 创建全文虚拟表（如果 SQLite 支持 FTS5）
DROP TABLE IF EXISTS memories_fts;
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    content,
    summary,
    tags,
    content='memories',
    content_rowid='rowid'
);

-- 创建触发器同步 FTS
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
    echo "Database initialized at $MEMORY_DB"
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

    local id=$(generate_id)
    local epoch=$(generate_epoch_timestamp)
    local content_preview="${content:0:200}"
    local content_hash=$(generate_content_hash "$content" "$category")

    # 检查是否重复
    local existing_id=$(check_duplicate_memory "$content_hash")
    if [ -n "$existing_id" ]; then
        echo "duplicate:$existing_id"
        return
    fi

    # 转义单引号
    content="${content//\'/\'\'}"
    content_preview="${content_preview//\'/\'\'}"
    summary="${summary//\'/\'\'}"

    sqlite3 "$MEMORY_DB" <<EOF
INSERT INTO memories (id, session_id, project_path, category, content, content_preview, summary, tags, concepts, timestamp_epoch, content_hash)
VALUES ('$id', '$session_id', '$project_path', '$category', '$content', '$content_preview', '$summary', '$tags', '$concepts', $epoch, '$content_hash');
EOF

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

    if [ -n "$project_path" ]; then
        where_clause="$where_clause AND (project_path = '$project_path' OR project_path LIKE '$project_path/%')"
    fi

    if [ -n "$category" ]; then
        where_clause="$where_clause AND category = '$category'"
    fi

    if [ -n "$query" ]; then
        # 使用全文检索
        where_clause="$where_clause AND id IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query')"
    fi

    sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, summary, concepts, tags,
       CASE
           WHEN project_path = '$project_path' THEN 3
           WHEN project_path LIKE '$project_path/%' THEN 2
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

    # 阶段 1: 精确匹配（项目路径 + 类别）
    if [ -n "$project_path" ] && [ -n "$category" ]; then
        results=$(sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, summary, concepts, tags
FROM memories
WHERE project_path = '$project_path' AND category = '$category'
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
        count=$(echo "$results" | grep -c "^" 2>/dev/null || echo "0")
        if [ "$count" -ge "$min_results" ]; then
            echo "$results"
            return
        fi
    fi

    # 阶段 2: 项目路径匹配 + 全文检索
    if [ -n "$query" ] && [ -n "$project_path" ]; then
        results=$(sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, summary, concepts, tags
FROM memories
WHERE (project_path = '$project_path' OR project_path LIKE '$project_path/%')
  AND id IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query')
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
        count=$(echo "$results" | grep -c "^" 2>/dev/null || echo "0")
        if [ "$count" -ge "$min_results" ]; then
            echo "$results"
            return
        fi
    fi

    # 阶段 3: 全文检索（不限项目）
    if [ -n "$query" ]; then
        results=$(sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, summary, concepts, tags
FROM memories
WHERE id IN (SELECT rowid FROM memories_fts WHERE memories_fts MATCH '$query')
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
        count=$(echo "$results" | grep -c "^" 2>/dev/null || echo "0")
        if [ "$count" -ge "$min_results" ]; then
            echo "$results"
            return
        fi
    fi

    # 阶段 4: 仅按项目检索
    if [ -n "$project_path" ]; then
        results=$(sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, summary, concepts, tags
FROM memories
WHERE project_path = '$project_path' OR project_path LIKE '$project_path/%'
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
)
        echo "$results"
        return
    fi

    # 阶段 5: 返回所有结果
    sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, summary, concepts, tags
FROM memories
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
}

# 获取单条记忆详情
get_memory() {
    local memory_id="$1"

    sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, session_id, timestamp, project_path, category, content, summary, concepts, tags
FROM memories
WHERE id = '$memory_id';
EOF
}

# 获取时间线上下文（某条记忆前后的记忆）
get_timeline() {
    local anchor_id="$1"
    local depth_before="${2:-3}"
    local depth_after="${3:-3}"

    # 获取锚点记忆的 epoch 时间戳
    local anchor_epoch=$(sqlite3 "$MEMORY_DB" "SELECT timestamp_epoch FROM memories WHERE id = '$anchor_id';")

    if [ -z "$anchor_epoch" ]; then
        echo "未找到记忆：$anchor_id"
        return 1
    fi

    # 获取锚点前后的记忆
    sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, summary, concepts, tags,
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

    sqlite3 "$MEMORY_DB" <<EOF
INSERT OR REPLACE INTO sessions (id, project_path, start_time, status)
VALUES ('$session_id', '$project_path', CURRENT_TIMESTAMP, 'active');
EOF
}

# 结束会话
end_session() {
    local session_id="$1"
    local message_count="$2"
    local summary="$3"

    sqlite3 "$MEMORY_DB" <<EOF
UPDATE sessions
SET end_time = CURRENT_TIMESTAMP,
    message_count = $message_count,
    summary = '$summary',
    status = 'completed'
WHERE id = '$session_id';
EOF
}

# 更新项目访问
update_project_access() {
    local project_path="$1"
    local name="$2"
    local tags="$3"

    sqlite3 "$MEMORY_DB" <<EOF
INSERT OR REPLACE INTO projects (path, name, tags, last_accessed)
VALUES ('$project_path', '$name', '$tags', CURRENT_TIMESTAMP);
EOF
}

# 清理旧记忆（保留最近 N 天）
cleanup_old_memories() {
    local days="${1:-30}"
    sqlite3 "$MEMORY_DB" <<EOF
DELETE FROM memories WHERE timestamp < datetime('now', '-$days days');
VACUUM;
EOF
    echo "Cleaned up memories older than $days days"
}

# 导出记忆为 Markdown（简单格式，不需要 Obsidian）
export_to_markdown() {
    local output_dir="$1"
    local project_path="$2"

    mkdir -p "$output_dir"

    local where_clause="WHERE 1=1"
    if [ -n "$project_path" ]; then
        where_clause="$where_clause AND project_path = '$project_path'"
    fi

    # 只导出有效的记忆记录（id 以 mem_开头）
    sqlite3 -separator '|' "$MEMORY_DB" "SELECT id, timestamp, category, summary, tags, content FROM memories $where_clause AND id GLOB 'mem_*' ORDER BY timestamp DESC;" | while IFS='|' read -r id timestamp category summary tags content; do
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

# 生成项目 CLAUDE.md 上下文文件
generate_claude_md() {
    local project_path="$1"
    local output_file="$2"

    if [ -z "$output_file" ]; then
        output_file="$project_path/CLAUDE.md"
    fi

    # 获取项目相关记忆
    local memories=$(sqlite3 -separator '|' "$MEMORY_DB" "
        SELECT id, timestamp, category, content_preview, concepts, tags
        FROM memories
        WHERE project_path = '$project_path' OR project_path LIKE '$project_path/%'
        ORDER BY timestamp_epoch DESC
        LIMIT 20;
    ")

    if [ -z "$memories" ]; then
        echo "项目 '$project_path' 暂无记忆记录"
        return 1
    fi

    # 生成 CLAUDE.md 文件
    cat > "$output_file" <<EOF
<cc-mem-context>
# Recent Activity

<!-- This section is auto-generated by cc-mem. Edit content outside the tags. -->

EOF

    # 按日期分组
    local current_date=""

    echo "$memories" | while IFS='|' read -r id timestamp category preview concepts tags; do
        # 提取日期
        local date_part="${timestamp%% *}"

        # 如果日期变化，添加日期标题
        if [ "$date_part" != "$current_date" ]; then
            current_date="$date_part"
            echo "" >> "$output_file"
            echo "### $current_date" >> "$output_file"
            echo "" >> "$output_file"
            echo "| ID | Time | C | Title | Concepts |" >> "$output_file"
            echo "|----|------|---|-------|----------|" >> "$output_file"
        fi

        # 提取时间和类别图标
        local time_part="${timestamp#* }"
        time_part="${time_part%%.*}"
        local category_icon="🔵"
        case "$category" in
            "decision") category_icon="📌" ;;
            "solution") category_icon="💡" ;;
            "debug") category_icon="🐛" ;;
            "pattern") category_icon="🔧" ;;
        esac

        # 截断预览
        local short_preview="${preview:0:50}..."
        short_preview="${short_preview//$'\n'/ }"

        # 获取概念标签
        local concept_display=""
        if [ -n "$concepts" ]; then
            concept_display="$concepts"
        else
            concept_display="-"
        fi

        echo "| $id | $time_part | $category_icon | $short_preview | $concept_display |" >> "$output_file"
    done

    cat >> "$output_file" <<EOF

</cc-mem-context>

---
*Generated by CC-Mem at $(format_iso8601)*
EOF

    echo "已生成：$output_file"
}

# 列出所有项目
list_projects() {
    sqlite3 -header -column "$MEMORY_DB" "
        SELECT project_path, COUNT(*) as count, MAX(timestamp) as last_updated
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

    # 转义单引号
    old_value="${old_value//\'/\'\'}"
    new_value="${new_value//\'/\'\'}"

    sqlite3 "$MEMORY_DB" <<EOF
INSERT INTO memory_history (id, memory_id, event_type, old_value, new_value, session_id)
VALUES ('$id', '$memory_id', '$event_type', '$old_value', '$new_value', '$session_id');
EOF
}

# 获取记忆的历史记录
get_memory_history() {
    local memory_id="$1"
    local limit="${2:-10}"

    sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, memory_id, event_type, old_value, new_value, timestamp, session_id
FROM memory_history
WHERE memory_id = '$memory_id'
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
        where_clause="WHERE m.project_path = '$project_path'"
    fi

    sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT h.id, h.memory_id, h.event_type, h.old_value, h.new_value, h.timestamp, h.session_id, m.project_path
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
        # 回退到简单哈希
        echo "$hash_input" | md5sum 2>/dev/null | cut -c1-16 || echo "${#hash_input}"
    fi
}

# 检查内容是否已存在（通过哈希）
check_duplicate_memory() {
    local content_hash="$1"

    if [ -z "$content_hash" ]; then
        echo ""
        return
    fi

    sqlite3 "$MEMORY_DB" "SELECT id FROM memories WHERE content_hash = '$content_hash' LIMIT 1;"
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
