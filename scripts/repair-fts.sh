#!/bin/bash
# CC-Mem FTS 修复工具
# 用于修复 SQLite FTS5 全文索引损坏问题
#
# 用法：
#   ./repair-fts.sh [选项]
#
# 选项:
#   --db <path>     指定数据库路径（默认：$HOME/.claude/cc-mem/memory.db）
#   --backup        修复前备份数据库
#   --force         强制修复，不检查状态
#   --dry-run       只显示问题，不执行修复
#   -h, --help      显示帮助信息

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/config.sh"

# 默认配置
DB_PATH="$(get_memory_db_path)"
DO_BACKUP=true
FORCE_REPAIR=false
DRY_RUN=false

# 解析命令行参数
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --db) DB_PATH="$2"; shift ;;
        --backup) DO_BACKUP=true ;;
        --no-backup) DO_BACKUP=false ;;
        --force) FORCE_REPAIR=true ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help)
            echo "CC-Mem FTS 修复工具"
            echo ""
            echo "用法：$0 [选项]"
            echo ""
            echo "选项:"
            echo "  --db <path>     指定数据库路径（默认：\$HOME/.claude/cc-mem/memory.db）"
            echo "  --backup        修复前备份数据库（默认开启）"
            echo "  --no-backup     不备份数据库"
            echo "  --force         强制修复，不检查状态"
            echo "  --dry-run       只显示问题，不执行修复"
            echo "  -h, --help      显示帮助信息"
            exit 0
            ;;
        *) echo "未知选项：$1"; exit 1 ;;
    esac
    shift
done

# 检查 FTS 状态
# 返回 0 表示 FTS 正常，返回 1 表示 FTS 异常
check_fts_status() {
    local db="$1"
    local result=$(sqlite3 "$db" "SELECT COUNT(*) FROM memories_fts;" 2>&1)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        return 1
    fi

    # 额外检查：FTS 数据量是否与主表匹配
    local main_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM memories;" 2>&1)
    local fts_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM memories_fts;" 2>&1)

    if [ "$main_count" -gt 0 ] && [ "$fts_count" -eq 0 ]; then
        # 主表有数据但 FTS 为空，说明触发器未工作
        return 1
    fi

    return 0
}

# 修复 FTS 全文索引
repair_fts() {
    local db="$1"

    echo "正在修复 FTS 全文索引..."
    echo "数据库：$db"
    echo ""

    # 备份数据库
    if [ "$DO_BACKUP" = true ]; then
        local backup="${db}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$db" "$backup"
        echo "✓ 已备份数据库到：$backup"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "[干运行模式] 将执行以下操作:"
        echo "  1. 删除旧的 FTS 触发器"
        echo "  2. 删除损坏的 FTS 表"
        echo "  3. 创建新的 FTS 表"
        echo "  4. 重新创建触发器"
        echo "  5. 重新索引现有数据"
        return 0
    fi

    # 执行修复
    sqlite3 "$db" <<EOF
-- 删除旧的触发器
DROP TRIGGER IF EXISTS memories_ai;
DROP TRIGGER IF EXISTS memories_ad;
DROP TRIGGER IF EXISTS memories_au;

-- 删除损坏的 FTS 表
DROP TABLE IF EXISTS memories_fts;

-- 创建新的 FTS 表（不使用 content 参数，减少依赖问题）
CREATE VIRTUAL TABLE memories_fts USING fts5(
    content,
    summary,
    tags
);

-- 重新创建触发器
CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, content, summary, tags)
    VALUES (NEW.rowid, NEW.content, NEW.summary, NEW.tags);
END;

CREATE TRIGGER memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content, summary, tags)
    VALUES ('delete', OLD.rowid, OLD.content, OLD.summary, OLD.tags);
END;

CREATE TRIGGER memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, content, summary, tags)
    VALUES ('delete', OLD.rowid, OLD.content, OLD.summary, OLD.tags);
    INSERT INTO memories_fts(rowid, content, summary, tags)
    VALUES (NEW.rowid, NEW.content, NEW.summary, NEW.tags);
END;

-- 将现有数据重新索引到 FTS
INSERT INTO memories_fts(rowid, content, summary, tags)
SELECT rowid, content, summary, tags FROM memories;
EOF

    # 验证修复结果
    if check_fts_status "$db"; then
        local count=$(sqlite3 "$db" "SELECT COUNT(*) FROM memories_fts;")
        echo "✓ FTS 修复成功！"
        echo "  FTS 索引记录数：$count"
        return 0
    else
        echo "✗ FTS 修复失败，可能需要手动干预"
        return 1
    fi
}

# 主程序
main() {
    # 检查数据库文件是否存在
    if [ ! -f "$DB_PATH" ]; then
        echo "错误：数据库文件不存在：$DB_PATH"
        echo "请先运行 'ccmem-cli.sh init' 初始化数据库"
        exit 1
    fi

    echo "=== CC-Mem FTS 修复工具 ==="
    echo ""

    # 检查 FTS 状态
    echo "检查 FTS 状态..."
    if check_fts_status "$DB_PATH"; then
        echo "FTS 状态：正常"
        if [ "$FORCE_REPAIR" = false ]; then
            echo "无需修复，退出。"
            echo ""
            echo "如需强制修复，请使用 --force 选项"
            exit 0
        else
            echo "强制修复模式，继续执行..."
        fi
    else
        echo "FTS 状态：异常"
    fi

    echo ""

    # 执行修复
    repair_fts "$DB_PATH"
    exit $?
}

main "$@"
