# CC-mem

> **English** | [中文](README-zh.md)

Lightweight memory management system for Claude Code

**Tests**: ✅ Full regression passed | **License**: MIT

---

## Overview

**CC-mem** is a **local-first, rule-driven, tiered-storage, explainable-injection memory system** for Claude Code.

**Target Users**: Individual developers, technical bloggers, heavy AI assistant users

**Core Values**:
- 🪶 **Lightweight** - Pure Bash scripts, core dependency on SQLite only, no Node runtime required
- 🔒 **Local-first** - All data stored locally, no cloud dependencies, privacy controlled
- 📦 **Ready to use** - Install and run, no complex configuration
- 🧪 **Well tested** - Full regression coverage for storage, CLI, hooks, and edge cases

**Ideal For**:
- ✅ Personal knowledge management and session memory
- ✅ Cross-session context retention
- ✅ Technical decision and solution documentation
- ✅ Project-level memory isolation

**Not Suitable For**:
- ❌ Enterprise multi-user collaboration
- ❌ Complex scenarios requiring vector search
- ❌ Graph-based knowledge representation

---

## Features

- **Automatic Capture**: PostToolUse / UserPromptSubmit / Stop / SessionEnd continuously capture work progress
- **Real-time Injection**: SessionStart preloads context + UserPromptSubmit query-aware recall
- **Tiered Memory**: Organized by source, lifecycle, and auto-inject eligibility
- **Cross-project Linking**: Controlled related project memory supplementation via `project_links`
- **Smart Truncation**: Stop / SessionEnd locally truncate overly long responses and logs
- **Preview Compression**: `content_preview` generates tiered previews based on `durable / working / temporary`, balancing fidelity and storage efficiency
- **Rule-based Classification**: Automatic capture paths share a unified local classifier, generating category, confidence, and reasoning to inform tiering decisions
- **Prompt Reuse Detection**: `user_prompt_submit` prioritizes extracting reusable preferences, constraints, rules, and decisions, skipping one-time confirmation phrases
- **Tool Signal Extraction**: `post_tool_use` focuses on extracting error, fix, verification, and file change signals rather than elevating entire outputs to memory
- **Persistent Storage**: SQLite local database
- **Tiered Retrieval**: FTS, Chinese fallback, timeline, related project recall
- **Failure Recovery**: Hooks write failures are queued locally for retry, preventing data loss
- **MCP Tools**: Exposes capture/search/get/timeline/inject-context/recall via MCP
- **Markdown Export**: Export to standard Markdown files
- **Hooks Integration**: SessionStart / UserPromptSubmit auto-injection, PostToolUse / Stop / SessionEnd auto-capture
- **Memory History**: Track memory events and change history
- **Content Deduplication**: Automatic duplicate detection based on content hash
- **Concept Tags**: Predefined concept auto-recognition

## Installation

### Requirements

- **macOS** 10.15+ - Built-in Bash and SQLite
- **Linux** Ubuntu 18.04+ / Debian 10+ - Requires sqlite3 installation
- **Windows** Windows 10/11 + WSL2

See **[Compatibility Guide](docs/COMPATIBILITY.md)** for detailed requirements.

Additional notes:
- Recommended: `git`, `sqlite3`, `jq`
- Hooks auto-injection/capture functionality works best with `jq`
- MCP server requires `python3`

