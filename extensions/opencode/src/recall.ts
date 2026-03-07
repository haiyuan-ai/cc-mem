import { recallContext } from "./mcp-client.js"

export async function buildRecallContext(projectPath: string, query: string) {
  if (!projectPath || !query?.trim()) return ""
  const result = await recallContext({
    project_path: projectPath,
    query,
    limit: 2
  }).catch(() => null)
  return result?.content?.[0]?.text?.trim() || ""
}
