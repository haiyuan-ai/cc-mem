import { captureMemory } from "./mcp-client.js"

const MAX_CAPTURE_CHARS = 2000
const MAX_CAPTURE_LINES = 24

function inferCategory(tool: string, title: string, output: string) {
  const text = `${tool} ${title} ${output}`.toLowerCase()
  if (/(fix|fixed|修复|解决|workaround)/.test(text)) return "solution"
  if (/(debug|trace|排查|报错|error|timeout)/.test(text)) return "debug"
  if (/(decide|decision|采用|改为|方案|约定)/.test(text)) return "decision"
  if (/(pattern|convention|规范|统一|最佳实践)/.test(text)) return "pattern"
  return "context"
}

function shouldCapture(tool: string, output: string) {
  if (!output?.trim()) return false
  if (/(^|[_-])(read|grep|glob|find|search|list|ls|stat|pwd)([_-]|$)/i.test(tool)) return false
  if (!/(edit|write|patch|apply|bash|shell|command|create|delete|move|rename|file)/i.test(tool)) return false
  if (output.trim().length < 40) return false
  return true
}

function condenseOutput(title: string, output: string) {
  const lines = output
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)

  const selected: string[] = []

  if (title?.trim()) selected.push(title.trim())

  for (const line of lines) {
    if (selected.length >= MAX_CAPTURE_LINES) break
    if (
      /(fix|fixed|解决|修复|error|timeout|failed|success|updated|created|deleted|changed|warning|decision|pattern|debug|排查|原因|约定|统一)/i.test(
        line
      )
    ) {
      selected.push(line)
    }
  }

  for (const line of lines) {
    if (selected.length >= MAX_CAPTURE_LINES) break
    if (!selected.includes(line)) selected.push(line)
  }

  return selected.join("\n").slice(0, MAX_CAPTURE_CHARS).trim()
}

function buildSummary(tool: string, title: string, output: string) {
  if (title?.trim()) return title.trim().slice(0, 120)
  return `${tool}: ${output.trim().split("\n")[0]}`.slice(0, 120)
}

export async function captureToolResult(args: {
  projectPath: string
  sessionID: string
  tool: string
  title: string
  output: string
  metadata?: Record<string, unknown>
}) {
  const { projectPath, sessionID, tool, title, output } = args
  if (!projectPath || !shouldCapture(tool, output)) return

  const category = inferCategory(tool, title, output)
  const summary = buildSummary(tool, title, output)
  const content = `[OpenCode:${tool}] ${condenseOutput(title, output)}`.trim()

  await captureMemory({
    project_path: projectPath,
    session_id: sessionID,
    category,
    tags: `opencode,tool,${tool}`,
    summary,
    content
  }).catch(() => undefined)
}