### Option 1: One-line Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/install.sh | bash
```

Restart Claude Code after installation:
```bash
exit
# restart claude
```

### Option 2: Let Claude Code Install (Easiest)

Simply tell Claude Code:

```
Install https://github.com/haiyuan-ai/cc-mem
```

Claude Code will automatically:
1. Clone the repository to the correct directory
2. Register marketplace configuration
3. Register as installed plugin
4. Initialize the database

After installation, restart Claude Code:
```bash
exit
# restart claude
```

Then enable the plugin:
```
/plugin install cc-mem@haiyuan-ai-cc-mem
```

Restart Claude Code once more to activate hooks.

### Option 3: Manual Installation

**Step 1: Clone Repository**

```bash
git clone https://github.com/haiyuan-ai/cc-mem.git ~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem
```

**Step 2: Register Marketplace**

Edit `~/.claude/plugins/known_marketplaces.json`, add:

```json
{
  "haiyuan-ai-cc-mem": {
    "source": {
      "source": "github",
      "repo": "haiyuan-ai/cc-mem"
    },
    "installLocation": "/ABSOLUTE/PATH/TO/.claude/plugins/marketplaces/haiyuan-ai-cc-mem",
    "lastUpdated": "2026-03-07T00:00:00.000Z"
  }
}
```

Use absolute paths, do not use `$HOME` or `~`.
Examples:
- macOS: `/Users/yourname/.claude/plugins/marketplaces/haiyuan-ai-cc-mem`
- Linux/WSL: `/home/yourname/.claude/plugins/marketplaces/haiyuan-ai-cc-mem`

**Step 3: Register Installed Plugin**

Edit `~/.claude/plugins/installed_plugins.json`, add to the `plugins` object:

```json
"cc-mem@haiyuan-ai-cc-mem": [
  {
    "scope": "user",
    "installPath": "/ABSOLUTE/PATH/TO/.claude/plugins/marketplaces/haiyuan-ai-cc-mem",
    "version": "main",
    "installedAt": "2026-03-07T00:00:00.000Z",
    "lastUpdated": "2026-03-07T00:00:00.000Z",
    "gitCommitSha": "COMMIT_SHA_HERE"
  }
]
```

**Step 4: Restart Claude Code Session**

```bash
exit
# restart claude
```

---

## Uninstallation

### Option 1: One-line Uninstall (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/uninstall.sh | bash
```

Then restart Claude Code:

```bash
exit
# restart claude
```

### Option 2: Using `/plugin` Command

```bash
/plugin uninstall cc-mem@haiyuan-ai-cc-mem
```

Then restart Claude Code:

```bash
exit
# restart claude
```

### Option 3: Manual Uninstallation

**Step 1: Remove Plugin Directory**

```bash
rm -rf ~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem
```

**Step 2: Remove Skill**

```bash
rm -f ~/.claude/skills/cc-mem.md
```

> **Note**: Plugin-level hooks are automatically removed, no manual config editing needed.

**Step 3: Clean Marketplace Registration (Optional)**

Edit `~/.claude/plugins/known_marketplaces.json`, remove the `haiyuan-ai-cc-mem` entry.

**Step 4: Remove Database (Optional)**

```bash
# Default path
rm -rf ~/.claude/cc-mem/memory.db
# Or custom path
rm -rf ~/.config/cc-mem/memory.db
```

**Step 5: Restart Claude Code Session**

```bash
exit
# restart claude
```

---

## Usage

### Basic Commands

```bash
# Initialize
ccmem-cli.sh init

# Check status
ccmem-cli.sh status

# View recent stats
ccmem-cli.sh stats --days 7

# Retry failed queue
ccmem-cli.sh retry

# Capture memory
echo "Important content" | ccmem-cli.sh capture -c "decision" -t "tag1,tag2"

# Search memories
ccmem-cli.sh search -p "/path/to/project" -q "keywords"

# Generate query-aware recall
ccmem-cli.sh recall -p "/path/to/project" -q "current problem"

# Get timeline context
ccmem-cli.sh timeline -a mem_xxx -b 3 -A 3

# Get memory details
ccmem-cli.sh get mem_123 mem_456

# List recent memories
ccmem-cli.sh list

# Manual capture (custom summary)
ccmem-cli.sh capture -p "/path/to/project" -c "pattern" -t "tag" -m "summary"

# Export memories
ccmem-cli.sh export -o "~/exports"

# Generate session start injection context
ccmem-cli.sh inject-context -p "/path/to/project" -l 3

# List all projects
ccmem-cli.sh projects

# List related projects
ccmem-cli.sh related-projects -p "/path/to/project"

# Manual project link/unlink
ccmem-cli.sh link-projects "/repo/app" "/repo/lib-common" --reason "shared architecture"
ccmem-cli.sh unlink-projects "/repo/app" "/repo/lib-common"

# Clean up expired memories
ccmem-cli.sh cleanup -d 30

# View memory history
ccmem-cli.sh history -r -l 10

# Repair FTS index (maintenance)
./scripts/repair-fts.sh --force --no-backup
```

### Common Usage

#### `stats` - View Recent Memory Statistics

```bash
# View last 7 days stats
ccmem-cli.sh stats

# View last 14 days stats for specific project
ccmem-cli.sh stats --days 14 --project "/path/to/project"
```

