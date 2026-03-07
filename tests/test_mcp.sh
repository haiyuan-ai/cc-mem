#!/bin/bash
# CC-Mem MCP Server 测试

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$SCRIPT_DIR/mcp/server.py"
CLI="$SCRIPT_DIR/bin/ccmem-cli.sh"

source "$SCRIPT_DIR/tests/test_framework.sh"

describe "MCP Server"

it "应该列出核心工具"
test_mcp_lists_core_tools() {
    local result
    result=$(python3 - "$SERVER" <<'PY'
import json
import subprocess
import sys

server = sys.argv[1]
p = subprocess.Popen(
    ["python3", server],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

def send(obj):
    payload = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    p.stdin.write(f"Content-Length: {len(payload)}\r\n\r\n".encode("utf-8"))
    p.stdin.write(payload)
    p.stdin.flush()

def recv():
    headers = {}
    while True:
        line = p.stdout.readline()
        if line in (b"\r\n", b"\n", b""):
            break
        k, v = line.decode("utf-8").split(":", 1)
        headers[k.strip().lower()] = v.strip()
    length = int(headers["content-length"])
    return json.loads(p.stdout.read(length).decode("utf-8"))

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
recv()
send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
resp = recv()
print(json.dumps(resp["result"]["tools"], ensure_ascii=False))
p.terminate()
PY
)
    assert_contains "$result" "ccmem_capture" "应列出 ccmem_capture"
    assert_contains "$result" "ccmem_search" "应列出 ccmem_search"
    assert_contains "$result" "ccmem_get" "应列出 ccmem_get"
    assert_contains "$result" "ccmem_timeline" "应列出 ccmem_timeline"
    assert_contains "$result" "ccmem_inject_context" "应列出 ccmem_inject_context"
    assert_contains "$result" "ccmem_recall" "应列出 ccmem_recall"
}

it "应该通过 MCP 捕获并 recall 记忆"
test_mcp_capture_and_recall() {
    local project="/tmp/mcp-project"
    mkdir -p "$project"
    local result
    result=$(python3 - "$SERVER" "$project" <<'PY'
import json
import subprocess
import sys

server = sys.argv[1]
project = sys.argv[2]
p = subprocess.Popen(
    ["python3", server],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)

def send(obj):
    payload = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    p.stdin.write(f"Content-Length: {len(payload)}\r\n\r\n".encode("utf-8"))
    p.stdin.write(payload)
    p.stdin.flush()

def recv():
    headers = {}
    while True:
        line = p.stdout.readline()
        if line in (b"\r\n", b"\n", b""):
            break
        k, v = line.decode("utf-8").split(":", 1)
        headers[k.strip().lower()] = v.strip()
    length = int(headers["content-length"])
    return json.loads(p.stdout.read(length).decode("utf-8"))

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
recv()
send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

send({
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
        "name": "ccmem_capture",
        "arguments": {
            "project_path": project,
            "category": "decision",
            "tags": "mcp,test",
            "summary": "MCP 保存的决策",
            "content": "MCP 保存的决策内容"
        }
    }
})
capture_resp = recv()

send({
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
        "name": "ccmem_recall",
        "arguments": {
            "project_path": project,
            "query": "决策",
            "limit": 2
        }
    }
})
recall_resp = recv()

print(json.dumps({
    "capture": capture_resp["result"]["content"][0]["text"],
    "recall": recall_resp["result"]["content"][0]["text"]
}, ensure_ascii=False))
p.terminate()
PY
)
    assert_contains "$result" "记忆已存储" "MCP capture 应成功存储"
    assert_contains "$result" "<cc-mem-recall>" "MCP recall 应返回 recall block"
    assert_contains "$result" "MCP 保存的决策" "MCP recall 应包含刚保存的摘要"

    local stored_count
    stored_count=$(db_query "SELECT COUNT(*) FROM memories WHERE project_path = '$project';")
    assert_equals "1" "$stored_count" "MCP capture 应写入数据库"
}

setup_test_db
test_mcp_lists_core_tools
test_mcp_capture_and_recall
print_summary

