# OpenCode Extension for cc-mem

This extension connects OpenCode events to the local `cc-mem` MCP server and
provides three behaviors:

- session prewarm via `ccmem_inject_context`
- query-aware recall via `ccmem_recall`
- tool-result capture via `ccmem_capture`

## Current scope

The current extension is intentionally minimal:

- `experimental.chat.system.transform` appends `cc-mem` project context
- `chat.message` appends recall context for user text messages
- `tool.execute.after` captures high-signal tool output

It does not yet implement:

- session compaction capture
- tool-specific structured capture rules
- batching or deduplicated capture queues

## Requirements

- `python3`
- the `cc-mem` repo available locally
- a working `cc-mem` database at the default location or via `MEMORY_DB`

The extension talks directly to:

- `mcp/server.py`

It does not require separately registering the `cc-mem` MCP server inside
OpenCode.

## Layout

- `src/plugin.ts`: OpenCode plugin entry
- `src/mcp-client.ts`: thin stdio MCP client for `cc-mem`
- `src/inject.ts`: session prewarm integration
- `src/recall.ts`: query recall integration
- `src/capture.ts`: tool-result capture integration
- `examples/opencode.config.ts`: minimal example config

## Minimal usage

Use the example config as a starting point and wire the plugin into your local
OpenCode setup.

This extension is kept separate from the core Bash runtime on purpose. The core
`cc-mem` project stays shell-first, while OpenCode integration can evolve
independently inside `extensions/opencode/`.