Output features:
- Shows memory count for last N days
- Shows `content` / `content_preview` byte statistics and preview ratio
- Shows durable / working / temporary tier distribution
- Supports filtering by `project_root`

#### `capture` - Capture Memory

```bash
# Read from stdin
echo "Decision: Choose SQLite as storage solution" | \
  ccmem-cli.sh capture -c "decision" -t "sqlite,architecture"

# Specify project path
ccmem-cli.sh capture -p "/path/to/project" -c "solution" -t "bugfix"
```

**Categories:**
- `decision` - Important decisions
- `solution` - Solutions
- `pattern` - Reusable patterns
- `debug` - Debug records
- `context` - Context information

#### `search` - Search Memories

```bash
# Search by project path
ccmem-cli.sh search -p "/path/to/project"

# Search by keywords
ccmem-cli.sh search -q "SQLite full-text search"

# Search by category
ccmem-cli.sh search -c "debug"

# Combined search
ccmem-cli.sh search -p "/path/to/project" -q "API" -c "solution" -l 5
```

Notes:
- English/normal keywords prioritize FTS5
- Chinese queries automatically enable `LIKE` fallback
- `search` is better for finding candidates; use `timeline` and `get` for details

#### `export` - Export Memories

```bash
# Export all memories to directory
ccmem-cli.sh export -o "~/cc-mem-exports"

# Export specific project memories
ccmem-cli.sh export -p "/path/to/project" -o ~/exports
```

**Export Format**: Standard Markdown files, viewable in any Markdown editor (VS Code, Typora, Obsidian, etc.)

#### `retry` - Retry Failed Queue

```bash
# Retry all failed items
ccmem-cli.sh retry

# Preview only
ccmem-cli.sh retry --dry-run

# Process specific hook failures
ccmem-cli.sh retry --hook stop
```

Use cases:
- Retry failed hook writes
- Preserve original project context during recovery
- Duplicates are automatically removed

#### `timeline` / `get`

```bash
# Get memory context around anchor
ccmem-cli.sh timeline -a mem_123 -b 3 -A 3

# Parameters
# -a: Anchor memory ID
# -b: Memories before anchor (default 3)
# -A: Memories after anchor (default 3)
```

#### `inject-context` / `recall`

```bash
# Generate session start context for project
ccmem-cli.sh inject-context -p "/path/to/project" -l 3
```

Output features:
- Only outputs structured `<cc-mem-context>` block
- Defaults to durable / conditional memories
- Supplements 1 related project memory if needed
- Auto appends timeline hints for consecutive debug/decision chains

#### `projects` / `related-projects`

```bash
# List all memory projects
ccmem-cli.sh projects
```

#### `cleanup`

```bash
# View related projects for current project
ccmem-cli.sh related-projects -p "/repo/app"

# Manual link creation
ccmem-cli.sh link-projects "/repo/app" "/repo/lib-common" --reason "shared architecture"

# Remove link
ccmem-cli.sh unlink-projects "/repo/app" "/repo/lib-common"
```

Notes:
- Current project always takes priority
- Auto-inject and recall add at most 1-2 related project memories
- Worktree / parent-child projects automatically establish strong links

```bash
# Default: Safe cleanup, only removes low-priority temporary memories
ccmem-cli.sh cleanup

# Aggressive: Extends to all expired and aged working memories
ccmem-cli.sh cleanup --aggressive
```

## Configuration

Edit `~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/config/config.json`:

```json
{
  "memory_db": "~/.claude/cc-mem/memory.db",
  "failed_queue_dir": "/tmp/ccmem_failed_queue",
  "debug_log": "/tmp/ccmem_debug.log",
  "markdown_export_path": "~/cc-mem-export",
  "cleanup": {
    "throttle_seconds": 43200,
    "growth_threshold": 100,
    "growth_window_seconds": 3600
  },
  "preview": {
    "durable_max_chars": 320,
    "working_max_chars": 220,
    "temporary_max_chars": 180
  },
  "hooks": {
    "post_tool_use_flush_lines": 3
  },
  "injection": {
    "session_start_limit": 3,
    "recall_limit": 3,
    "related_project_limit": 1
  }
}
```

Key configuration options:

- `memory_db`
- `failed_queue_dir`
- `debug_log`
- `cleanup.*`
- `preview.*`
- `hooks.post_tool_use_flush_lines`
- `injection.session_start_limit`
- `injection.recall_limit`
- `injection.related_project_limit`
- `markdown_export_path`

