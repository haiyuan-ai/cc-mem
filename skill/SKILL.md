---
name: cc-mem
description: Lightweight local memory plugin for Claude Code sessions.

triggers:
  - /cc-mem
  - /ccmem
author: haiyuan-ai
version: 1.5.4
---

# CC-Mem

Lightweight local memory management for Claude Code.

## Commands

```
/cc-mem status              # Check database status
/cc-mem list [-l 10]        # List recent memories
/cc-mem search <keyword>    # Search memories
/cc-mem stats [--days 14]   # Show statistics
/cc-mem capture <content>   # Create a memory
/cc-mem export [-o path]    # Export to Markdown
/cc-mem retry               # Retry failed captures
/cc-mem cleanup             # Remove expired memories
/cc-mem help                # Show help
```
