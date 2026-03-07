# OpenCode Extension for cc-mem

This extension connects OpenCode events to the local `cc-mem` MCP server and
provides three behaviors:

- session prewarm via `ccmem_inject_context`
- query-aware recall via `ccmem_recall`
- tool-result capture via `ccmem_capture`

## Experimental status

This extension is currently experimental.

It is intended to get OpenCode closer to the Claude Code memory experience, but
it is not yet a production-stable integration layer.

## Current scope

The current extension is intentionally minimal:

- `experimental.chat.system.transform` appends `cc-mem` project context once
  per session
- `chat.message` appends recall context for user text messages
- `tool.execute.after` captures high-signal tool output with local denoising
  and truncation
- MCP calls fail open, so memory issues do not block the main OpenCode flow

It does not yet implement:

- session compaction capture
- tool-specific structured capture rules
- batching or deduplicated capture queues
- host-managed MCP tool invocation from the OpenCode plugin layer

## Requirements

- `python3`
- the `cc-mem` repo available locally
- a working `cc-mem` database at the default location or via `MEMORY_DB`
- local extension dependencies installed via `bun install` or `npm install`

The extension currently talks directly to:

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

After installing dependencies, build the extension first:

```bash
cd extensions/opencode
bun install
bun run build
```

Or:

```bash
cd extensions/opencode
npm install
npm run build
```

Then wire the built plugin into your local OpenCode setup:

```ts
import ccMemPlugin from "/Users/YOUR_USERNAME/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/extensions/opencode/dist/plugin.js"

export default {
  plugins: [ccMemPlugin]
}
```

Use [examples/opencode.config.ts](/Users/ningoo/github/cc-mem/extensions/opencode/examples/opencode.config.ts)
as a starting point.

## Local development

Install dependencies inside `extensions/opencode/`:

```bash
cd extensions/opencode
bun install
```

Or:

```bash
cd extensions/opencode
npm install
```

Then run:

```bash
bun run typecheck
```

Or:

```bash
npm run typecheck
```

This extension is kept separate from the core Bash runtime on purpose. The core
`cc-mem` project stays shell-first, while OpenCode integration can evolve
independently inside `extensions/opencode/`.