## Hooks

### SessionStart Hook

Executes automatically at session start:

1. Records session start
2. Loads high-value memories by `project_root`
3. Supplements 1 related project memory if needed
4. Appends timeline hint for consecutive debug/decision chains
5. Outputs structured `<cc-mem-context>` injection block

### SessionEnd Hook

Executes automatically at session end:

1. Updates session status and summary
2. Checks for uncommitted operation logs
3. Writes remaining logs as final fallback memory
4. Queues failed writes locally
5. Triggers opportunistic cleanup, ending session

### PostToolUse Hook

Accumulates operation records after tool use:

- **Trigger tools**: Edit, Write, Bash
- **Records**: File changes, command execution
- **Flush threshold**: Auto-saves every 3 operations

### UserPromptSubmit Hook

Batch saves memories before user input, performs lightweight recall:

- **Rule Classification**: Derives `debug/solution/decision/pattern/context` from source, summary, content, tags, concepts
- **Batch Save**: Commits accumulated operation records to database
- **Query Recall**: Retrieves 2-3 relevant summaries based on current prompt
- **Chinese Support**: FTS priority, LIKE fallback for insufficient results
- **Output**: stdout only outputs structured recall injection block
- **Failure Recovery**: Failed writes are queued locally
- **Session Fallback**: SessionEnd Hook saves remaining records

**Data Safety**: Three-layer capture mechanism reduces risk of operation loss from unexpected session interruption.

## Markdown Export Format

Exported Markdown files contain:

- Frontmatter metadata
- Summary heading
- Full content
- Project and tag metadata

Export location: Specified by `-o` parameter or config file (default: `~/cc-mem-export`)

## Comparison

| Feature | **CC-mem** | claude-mem | memU | mem0 |
|---------|------------|------------|------|------|
| **Language** | Bash | TypeScript | Python | Python |
| **Dependencies** | SQLite | Node/Bun + SQLite + Chroma | Python | Python |
| **Database** | SQLite + FTS5 | SQLite + FTS5 + Chroma | SQLite / Postgres / pgvector | Vector DB primary |
| **Vector Search** | ❌ | ✅ Chroma hybrid | ✅ pgvector / vector | ✅ Multiple vector backends |
| **Memory History** | ✅ | ✅ | ✅ | ✅ |
| **Deduplication** | ✅ Content hash | ✅ | ✅ | ✅ |
| **Concept Tags** | ✅ Auto-recognition | ✅ | ✅ | ✅ |
| **Tiered Retrieval** | ✅ | ✅ | ✅ | ⚠️ Generic |
| **Hooks Integration** | ✅ | ✅ | ❌ Native hooks | ❌ Native hooks |
| **Graph Memory** | ❌ | ❌ | ✅ | ✅ Optional |
| **MCP Tools** | ✅ | ✅ | ❌ | ✅ |
| **Web UI** | ❌ | ✅ | ❌ | ✅ |
| **Multimodal** | ❌ | ❌ | ✅ | ✅ |

## Acknowledgments

CC-mem references the following excellent projects for feature inspiration:

- **[claude-mem](https://github.com/thedotmack/claude-mem)** - Hooks integration architecture, session context file design
- **[memU](https://github.com/NevaMind-AI/memU)** - Memory as filesystem concept, Proactive Memory design
- **[mem0](https://github.com/mem0ai/mem0)** - Fact extraction prompts, memory history tracking, test framework reference
- **[RTK](https://github.com/rtk-ai/rtk)** - Tiered filtering, failure preservation, throttling and degradation strategies

CC-mem is positioned as a lightweight alternative, implemented in pure Bash, focused on simple personal use cases.

---

## Troubleshooting

### Database Not Initialized

```bash
~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/bin/ccmem-cli.sh init
```

### Permission Issues

```bash
chmod +x ~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/bin/*.sh
chmod +x ~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/hooks/*.sh
```

### Memories Not Found

1. Check if project path matches
2. Try global search without `-p` parameter
3. Check tag spelling

## Privacy & Security

- All data stored locally
- Sensitive content filtering supported (e.g., `<private>` tags)
- Project-level memory isolation (based on `project_root`)
- Expired data cleanup supported (manual `cleanup`, hooks also perform opportunistic cleanup)

## License

MIT
