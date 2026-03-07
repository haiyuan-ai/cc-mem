import { captureMemory } from "./mcp-client.js"

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
  if (tool === "read" || tool === "grep" || tool === "glob") return false
  if (output.trim().length < 20) return false
  return true
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
}) {
  const { projectPath, sessionID, tool, title, output } = args
  if (!projectPath || !shouldCapture(tool, output)) return

  const category = inferCategory(tool, title, output)
  const summary = buildSummary(tool, title, output)
  const content = `[OpenCode:${tool}] ${title}\n\n${output}`.trim()

  captureMemory({
    project_path: projectPath,
    session_id: sessionID,
    category,
    tags: `opencode,tool,${tool}`,
    summary,
    content
  })
}
