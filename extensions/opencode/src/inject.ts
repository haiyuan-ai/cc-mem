import { injectContext } from "./mcp-client.js"

export async function appendInjectContext(system: string[], projectPath: string) {
  if (!projectPath) return
  const result = await injectContext({ project_path: projectPath, limit: 3 }).catch(() => null)
  const text = result?.content?.[0]?.text?.trim()
  if (!text || text === "(no output)") return
  system.push(text)
}
