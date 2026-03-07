import { spawn } from "node:child_process"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = path.resolve(__dirname, "../../..")
const SERVER_PATH = path.join(REPO_ROOT, "mcp", "server.py")

type TextResult = {
  content: Array<{ type: "text"; text: string }>
  isError?: boolean
}

function buildMessage(payload: unknown) {
  const body = Buffer.from(JSON.stringify(payload), "utf8")
  const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "utf8")
  return Buffer.concat([header, body])
}

function parseMessage(buffer: Buffer) {
  const separator = buffer.indexOf("\r\n\r\n")
  if (separator === -1) throw new Error("Invalid MCP response header")
  const header = buffer.subarray(0, separator).toString("utf8")
  const match = header.match(/Content-Length:\s*(\d+)/i)
  if (!match) throw new Error("Missing Content-Length in MCP response")
  const length = Number(match[1])
  const body = buffer.subarray(separator + 4, separator + 4 + length).toString("utf8")
  return JSON.parse(body)
}

function callTool(name: string, args: Record<string, unknown>) {
  const initialize = buildMessage({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {}
  })
  const initialized = buildMessage({
    jsonrpc: "2.0",
    method: "notifications/initialized",
    params: {}
  })
  const call = buildMessage({
    jsonrpc: "2.0",
    id: 2,
    method: "tools/call",
    params: {
      name,
      arguments: args
    }
  })

  return new Promise<TextResult>((resolve, reject) => {
    const proc = spawn("python3", [SERVER_PATH], {
      cwd: REPO_ROOT,
      stdio: ["pipe", "pipe", "pipe"]
    })

    const stdoutChunks: Buffer[] = []
    const stderrChunks: Buffer[] = []
    const timeout = setTimeout(() => {
      proc.kill("SIGTERM")
      reject(new Error("cc-mem MCP server timed out"))
    }, 5000)

    proc.stdout.on("data", (chunk: Buffer) => {
      stdoutChunks.push(chunk)
    })

    proc.stderr.on("data", (chunk: Buffer) => {
      stderrChunks.push(chunk)
    })

    proc.on("error", (error) => {
      clearTimeout(timeout)
      reject(error)
    })

    proc.on("close", (code) => {
      clearTimeout(timeout)

      if (code !== 0) {
        const stderr = Buffer.concat(stderrChunks).toString("utf8").trim()
        reject(new Error(stderr || `MCP server exited with ${code}`))
        return
      }

      const output = Buffer.concat(stdoutChunks)
      const firstSep = output.indexOf("\r\n\r\n")
      if (firstSep === -1) {
        reject(new Error("Invalid MCP initialize response"))
        return
      }

      const firstHeader = output.subarray(0, firstSep).toString("utf8")
      const firstLenMatch = firstHeader.match(/Content-Length:\s*(\d+)/i)
      if (!firstLenMatch) {
        reject(new Error("Missing Content-Length in initialize response"))
        return
      }

      const firstLen = Number(firstLenMatch[1])
      const secondStart = firstSep + 4 + firstLen
      const second = output.subarray(secondStart)
      const response = parseMessage(second)
      resolve(response.result as TextResult)
    })

    proc.stdin.write(Buffer.concat([initialize, initialized, call]))
    proc.stdin.end()
  })
}

export function captureMemory(args: {
  content: string
  category?: string
  project_path: string
  tags?: string
  summary?: string
  concepts?: string
  session_id?: string
}) {
  return callTool("ccmem_capture", args)
}

export function injectContext(args: { project_path: string; limit?: number }) {
  return callTool("ccmem_inject_context", args)
}

export function recallContext(args: { project_path: string; query: string; limit?: number }) {
  return callTool("ccmem_recall", args)
}
