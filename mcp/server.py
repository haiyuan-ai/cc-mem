#!/usr/bin/env python3
"""Minimal stdio MCP server for CC-Mem."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List


REPO_ROOT = Path(__file__).resolve().parents[1]
CLI_PATH = REPO_ROOT / "bin" / "ccmem-cli.sh"
LIB_PATH = REPO_ROOT / "lib" / "sqlite.sh"
SERVER_VERSION = "1.5.2"


TOOLS: List[Dict[str, Any]] = [
    {
        "name": "ccmem_capture",
        "description": "Capture and save a memory into CC-Mem.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "content": {"type": "string", "description": "Memory content to save."},
                "category": {
                    "type": "string",
                    "enum": ["decision", "solution", "pattern", "debug", "context"],
                    "description": "Memory category.",
                },
                "project_path": {"type": "string", "description": "Project path scope."},
                "tags": {"type": "string", "description": "Comma-separated tags."},
                "summary": {"type": "string", "description": "Optional custom summary."},
                "concepts": {"type": "string", "description": "Optional concept tags."},
                "session_id": {"type": "string", "description": "Optional session ID."},
            },
            "required": ["content"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ccmem_search",
        "description": "Search related memories using staged retrieval.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query."},
                "project_path": {"type": "string", "description": "Project path scope."},
                "category": {
                    "type": "string",
                    "enum": ["decision", "solution", "pattern", "debug", "context"],
                },
                "limit": {"type": "integer", "minimum": 1, "default": 10},
            },
            "additionalProperties": False,
        },
    },
    {
        "name": "ccmem_get",
        "description": "Get full details for one or more memory IDs.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "memory_ids": {
                    "type": "array",
                    "items": {"type": "string"},
                    "minItems": 1,
                    "description": "Memory IDs to fetch.",
                }
            },
            "required": ["memory_ids"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ccmem_timeline",
        "description": "Get timeline context around a memory anchor.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "anchor_id": {"type": "string", "description": "Anchor memory ID."},
                "before": {"type": "integer", "minimum": 0, "default": 3},
                "after": {"type": "integer", "minimum": 0, "default": 3},
            },
            "required": ["anchor_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ccmem_inject_context",
        "description": "Generate structured startup injection context for a project.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project_path": {"type": "string", "description": "Project path scope."},
                "limit": {"type": "integer", "minimum": 1, "default": 3},
            },
            "required": ["project_path"],
            "additionalProperties": False,
        },
    },
    {
        "name": "ccmem_recall",
        "description": "Generate query-aware recall context for a project and prompt.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project_path": {"type": "string", "description": "Project path scope."},
                "query": {"type": "string", "description": "Current user request."},
                "limit": {"type": "integer", "minimum": 1, "default": 3},
            },
            "required": ["project_path", "query"],
            "additionalProperties": False,
        },
    },
]


def write_message(message: Dict[str, Any]) -> None:
    payload = json.dumps(message, ensure_ascii=False).encode("utf-8")
    sys.stdout.write(f"Content-Length: {len(payload)}\r\n\r\n")
    sys.stdout.flush()
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()


def read_message() -> Dict[str, Any] | None:
    headers: Dict[str, str] = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        name, value = line.decode("utf-8").split(":", 1)
        headers[name.strip().lower()] = value.strip()

    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    payload = sys.stdin.buffer.read(length)
    return json.loads(payload.decode("utf-8"))


def tool_text_result(text: str, is_error: bool = False) -> Dict[str, Any]:
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def run_cli(args: List[str], stdin_text: str | None = None) -> Dict[str, Any]:
    env = os.environ.copy()
    proc = subprocess.run(
        [str(CLI_PATH), *args],
        input=stdin_text,
        text=True,
        capture_output=True,
        env=env,
        cwd=str(REPO_ROOT),
    )
    text = proc.stdout.strip()
    if proc.stderr.strip():
        text = f"{text}\n{proc.stderr.strip()}".strip()
    return tool_text_result(text or "(no output)", is_error=proc.returncode != 0)


def run_recall(project_path: str, query: str, limit: int) -> Dict[str, Any]:
    proc = subprocess.run(
        [
            "bash",
            "-lc",
            'source "$1"; [ -f "$CCMEM_MEMORY_DB" ] || init_db >/dev/null 2>&1; generate_query_recall_context "$2" "$3" "$4"',
            "ccmem-mcp",
            str(LIB_PATH),
            project_path,
            query,
            str(limit),
        ],
        text=True,
        capture_output=True,
        cwd=str(REPO_ROOT),
        env=os.environ.copy(),
    )
    text = proc.stdout.strip()
    if proc.stderr.strip():
        text = f"{text}\n{proc.stderr.strip()}".strip()
    return tool_text_result(text or "(no output)", is_error=proc.returncode != 0)


def handle_tool_call(name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
    if name == "ccmem_capture":
        args = ["capture"]
        if arguments.get("project_path"):
            args += ["-p", arguments["project_path"]]
        if arguments.get("category"):
            args += ["-c", arguments["category"]]
        if arguments.get("tags"):
            args += ["-t", arguments["tags"]]
        if arguments.get("summary"):
            args += ["-m", arguments["summary"]]
        if arguments.get("concepts"):
            args += ["--concepts", arguments["concepts"]]
        if arguments.get("session_id"):
            args += ["-s", arguments["session_id"]]
        return run_cli(args, stdin_text=arguments["content"])

    if name == "ccmem_search":
        args = ["search"]
        if arguments.get("project_path"):
            args += ["-p", arguments["project_path"]]
        if arguments.get("query"):
            args += ["-q", arguments["query"]]
        if arguments.get("category"):
            args += ["-c", arguments["category"]]
        if arguments.get("limit"):
            args += ["-l", str(arguments["limit"])]
        return run_cli(args)

    if name == "ccmem_get":
        return run_cli(["get", *arguments["memory_ids"]])

    if name == "ccmem_timeline":
        args = ["timeline", "-a", arguments["anchor_id"]]
        args += ["-b", str(arguments.get("before", 3))]
        args += ["-A", str(arguments.get("after", 3))]
        return run_cli(args)

    if name == "ccmem_inject_context":
        args = ["inject-context", "-p", arguments["project_path"]]
        args += ["-l", str(arguments.get("limit", 3))]
        return run_cli(args)

    if name == "ccmem_recall":
        return run_recall(
            project_path=arguments["project_path"],
            query=arguments["query"],
            limit=int(arguments.get("limit", 3)),
        )

    return tool_text_result(f"Unknown tool: {name}", is_error=True)


def handle_request(message: Dict[str, Any]) -> Dict[str, Any] | None:
    method = message.get("method")
    req_id = message.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "cc-mem", "version": SERVER_VERSION},
            },
        }

    if method == "notifications/initialized":
        return None

    if method == "ping":
        return {"jsonrpc": "2.0", "id": req_id, "result": {}}

    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS}}

    if method == "tools/call":
        params = message.get("params", {})
        name = params.get("name")
        arguments = params.get("arguments", {})
        try:
            result = handle_tool_call(name, arguments)
        except Exception as exc:
            result = tool_text_result(f"Internal error: {exc}", is_error=True)
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": result,
        }

    if req_id is not None:
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": f"Method not found: {method}"},
        }
    return None


def main() -> int:
    while True:
        message = read_message()
        if message is None:
            return 0
        response = handle_request(message)
        if response is not None:
            write_message(response)


if __name__ == "__main__":
    raise SystemExit(main())
