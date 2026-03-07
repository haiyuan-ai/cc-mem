import type { Plugin } from "@opencode-ai/plugin"
import type { Part } from "@opencode-ai/sdk"
import { randomUUID } from "node:crypto"

import { captureToolResult } from "./capture.js"
import { appendInjectContext } from "./inject.js"
import { buildRecallContext } from "./recall.js"

function extractQuery(parts: Part[]) {
  const text = parts
    .filter((part): part is Extract<Part, { type: "text" }> => part.type === "text")
    .map((part) => part.text.trim())
    .filter(Boolean)
    .join("\n")
    .trim()

  if (!text) return ""
  if (text.startsWith("/")) return ""
  return text
}

function makeSyntheticTextPart(sessionID: string, messageID: string, text: string): Part {
  return {
    id: randomUUID(),
    sessionID,
    messageID,
    type: "text",
    text,
    synthetic: true,
    metadata: {
      source: "cc-mem",
      kind: "recall"
    }
  }
}

const plugin: Plugin = async (input) => {
  const projectPath = input.directory || input.worktree

  return {
    "experimental.chat.system.transform": async (_event, output) => {
      await appendInjectContext(output.system, projectPath)
    },

    "chat.message": async (_event, output) => {
      const query = extractQuery(output.parts)
      if (!query) return

      const recall = await buildRecallContext(projectPath, query)
      if (!recall) return

      output.parts.push(
        makeSyntheticTextPart(output.message.sessionID, output.message.id, recall)
      )
    },

    "tool.execute.after": async (event, output) => {
      await captureToolResult({
        projectPath,
        sessionID: event.sessionID,
        tool: event.tool,
        title: output.title,
        output: output.output
      })
    }
  }
}

export default plugin
