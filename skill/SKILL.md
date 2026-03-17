---
name: cc-mem
description: Project-specific memory plugin with search and capture.

triggers:
  - /cc-mem
  - /ccmem
category: productivity
author: haiyuan-ai
version: 1.5.3
---

# CC-Mem

Project-scoped memory management (NOT Claude's built-in memory).

## Commands

```
/cc-mem status              # Database status
/cc-mem list [-l 10]        # List recent memories
/cc-mem search <keyword>    # Search by content
/cc-mem stats [--days 14]   # Show statistics
/cc-mem capture <content>   # Create memory manually
/cc-mem export [-o path]    # Export to Markdown
/cc-mem retry               # Retry failed captures
/cc-mem cleanup             # Remove expired memories
/cc-mem help                # Show help
```

## Comparison

| Feature | CC-Mem | Claude Memory |
|---------|--------|---------------|
| Scope | Per-project | Global |
| Search | ✅ | ❌ |
| Hooks | Session/Tool/Stop | SessionStart |
| Export | ✅ | ❌ |

## Install

```bash
curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/install.sh | bash
```

**Database:** `~/.claude/cc-mem/memory.db`

**GitHub:** https://github.com/haiyuan-ai/cc-mem
