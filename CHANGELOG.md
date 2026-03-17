# Changelog

## [1.5.4] - 2026-03-17

### Fixed

- **FTS5 query escaping** - Fixed syntax errors when queries contain special characters (`.`, `*`, `"`, etc). Added `sql_escape_fts5()` to wrap queries as phrase literals.

## [1.5.3] - 2026-03-13

### Added

- Claude Code Skill support

### Security

- Fixed SQL injection in `store_memory()` - escaped `classification_confidence`
- Fixed command injection in MCP server - added input validation and `shlex.quote()`
- Fixed race condition in hook log files - use `mktemp` with `umask 0077`

## [1.5.2] - 2026-03-07

### Added

- MCP Server with 6 tools (capture, search, get, timeline, inject-context, recall)
- `ccmem-cli.sh recall` command
- OpenCode extension skeleton
- Session-level `inject-context` deduplication
- `stats` and `retry` CLI commands

### Improved

- Query-aware memory recall
- Content preview compression by memory kind
- Opportunistic cleanup with growth rate bypass
- Failed capture recovery preserves project context

## [1.5.1] - 2026-03-07

### Added

- `project_links` table for cross-project associations
- `related-projects`, `link-projects`, `unlink-projects` commands
- Memory classification with confidence scoring
- Classification snapshots (`classification_confidence`, `reason`, `source`, `version`)

### Improved

- Dual-mode cleanup (safe/aggressive)
- Salience ranking for recall queries

## [1.5.0] - 2026-03-07

### Added

- Memory tier model (`durable`, `working`, `temporary`)
- `auto_inject_policy` field (`always`, `conditional`, `manual_only`, `never`)
- Structured `<cc-mem-context>` injection at session start
- `<cc-mem-recall>` query-aware recall
- Related project memory hints

## [1.4.0] - 2026-03-06

### Fixed

- Fixed FTS5 full-text search (rowid vs id mismatch)
- Fixed `store_memory()` error handling
- Fixed FTS5 index rebuild on init
- Fixed `[FILE_CHANGE]` tag detection in stop hook
- Added CJK character support with LIKE fallback

---

Earlier versions: see git history.
