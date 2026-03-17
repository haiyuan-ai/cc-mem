#!/bin/bash
# CC-Mem FTS Repair Tool
# For fixing SQLite FTS5 full-text index corruption issues
#
# Usage:
#   ./repair-fts.sh [options]
#
# Options:
#   --db <path>     Specify database path (default: $HOME/.claude/cc-mem/memory.db)
#   --backup        Backup database before repair
#   --force         Force repair without checking status
#   --dry-run       Show issues only, don't repair
#   -h, --help      Show help info

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
source "$LIB_DIR/config.sh"

# Default config
DB_PATH="$(get_memory_db_path)"
DO_BACKUP=true
FORCE_REPAIR=false
DRY_RUN=false

# Parse command line args
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --db) DB_PATH="$2"; shift ;;
        --backup) DO_BACKUP=true ;;
        --no-backup) DO_BACKUP=false ;;
        --force) FORCE_REPAIR=true ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help)
            echo "CC-Mem FTS Repair Tool"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --db <path>     Specify database path (default: \$HOME/.claude/cc-mem/memory.db)"
            echo "  --backup        Backup database before repair (default: on)"
            echo "  --no-backup     Don't backup database"
            echo "  --force         Force repair without checking status"
            echo "  --dry-run       Show issues only, don't repair"
            echo "  -h, --help      Show help info"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Check FTS status
# Returns 0 if FTS is OK, 1 if FTS is abnormal
check_fts_status() {
    local db="$1"
    local result=$(sqlite3 "$db" "SELECT COUNT(*) FROM memories_fts;" 2>&1)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        return 1
    fi

    # Extra check: FTS data count matches main table
    local main_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM memories;" 2>&1)
    local fts_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM memories_fts;" 2>&1)

    if [ "$main_count" -gt 0 ] && [ "$fts_count" -eq 0 ]; then
        # Main table has data but FTS is empty, triggers not working
        return 1
    fi

    return 0
}

# Repair FTS full-text index
repair_fts() {
    local db="$1"

    echo "Repairing FTS full-text index..."
    echo "Database: $db"
    echo ""

    # Backup database
    if [ "$DO_BACKUP" = true ]; then
        local backup="${db}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$db" "$backup"
        echo "✓ Database backed up to: $backup"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "[Dry-run mode] Will perform:"
        echo "  1. Delete old FTS triggers"
        echo "  2. Delete corrupted FTS table"
        echo "  3. Create new FTS table"
        echo "  4. Recreate triggers"
        echo "  5. Reindex existing data"
        return 0
    fi

    # Execute repair
    sqlite3 "$db" <<EOF
-- Delete old triggers
DROP TRIGGER IF EXISTS memories_ai;
DROP TRIGGER IF EXISTS memories_ad;
DROP TRIGGER IF EXISTS memories_au;

-- Delete corrupted FTS table
DROP TABLE IF EXISTS memories_fts;

-- Create new FTS table (no content param, fewer dependency issues)
CREATE VIRTUAL TABLE memories_fts USING fts5(
    content,
    summary,
    tags
);

-- Recreate triggers
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

-- Reindex existing data to FTS
INSERT INTO memories_fts(rowid, content, summary, tags)
SELECT rowid, content, summary, tags FROM memories;
EOF

    # Verify repair result
    if check_fts_status "$db"; then
        local count=$(sqlite3 "$db" "SELECT COUNT(*) FROM memories_fts;")
        echo "✓ FTS repair successful!"
        echo "  FTS index records: $count"
        return 0
    else
        echo "✗ FTS repair failed, manual intervention may be needed"
        return 1
    fi
}

# Main program
main() {
    # Check if database file exists
    if [ ! -f "$DB_PATH" ]; then
        echo "Error: Database file not found: $DB_PATH"
        echo "Please run 'ccmem-cli.sh init' to initialize database"
        exit 1
    fi

    echo "=== CC-Mem FTS Repair Tool ==="
    echo ""

    # Check FTS status
    echo "Checking FTS status..."
    if check_fts_status "$DB_PATH"; then
        echo "FTS status: OK"
        if [ "$FORCE_REPAIR" = false ]; then
            echo "No repair needed, exiting."
            echo ""
            echo "Use --force to force repair"
            exit 0
        else
            echo "Force repair mode, continuing..."
        fi
    else
        echo "FTS status: abnormal"
    fi

    echo ""

    # Execute repair
    repair_fts "$DB_PATH"
    exit $?
}

main "$@"
