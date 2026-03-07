#!/bin/bash
# Stop Hook - 会话停止/中断时捕获记忆和生成摘要
# 由 Claude Code hooks 系统调用
# 与 SessionEnd 的区别：Stop 可以访问 transcript 文件

# 不设置 set -e，允许脚本继续执行即使部分命令失败

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CLI="$PLUGIN_DIR/bin/ccmem-cli.sh"

# 调试日志文件
DEBUG_LOG="/tmp/ccmem_debug.log"
echo "[stop] $(date): START" >> "$DEBUG_LOG"

# 从 stdin 读取 hook 输入（JSON 格式）
INPUT=$(cat)
echo "[stop] $(date): INPUT length=${#INPUT}" >> "$DEBUG_LOG"

# 从 stdin JSON 中解析字段
SESSION_ID=""
TRANSCRIPT_PATH=""
PROJECT_PATH="${PWD}"

if [ -n "$INPUT" ] && [ "$INPUT" != "" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    # 如果 cwd 在输入中，使用它
    local_cwd=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    if [ -n "$local_cwd" ]; then
        PROJECT_PATH="$local_cwd"
    fi
    echo "[stop] $(date): session_id=$SESSION_ID, transcript_path=$TRANSCRIPT_PATH" >> "$DEBUG_LOG"
fi

# 回退到环境变量或 PID
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="${CLAUDE_SESSION_ID:-$$}"
    echo "[stop] $(date): using fallback SESSION_ID=$SESSION_ID" >> "$DEBUG_LOG"
fi

# 加载库文件
if [ -f "$PLUGIN_DIR/lib/sqlite.sh" ]; then
    source "$PLUGIN_DIR/lib/sqlite.sh"
    echo "[stop] $(date): Loaded sqlite.sh" >> "$DEBUG_LOG"
else
    echo "[stop] $(date): ERROR - sqlite.sh not found" >> "$DEBUG_LOG"
    exit 1
fi

if [ -f "$PLUGIN_DIR/lib/llm.sh" ]; then
    source "$PLUGIN_DIR/lib/llm.sh"
    echo "[stop] $(date): Loaded llm.sh" >> "$DEBUG_LOG"
fi

# 从 transcript 文件提取最后一条助手消息
extract_last_assistant_message() {
    local transcript_path="$1"

    if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
        echo ""
        return
    fi

    # 读取 JSONL 文件，找到最后一条 assistant 消息
    # transcript 格式：每行是一个 JSON 对象，type 字段为 "assistant" 或 "user"
    local last_message=""

    # 从最后一行开始向前遍历
    local total_lines=$(wc -l < "$transcript_path" 2>/dev/null || echo "0")
    if [ "$total_lines" -eq 0 ]; then
        echo ""
        return
    fi

    # 反向读取文件（兼容 macOS 和 Linux），找到第一条 assistant 消息
    # macOS 使用 tail -r，Linux 使用 tac
    local reversed_lines
    if command -v tac &> /dev/null; then
        reversed_lines=$(tac "$transcript_path" 2>/dev/null)
    else
        reversed_lines=$(tail -r "$transcript_path" 2>/dev/null)
    fi

    while IFS= read -r line; do
        local msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        if [ "$msg_type" = "assistant" ]; then
            # 提取消息内容
            local content=$(echo "$line" | jq -r '.message.content // empty' 2>/dev/null)
            if [ -n "$content" ]; then
                # 如果是字符串类型
                if echo "$line" | jq -e '.message.content | type == "string"' > /dev/null 2>&1; then
                    last_message="$content"
                    break
                # 如果是数组类型（包含多个 content block）
                elif echo "$line" | jq -e '.message.content | type == "array"' > /dev/null 2>&1; then
                    # 提取所有 text 类型的 content
                    last_message=$(echo "$line" | jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null | tr '\n' ' ')
                    break
                fi
            fi
        fi
    done <<< "$reversed_lines"

    echo "$last_message"
}

# 生成会话摘要
generate_session_summary() {
    local last_message="$1"
    local operation_log="$2"

    local summary=""

    # 如果有最后一条助手消息，提取关键信息
    if [ -n "$last_message" ]; then
        # 提取第一行非空行作为摘要基础
        local first_line=$(echo "$last_message" | grep -v '^$' | head -1)
        # 限制长度
        if [ "${#first_line}" -gt 150 ]; then
            first_line="${first_line:0:150}..."
        fi
        summary="最后工作: $first_line"
    fi

    # 如果有操作日志，添加操作统计
    if [ -n "$operation_log" ]; then
        local file_change_count=$(echo "$operation_log" | grep -c '\[FILE_CHANGE\]' 2>/dev/null || echo "0")
        local bash_count=$(echo "$operation_log" | grep -c '\[BASH\]' 2>/dev/null || echo "0")

        if [ "$file_change_count" -gt 0 ] || [ "$bash_count" -gt 0 ]; then
            local stats="操作统计: "
            [ "$file_change_count" -gt 0 ] && stats="${stats}Files=${file_change_count} "
            [ "$bash_count" -gt 0 ] && stats="${stats}Bash=${bash_count} "

            if [ -n "$summary" ]; then
                summary="$summary | $stats"
            else
                summary="$stats"
            fi
        fi
    fi

    echo "$summary"
}

# 主逻辑
main() {
    echo "[stop] $(date): PROJECT_PATH=$PROJECT_PATH" >> "$DEBUG_LOG"

    # 从 transcript 提取最后一条助手消息
    local last_assistant_message=""
    if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
        last_assistant_message=$(extract_last_assistant_message "$TRANSCRIPT_PATH")
        echo "[stop] $(date): Extracted last assistant message, length=${#last_assistant_message}" >> "$DEBUG_LOG"
    else
        echo "[stop] $(date): No transcript path available" >> "$DEBUG_LOG"
    fi

    # 检查操作日志
    LOG_FILE="/tmp/ccmem_${SESSION_ID}.log"
    local operation_log=""
    if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        operation_log=$(cat "$LOG_FILE")
        echo "[stop] $(date): Found operation log, length=${#operation_log}" >> "$DEBUG_LOG"
    fi

    # 生成会话摘要
    local session_summary=$(generate_session_summary "$last_assistant_message" "$operation_log")
    echo "[stop] $(date): Generated summary: $session_summary" >> "$DEBUG_LOG"

    # 更新会话记录（使用 stop 状态，与 completed 区分）
    local msg_count=0
    if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
        msg_count=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null || echo "0")
    fi

    # 更新会话（标记为 stopped 状态）
    sqlite3 "$MEMORY_DB" <<EOF
UPDATE sessions
SET end_time = CURRENT_TIMESTAMP,
    message_count = $msg_count,
    summary = '$(echo "$session_summary" | sed "s/'/''/g")',
    status = 'stopped'
WHERE id = '$SESSION_ID';
EOF
    echo "[stop] $(date): Updated session record with stopped status" >> "$DEBUG_LOG"

    # 捕获操作日志中的记忆（如果有）
    if [ -n "$operation_log" ]; then
        # 确定类别
        CATEGORY="context"
        if echo "$operation_log" | grep -qi "error\|fix\|debug\|fail"; then
            CATEGORY="debug"
        elif echo "$operation_log" | grep -qi "solution\|resolve\|workaround"; then
            CATEGORY="solution"
        elif echo "$operation_log" | grep -qi "decision\|choose\|select\|create\|add"; then
            CATEGORY="decision"
        fi

        # 捕获记忆
        echo "$operation_log" | "$CLI" capture \
            -p "$PROJECT_PATH" \
            -c "$CATEGORY" \
            -s "$SESSION_ID" \
            -t "stop,auto-captured" \
            --source "stop_summary" \
            --concepts "what-changed" \
            2>/dev/null || true

        # 清空日志
        > "$LOG_FILE"

        echo "[CC-Mem] 已保存停止时的记忆：$SESSION_ID"
        echo "[stop] $(date): Memory saved from operation log" >> "$DEBUG_LOG"
    fi

    # 如果有助手消息，也单独保存为一条记忆（记录最后的工作成果）
    if [ -n "$last_assistant_message" ]; then
        # 过滤私有内容
        local filtered_message="$last_assistant_message"
        if command -v perl &> /dev/null; then
            filtered_message=$(echo "$last_assistant_message" | perl -0777 -pe 's/<system-reminder>.*?<\/system-reminder>//gs')
            filtered_message=$(echo "$filtered_message" | perl -0777 -pe 's/<private>.*?<\/private>//gs')
        fi

        # 压缩内容（如果太长）
        if [ "${#filtered_message}" -gt 1000 ]; then
            filtered_message="${filtered_message:0:1000}..."
        fi

        # 保存为记忆
        echo -e "=== 会话停止时的最后回复 ===\n$filtered_message" | "$CLI" capture \
            -p "$PROJECT_PATH" \
            -c "context" \
            -s "$SESSION_ID" \
            -t "stop,final-response" \
            --source "stop_final_response" \
            --concepts "what-changed" \
            2>/dev/null || true

        echo "[stop] $(date): Saved final assistant message as memory" >> "$DEBUG_LOG"
    fi

    echo "[CC-Mem] 会话已停止：$SESSION_ID"
    echo "[stop] $(date): END" >> "$DEBUG_LOG"
}

# 执行主逻辑
main
