#!/usr/bin/env python3
"""Minimal stdio MCP server for CC-Mem."""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List


REPO_ROOT = Path(__file__).resolve().parents[1]
CLI_PATH = REPO_ROOT / "bin" / "ccmem-cli.sh"
LIB_PATH = REPO_ROOT / "lib" / "sqlite.sh"
SERVER_VERSION = "1.5.3"


def validate_project_path(path: str) -> bool:
    """验证项目路径是否合法，防止路径遍历和命令注入。"""
    if not path or not isinstance(path, str):
        return False
    # 拒绝包含 null 字节、控制字符或 shell 特殊字符的路径
    if "\x00" in path or re.search(r"[<>&|;`$(){}\[\]\\*?\"']", path):
        return False
    # 路径必须是绝对路径或相对路径，但不能包含 ../ 遍历
    if ".." in path.split("/"):
        return False
    return True


def validate_query(query: str) -> bool:
    """验证查询字符串是否合法。"""
    if not query or not isinstance(query, str):
        return False
    # 拒绝 null 字节和控制字符
    if "\x00" in query or any(ord(c) < 32 and c not in "\n\r\t" for c in query):
        return False
    return True


def sanitize_limit(limit: int, default: int = 3, max_limit: int = 100) -> int:
    """验证并限制查询结果数量。"""
    try:
        limit = int(limit)
        if limit < 1:
            return default
        if limit > max_limit:
            return max_limit
        return limit
    except (ValueError, TypeError):
        return default


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
    # 验证输入参数
    if not validate_project_path(project_path):
        return tool_text_result(f"Invalid project_path: contains dangerous characters", is_error=True)
    if not validate_query(query):
        return tool_text_result(f"Invalid query: contains dangerous characters", is_error=True)

    limit = sanitize_limit(limit)

    # 使用 shlex.quote 对参数进行 shell 转义
    safe_project_path = shlex.quote(project_path)
    safe_query = shlex.quote(query)
    safe_limit = shlex.quote(str(limit))

    proc = subprocess.run(
        [
            "bash",
            "-lc",
            f'source "$1"; [ -f "$CCMEM_MEMORY_DB" ] || init_db >/dev/null 2>&1; generate_query_recall_context {safe_project_path} {safe_query} {safe_limit}',
            "ccmem-mcp",
            str(LIB_PATH),
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
        project_path = arguments.get("project_path", "")
        if project_path:
            if not validate_project_path(project_path):
                return tool_text_result("Invalid project_path: contains dangerous characters", is_error=True)
            args += ["-p", project_path]
        category = arguments.get("category", "")
        if category:
            if category not in ("decision", "solution", "pattern", "debug", "context"):
                return tool_text_result(f"Invalid category: {category}", is_error=True)
            args += ["-c", category]
        tags = arguments.get("tags", "")
        if tags:
            args += ["-t", tags]
        summary = arguments.get("summary", "")
        if summary:
            args += ["-m", summary]
        concepts = arguments.get("concepts", "")
        if concepts:
            args += ["--concepts", concepts]
        session_id = arguments.get("session_id", "")
        if session_id:
            args += ["-s", session_id]
        return run_cli(args, stdin_text=arguments.get("content", ""))

    if name == "ccmem_search":
        args = ["search"]
        project_path = arguments.get("project_path", "")
        if project_path:
            if not validate_project_path(project_path):
                return tool_text_result("Invalid project_path: contains dangerous characters", is_error=True)
            args += ["-p", project_path]
        query = arguments.get("query", "")
        if query:
            if not validate_query(query):
                return tool_text_result("Invalid query: contains dangerous characters", is_error=True)
            args += ["-q", query]
        category = arguments.get("category", "")
        if category:
            if category not in ("decision", "solution", "pattern", "debug", "context"):
                return tool_text_result(f"Invalid category: {category}", is_error=True)
            args += ["-c", category]
        limit = arguments.get("limit")
        if limit is not None:
            args += ["-l", str(sanitize_limit(limit))]
        return run_cli(args)

    if name == "ccmem_get":
        memory_ids = arguments.get("memory_ids", [])
        if not isinstance(memory_ids, list) or not memory_ids:
            return tool_text_result("memory_ids must be a non-empty list", is_error=True)
        # 验证每个 memory_id 格式
        for mid in memory_ids:
            if not isinstance(mid, str) or not re.match(r"^[a-zA-Z0-9_-]+$", mid):
                return tool_text_result(f"Invalid memory_id format: {mid}", is_error=True)
        return run_cli(["get", *memory_ids])

    if name == "ccmem_timeline":
        anchor_id = arguments.get("anchor_id", "")
        if not isinstance(anchor_id, str) or not re.match(r"^[a-zA-Z0-9_-]+$", anchor_id):
            return tool_text_result(f"Invalid anchor_id format: {anchor_id}", is_error=True)
        args = ["timeline", "-a", anchor_id]
        before = arguments.get("before", 3)
        after = arguments.get("after", 3)
        try:
            before = max(0, int(before))
            after = max(0, int(after))
        except (ValueError, TypeError):
            return tool_text_result("before/after must be non-negative integers", is_error=True)
        args += ["-b", str(before)]
        args += ["-A", str(after)]
        return run_cli(args)

    if name == "ccmem_inject_context":
        project_path = arguments.get("project_path", "")
        if not validate_project_path(project_path):
            return tool_text_result("Invalid project_path: contains dangerous characters", is_error=True)
        args = ["inject-context", "-p", project_path]
        limit = arguments.get("limit", 3)
        args += ["-l", str(sanitize_limit(limit, default=3, max_limit=50))]
        return run_cli(args)

    if name == "ccmem_recall":
        project_path = arguments.get("project_path", "")
        if not validate_project_path(project_path):
            return tool_text_result("Invalid project_path: contains dangerous characters", is_error=True)
        query = arguments.get("query", "")
        if not validate_query(query):
            return tool_text_result("Invalid query: contains dangerous characters", is_error=True)
        limit = arguments.get("limit", 3)
        try:
            limit = int(limit)
        except (ValueError, TypeError):
            limit = 3
        return run_recall(
            project_path=project_path,
            query=query,
            limit=limit,
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
