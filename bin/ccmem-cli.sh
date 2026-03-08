#!/bin/bash
# CC-Mem CLI - 简易记忆管理工具
# 用法：ccmem-cli.sh <command> [options]

set -e

# 恢复 PATH（如果缺少核心工具）
if ! command -v dirname &> /dev/null; then
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CONFIG_DIR="$SCRIPT_DIR/config"

source "$LIB_DIR/sqlite.sh"
source "$LIB_DIR/content_utils.sh"
source "$LIB_DIR/classification.sh"

load_config() {
    export CCMEM_CONFIG_FILE="${CCMEM_CONFIG_FILE:-$CONFIG_DIR/config.json}"
    apply_runtime_config
}

resolve_effective_project_path() {
    local project_path="$1"
    if [ -n "$project_path" ]; then
        printf '%s\n' "$project_path"
    else
        pwd
    fi
}

build_default_summary() {
    local content="$1"
    printf '%s...\n' "${content:0:100}"
}

print_unknown_option() {
    echo "未知选项：$1"
    return 1
}

print_command_usage() {
    echo "用法：ccmem $1"
}

handle_store_memory_result() {
    local id="$1"
    local prefix="${2:-}"
    local private_warning="${3:-}"
    local success_message="${4:-记忆已存储}"
    if [[ "$id" == duplicate:* ]]; then
        echo "${prefix}跳过：内容已存在（重复记忆 ID: ${id#duplicate:}）"
        return 0
    fi
    if [[ "$id" == error:* ]]; then
        echo "${prefix}错误：存储记忆失败 - ${id#error:}"
        return 1
    fi
    if [ -n "$private_warning" ]; then
        echo "$private_warning"
    fi
    echo "${prefix}${success_message}"
    return 0
}

ensure_db_ready() {
    mkdir -p "$(dirname "$CCMEM_MEMORY_DB")"

    if [ ! -f "$CCMEM_MEMORY_DB" ]; then
        init_db >/dev/null 2>&1
        return
    fi

    local has_memories
    has_memories=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='memories';" 2>/dev/null || true)
    if [ "$has_memories" != "memories" ]; then
        init_db >/dev/null 2>&1
    fi
}

get_failed_capture_queue_dir() {
    printf '%s\n' "$CCMEM_FAILED_QUEUE_DIR"
}

get_debug_log_path() {
    printf '%s\n' "$CCMEM_DEBUG_LOG"
}

format_epoch_local() {
    local epoch="$1"

    if [ -z "$epoch" ] || [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "unknown"
        return
    fi

    if date -r "$epoch" "+%Y-%m-%d %H:%M:%S" >/dev/null 2>&1; then
        date -r "$epoch" "+%Y-%m-%d %H:%M:%S"
    elif date -d "@$epoch" "+%Y-%m-%d %H:%M:%S" >/dev/null 2>&1; then
        date -d "@$epoch" "+%Y-%m-%d %H:%M:%S"
    else
        printf '%s\n' "$epoch"
    fi
}

format_ratio_percent() {
    local numerator="${1:-0}"
    local denominator="${2:-0}"

    if [ -z "$denominator" ] || [ "$denominator" = "0" ]; then
        printf '%s\n' "0.0%%"
        return
    fi

    awk -v num="$numerator" -v den="$denominator" 'BEGIN {
        printf "%.1f%%\n", (num / den) * 100
    }'
}

format_decimal() {
    local numerator="${1:-0}"
    local denominator="${2:-1}"

    if [ -z "$denominator" ] || [ "$denominator" = "0" ]; then
        printf '%s\n' "0.0"
        return
    fi

    awk -v num="$numerator" -v den="$denominator" 'BEGIN {
        printf "%.1f\n", num / den
    }'
}

print_failed_queue_summary() {
    local queue_dir
    queue_dir=$(get_failed_capture_queue_dir)
    local total_count=0
    local latest_epoch=0
    local latest_time="none"
    local hook_summary=""

    echo "失败队列：$queue_dir"
    if [ ! -d "$queue_dir" ]; then
        echo "  状态：空"
        return
    fi

    total_count=$(find "$queue_dir" -type f -name 'failed_*' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$total_count" = "0" ]; then
        echo "  状态：空"
        return
    fi

    latest_epoch=$(find "$queue_dir" -type f -name 'failed_*' -exec stat -f '%m' {} \; 2>/dev/null | sort -nr | head -1)
    if [ -z "$latest_epoch" ]; then
        latest_epoch=$(find "$queue_dir" -type f -name 'failed_*' -exec stat -c '%Y' {} \; 2>/dev/null | sort -nr | head -1)
    fi
    latest_time=$(format_epoch_local "$latest_epoch")
    hook_summary=$(find "$queue_dir" -type f -name 'failed_*' 2>/dev/null | sed -E 's|.*/failed_([^_]+).*|\1|' | sort | uniq -c | awk '{printf "%s=%s ", $2, $1}' | sed 's/ $//')

    echo "  文件数：$total_count"
    echo "  最近失败：$latest_time"
    echo "  Hook 分布：${hook_summary:-unknown}"
}

print_recent_cleanup_summary() {
    local debug_log
    debug_log=$(get_debug_log_path)
    local latest_cleanup=""
    local latest_result=""

    echo "最近 Cleanup："
    if [ ! -f "$debug_log" ]; then
        echo "  状态：无记录"
        return
    fi

    latest_cleanup=$(grep '\[cleanup\].*mode=' "$debug_log" 2>/dev/null | tail -1 || true)
    latest_result=$(grep '\[cleanup\].*deleted=' "$debug_log" 2>/dev/null | tail -1 || true)

    if [ -z "$latest_cleanup" ] && [ -z "$latest_result" ]; then
        echo "  状态：无记录"
        return
    fi

    if [ -n "$latest_cleanup" ]; then
        echo "  最近触发：$latest_cleanup"
    fi
    if [ -n "$latest_result" ]; then
        echo "  最近结果：$latest_result"
    fi
}

show_help() {
    cat <<EOF
CC-Mem CLI - Claude Code 记忆管理工具

用法：ccmem-cli.sh <command> [options]

命令:
  init              初始化数据库
  capture           捕获当前会话记忆
  search            搜索记忆（三层检索第一步）
  recall            基于 query 生成 recall 注入块
  timeline          获取时间线上下文（三层检索第二步）
  get               获取记忆详情（三层检索第三步）
  history           查看记忆历史
  list              列出最近的记忆
  export            导出记忆到 Markdown
  retry             重试失败队列中的记忆写入
  inject-context    生成开场注入上下文
  projects          列出所有项目
  related-projects  列出关联项目
  link-projects     手动建立项目关联
  unlink-projects   删除项目关联
  refresh-project-links 刷新自动项目关联
  cleanup           清理过期记忆（默认安全模式）
  status            显示记忆库状态
  stats             显示最近记忆统计
  help              显示此帮助信息

示例:
  ccmem-cli.sh search -p "/path/to/project" -q "API endpoint"
  ccmem-cli.sh recall -p "/path/to/project" -q "SQLite timeout"
  ccmem-cli.sh timeline -a mem_xxx -b 3 -A 3
  ccmem-cli.sh get mem_123 mem_456
  ccmem-cli.sh capture -c "decision" -t "important,core"
  echo "重要模式" | ccmem-cli.sh capture -c "pattern" -t "react,hooks" -m "自定义摘要"
  ccmem-cli.sh export -o "~/exports"
  ccmem-cli.sh retry --dry-run
  ccmem-cli.sh related-projects -p "/path/to/project"
  ccmem-cli.sh stats --days 7
选项:
  -p, --project     项目路径
  -c, --category    记忆类别 (decision|solution|pattern|debug|context)
  -t, --tags        标签（逗号分隔）
  -m, --summary     自定义摘要
  --concepts        概念标签（how-it-works|problem-solution|gotcha|pattern|trade-off|why-it-exists|what-changed）
  -q, --query       检索关键词
  -o, --output      导出目录（默认：$HOME/cc-mem-export）
  -l, --limit       限制结果数量（默认：10）
  --hook            仅处理指定 hook 的失败项
  --dry-run         只显示将要处理的失败项，不执行写入
  -s, --session     会话 ID
  -h, --help        显示帮助

EOF
}

cmd_capture() {
    local project_path=""
    local category="context"
    local tags=""
    local summary=""
    local concepts=""
    local session_id="${CLAUDE_SESSION_ID:-$$}"
    local source="manual"
    local memory_kind=""
    local auto_inject_policy=""
    local project_root=""
    local expires_at=""
    local classification_confidence=""
    local classification_reason=""
    local classification_source=""
    local classification_version=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -c|--category) category="$2"; shift ;;
            -t|--tags) tags="$2"; shift ;;
            -m|--summary) summary="$2"; shift ;;
            --concepts) concepts="$2"; shift ;;
            -s|--session) session_id="$2"; shift ;;
            --source) source="$2"; shift ;;
            --memory-kind) memory_kind="$2"; shift ;;
            --inject-policy) auto_inject_policy="$2"; shift ;;
            --project-root) project_root="$2"; shift ;;
            --expires-at) expires_at="$2"; shift ;;
            --classification-confidence) classification_confidence="$2"; shift ;;
            --classification-reason) classification_reason="$2"; shift ;;
            --classification-source) classification_source="$2"; shift ;;
            --classification-version) classification_version="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    echo "捕获记忆..."
    echo "  会话 ID: $session_id"
    echo "  项目路径：${project_path:-未指定}"
    echo "  类别：$category"
    echo "  标签：${tags:-无}"
    echo "  概念：${concepts:-无}"

    # 如果没有指定项目路径，使用当前目录
    project_path="$(resolve_effective_project_path "$project_path")"

    # 更新项目访问记录
    update_project_access "$project_path" "$(basename "$project_path")" "$tags"

    # 创建/更新会话
    upsert_session "$session_id" "$project_path"

    # 如果从 stdin 读取内容
    if [ ! -t 0 ]; then
        local content=$(cat)
        if [ -n "$content" ]; then
            # 检查并过滤私有内容
            local filtered_content="$content"
            local private_warning=""

            if has_private_content "$content"; then
                filtered_content=$(filter_private_content "$content")
                private_warning="  警告：已过滤 <private> 标签内容"

                # 如果过滤后内容为空，不保存
                if [ -z "$(echo "$filtered_content" | tr -d '[:space:]')" ]; then
                    echo "  跳过：过滤私有内容后无有效内容"
                    return
                fi
            fi

            filtered_content=$(strip_injected_context_blocks "$filtered_content")

            if [ -z "$summary" ]; then
                summary=$(build_default_summary "$filtered_content")
            fi

            # 如果没有指定 concepts，尝试自动识别
            if [ -z "$concepts" ]; then
                concepts=$(detect_concepts "$filtered_content")
                if [ -n "$concepts" ]; then
                    echo "  自动识别概念：$concepts"
                fi
            fi

            local id=$(store_memory "$session_id" "$project_path" "$category" "$filtered_content" "$summary" "$tags" "$concepts" "$source" "$memory_kind" "$auto_inject_policy" "$project_root" "$expires_at" "$classification_confidence" "$classification_reason" "$classification_source" "$classification_version")

            if ! handle_store_memory_result "$id" "  " "$private_warning" "记忆 ID: $id"; then
                return 1
            fi
            echo "记忆已存储"
            return 0
        fi
    fi

    echo "没有捕获到内容（从 stdin 为空）"
}
cmd_search() {
    local project_path=""
    local query=""
    local category=""
    local limit=10
    local min_results=3

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -q|--query) query="$2"; shift ;;
            -c|--category) category="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            --min) min_results="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    echo "搜索记忆..."
    echo "  项目路径：$project_path"
    echo "  关键词：${query:-全部}"
    echo "  类别：${category:-全部}"
    echo "  限制：$limit (最小返回：$min_results)"
    echo ""

    # 使用分阶段检索（带充分性检查）
    local tmp_results
    tmp_results=$(mktemp "${TMPDIR:-/tmp}/ccmem-search.XXXXXX")
    retrieve_memories_staged "$project_path" "$query" "$category" "$limit" "$min_results" > "$tmp_results"
    local results
    results=$(cat "$tmp_results")
    rm -f "$tmp_results"

    if [ -n "$query" ]; then
        if contains_cjk "$query" && [ "${RETRIEVE_CJK_FALLBACK_USED:-0}" -eq 1 ]; then
            echo "  中文回退：已使用"
        else
            echo "  中文回退：未使用"
        fi
        echo ""
    fi
    echo "$results"
}

cmd_recall() {
    local project_path=""
    local query=""
    local limit
    limit=$(get_injection_recall_limit)

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -q|--query) query="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            -h|--help)
                print_command_usage "recall -p <project> -q <query> [-l limit]"
                echo "生成 query-aware recall 注入块"
                echo ""
                echo "选项："
                echo "  -p, --project    项目路径（默认当前目录）"
                echo "  -q, --query      当前请求关键词"
                echo "  -l, --limit      recall 结果数量（默认来自配置，缺省 3）"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    if [ -z "$query" ]; then
        print_command_usage "recall -p <project> -q <query> [-l limit]"
        return 1
    fi

    project_path="$(resolve_effective_project_path "$project_path")"
    generate_query_recall_context "$project_path" "$query" "$limit"
}

cmd_list() {
    local limit=20
    local project_path=""
    local project_path_escaped=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -l|--limit) limit="$2"; shift ;;
            -p|--project) project_path="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    local where_clause="WHERE 1=1"
    if [ -n "$project_path" ]; then
        project_path_escaped=$(sql_escape "$project_path")
        where_clause="WHERE project_path = '$project_path_escaped'"
    fi

    sqlite3 -header -column "$CCMEM_MEMORY_DB" <<EOF
SELECT id, datetime(timestamp_epoch, 'unixepoch', 'localtime') AS timestamp, category, concepts, summary, project_path, tags
FROM memories
$where_clause
ORDER BY timestamp_epoch DESC
LIMIT $limit;
EOF
}

cmd_export() {
    local output_dir=""
    local project_path=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -o|--output) output_dir="$2"; shift ;;
            -p|--project) project_path="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    # 配置优先级：命令行参数 > 配置文件 > 默认值
    if [ -z "$output_dir" ]; then
        output_dir=$(get_markdown_export_path)

        # 最终默认值
        if [ -z "$output_dir" ] || [ "$output_dir" = "null" ]; then
            output_dir="$HOME/cc-mem-export"
        fi
    fi

    echo "导出记忆到：$output_dir"

    # 使用简单 Markdown 导出（不需要 Obsidian）
    export_to_markdown "$output_dir" "$project_path"

    echo "导出完成"
}

retry_map_hook_metadata() {
    local hook_name="$1"

    case "$hook_name" in
        post-tool-use)
            printf '%s|%s|%s\n' "post_tool_use" "auto-captured" "what-changed"
            ;;
        user-prompt-submit)
            printf '%s|%s|%s\n' "user_prompt_submit" "auto-captured" "what-changed"
            ;;
        session-end)
            printf '%s|%s|%s\n' "session_end" "auto-captured,session-end" "what-changed"
            ;;
        stop)
            printf '%s|%s|%s\n' "stop_summary" "auto-captured,stop" "what-changed"
            ;;
        stop-final-response)
            printf '%s|%s|%s\n' "stop_final_response" "final-response,stop" "what-changed"
            ;;
        *)
            return 1
            ;;
    esac
}

retry_read_metadata() {
    local file_path="$1"
    local key="$2"

    awk -v target="$key" '
        BEGIN { found = "" }
        NR == 1 && $0 ~ /^# / {
            line = substr($0, 3)
            n = split(line, parts, " ")
            for (i = 1; i <= n; i++) {
                split(parts[i], pair, "=")
                if (pair[1] == target) {
                    print substr(parts[i], length(target) + 2)
                    exit
                }
            }
        }
    ' "$file_path"
}

retry_read_content() {
    local file_path="$1"

    awk '
        NR == 1 && $0 ~ /^# / { next }
        { print }
    ' "$file_path"
}

retry_process_file() {
    local file_path="$1"
    local hook_name=""
    local session_id=""
    local meta=""
    local source=""
    local tags=""
    local concepts=""
    local content=""
    local filtered_content=""
    local summary=""
    local classification_result=""
    local category=""
    local confidence=""
    local reason=""
    local memory_kind=""
    local auto_inject_policy=""
    local store_result=""

    hook_name=$(retry_read_metadata "$file_path" "hook")
    session_id=$(retry_read_metadata "$file_path" "session_id")

    if [ -z "$hook_name" ]; then
        printf '%s\n' "skip:missing-hook"
        return 0
    fi

    meta=$(retry_map_hook_metadata "$hook_name" || true)
    if [ -z "$meta" ]; then
        printf '%s\n' "skip:unsupported-hook"
        return 0
    fi

    source=$(printf '%s' "$meta" | cut -d'|' -f1)
    tags=$(printf '%s' "$meta" | cut -d'|' -f2)
    concepts=$(printf '%s' "$meta" | cut -d'|' -f3)
    content=$(retry_read_content "$file_path")
    filtered_content=$(strip_injected_context_blocks "$content")

    if [ -z "$(printf '%s' "$filtered_content" | tr -d '[:space:]')" ]; then
        printf '%s\n' "fail:empty-content"
        return 1
    fi

    summary=$(build_default_summary "$filtered_content")
    classification_result=$(classify_memory "$source" "$summary" "$filtered_content" "$tags" "$concepts")
    category=$(printf '%s' "$classification_result" | cut -d'|' -f1)
    confidence=$(printf '%s' "$classification_result" | cut -d'|' -f2)
    reason=$(printf '%s' "$classification_result" | cut -d'|' -f3-)
    memory_kind=$(infer_memory_kind "$source" "$category" "$confidence")
    auto_inject_policy=$(infer_auto_inject_policy "$source" "$category" "$confidence")

    if [ -z "$session_id" ]; then
        session_id="retry_$$"
    fi

    store_result=$(store_memory \
        "$session_id" \
        "" \
        "$category" \
        "$filtered_content" \
        "$summary" \
        "$tags" \
        "$concepts" \
        "$source" \
        "$memory_kind" \
        "$auto_inject_policy" \
        "" \
        "" \
        "$confidence" \
        "$reason" \
        "rule" \
        "rule-v2")

    case "$store_result" in
        duplicate:*)
            rm -f "$file_path"
            printf '%s\n' "duplicate:${store_result#duplicate:}"
            ;;
        error:*)
            printf '%s\n' "fail:${store_result#error:}"
            return 1
            ;;
        *)
            rm -f "$file_path"
            printf '%s\n' "success:$store_result"
            ;;
    esac
}

cmd_retry() {
    local queue_dir=""
    local dry_run=false
    local limit=""
    local hook_filter=""
    local files=()
    local file_path=""
    local scanned=0
    local matched=0
    local recovered=0
    local duplicates=0
    local failed=0
    local skipped=0
    local result=""
    local hook_name=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --dry-run) dry_run=true ;;
            --limit) limit="$2"; shift ;;
            --hook) hook_filter="$2"; shift ;;
            -h|--help)
                print_command_usage "retry [--dry-run] [--limit count] [--hook name]"
                echo "重试失败队列中的记忆写入。"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    queue_dir=$(get_failed_capture_queue_dir)
    if [ ! -d "$queue_dir" ]; then
        echo "失败队列为空"
        return 0
    fi

    while IFS= read -r file_path; do
        [ -n "$file_path" ] && files+=("$file_path")
    done < <(find "$queue_dir" -type f -name 'failed_*' | sort)

    if [ "${#files[@]}" -eq 0 ]; then
        echo "失败队列为空"
        return 0
    fi

    for file_path in "${files[@]}"; do
        scanned=$((scanned + 1))
        hook_name=$(retry_read_metadata "$file_path" "hook")
        if [ -n "$hook_filter" ] && [ "$hook_name" != "$hook_filter" ]; then
            continue
        fi
        matched=$((matched + 1))
        if [ -n "$limit" ] && [ "$matched" -gt "$limit" ]; then
            matched=$((matched - 1))
            break
        fi

        if [ "$dry_run" = true ]; then
            echo "将处理：$(basename "$file_path") hook=${hook_name:-unknown}"
            continue
        fi

        result=$(retry_process_file "$file_path" || true)
        case "$result" in
            success:*)
                recovered=$((recovered + 1))
                ;;
            duplicate:*)
                duplicates=$((duplicates + 1))
                ;;
            skip:*)
                skipped=$((skipped + 1))
                ;;
            fail:*)
                failed=$((failed + 1))
                echo "重试失败：$(basename "$file_path") ${result#fail:}"
                ;;
            *)
                failed=$((failed + 1))
                echo "重试失败：$(basename "$file_path") unknown"
                ;;
        esac
    done

    if [ "$dry_run" = true ]; then
        echo "将处理失败项：$matched"
        return 0
    fi

    echo "扫描失败项：$scanned"
    echo "匹配处理：$matched"
    echo "成功恢复：$recovered"
    echo "重复跳过：$duplicates"
    echo "跳过：$skipped"
    echo "恢复失败：$failed"
}

cmd_cleanup() {
    local days=30
    local mode="safe"
    local limit=100

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -d|--days) days="$2"; shift ;;
            --aggressive) mode="aggressive" ;;
            --limit) limit="$2"; shift ;;
            -h|--help)
                print_command_usage "cleanup [-d days] [--limit count] [--aggressive]"
                echo "默认执行安全清理，只删除低优先级临时记忆。"
                echo ""
                echo "选项："
                echo "  -d, --days        超龄阈值天数（默认 30）"
                echo "  --limit           单次最多删除条数（默认 100）"
                echo "  --aggressive      扩大到所有已过期记忆和超龄 working 记忆"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    local deleted_count
    deleted_count=$(cleanup_memories "$mode" "$days" "$limit")

    if [[ ! "$deleted_count" =~ ^[0-9]+$ ]]; then
        echo "错误：清理失败 - $deleted_count"
        return 1
    fi

    if [ "$mode" = "aggressive" ]; then
        echo "已清理 $deleted_count 条过期/超龄记忆（aggressive，days=$days，limit=$limit）"
    else
        echo "已清理 $deleted_count 条低优先级临时记忆（safe，days=$days，limit=$limit）"
    fi
}

cmd_projects() {
    echo "=== 项目列表 ==="
    echo ""
    list_projects
}

cmd_related_projects() {
    local project_path=""
    local limit=5
    local min_strength=70

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            --min-strength) min_strength="$2"; shift ;;
            -h|--help)
                print_command_usage "related-projects [-p project] [-l limit] [--min-strength score]"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    refresh_project_links "$project_path" >/dev/null 2>&1 || true

    local project_root
    project_root=$(resolve_project_root "$project_path")
    echo "=== 关联项目 ==="
    echo "主项目：$project_root"
    echo ""
    printf "%-40s %-14s %-8s %s\n" "target_root" "link_type" "strength" "reason"
    list_related_projects "$project_root" "$limit" "$min_strength" | awk -F'|' '
    {
        printf "%-40s %-14s %-8s %s\n", $1, $2, $3, $4
    }'
}

cmd_link_projects() {
    local source_root=""
    local target_root=""
    local link_type="manual"
    local strength=95
    local reason="manual link"
    local bidirectional=1

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --type) link_type="$2"; shift ;;
            --strength) strength="$2"; shift ;;
            --reason) reason="$2"; shift ;;
            --one-way) bidirectional=0 ;;
            -h|--help)
                print_command_usage "link-projects <source_root> <target_root> [--type manual] [--strength 95] [--reason 文本] [--one-way]"
                return
                ;;
            *)
                if [ -z "$source_root" ]; then
                    source_root="$1"
                elif [ -z "$target_root" ]; then
                    target_root="$1"
                else
                    echo "未知参数：$1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [ -z "$source_root" ] || [ -z "$target_root" ]; then
        print_command_usage "link-projects <source_root> <target_root> [--type manual] [--strength 95] [--reason 文本] [--one-way]"
        return 1
    fi

    link_projects "$source_root" "$target_root" "$link_type" "$strength" "$reason" "$bidirectional"
    echo "项目关联已建立：$source_root -> $target_root ($link_type, strength=$strength)"
    if [ "$bidirectional" = "1" ]; then
        echo "已同步建立反向关联"
    fi
}

cmd_unlink_projects() {
    local source_root=""
    local target_root=""
    local bidirectional=1

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --one-way) bidirectional=0 ;;
            -h|--help)
                print_command_usage "unlink-projects <source_root> <target_root> [--one-way]"
                return
                ;;
            *)
                if [ -z "$source_root" ]; then
                    source_root="$1"
                elif [ -z "$target_root" ]; then
                    target_root="$1"
                else
                    echo "未知参数：$1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [ -z "$source_root" ] || [ -z "$target_root" ]; then
        print_command_usage "unlink-projects <source_root> <target_root> [--one-way]"
        return 1
    fi

    unlink_projects "$source_root" "$target_root" "$bidirectional"
    echo "项目关联已删除：$source_root -> $target_root"
    if [ "$bidirectional" = "1" ]; then
        echo "已同步删除反向关联"
    fi
}

cmd_refresh_project_links() {
    local project_path=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -h|--help)
                print_command_usage "refresh-project-links [-p project]"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    refresh_project_links "$project_path"
    echo "已刷新项目关联：$(resolve_project_root "$project_path")"
}

cmd_history() {
    local memory_id=""
    local limit=10
    local recent=false

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -m|--memory) memory_id="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            -r|--recent) recent=true; shift ;;
            -h|--help) show_help; return ;;
            *)
                # 如果没有指定参数，默认为 memory_id
                if [ -z "$memory_id" ]; then
                    memory_id="$1"
                fi
                ;;
        esac
        shift
    done

    if [ "$recent" = true ]; then
        echo "=== 最近记忆历史 ==="
        echo ""
        get_recent_history "$limit"
    elif [ -n "$memory_id" ]; then
        echo "=== 记忆 $memory_id 的历史 ==="
        echo ""
        get_memory_history "$memory_id" "$limit"
    else
        echo "=== 最近记忆历史 ==="
        echo ""
        get_recent_history "$limit"
    fi
}

cmd_timeline() {
    local anchor_id=""
    local depth_before=3
    local depth_after=3

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -a|--anchor) anchor_id="$2"; shift ;;
            -b|--before) depth_before="$2"; shift ;;
            -A|--after) depth_after="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    if [ -z "$anchor_id" ]; then
        print_command_usage "timeline -a <memory_id> [-b before] [-A after]"
        return 1
    fi

    echo "=== 时间线上下文 ==="
    echo "  锚点：$anchor_id"
    echo "  前后范围：$depth_before / $depth_after"
    echo ""

    get_timeline "$anchor_id" "$depth_before" "$depth_after"
}

cmd_get() {
    local memory_ids=()

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--help) show_help; return ;;
            *) memory_ids+=("$1") ;;
        esac
        shift
    done

    if [ ${#memory_ids[@]} -eq 0 ]; then
        print_command_usage "get <memory_id> [memory_id2] ..."
        return 1
    fi

    echo "=== 记忆详情 ==="
    echo ""

    for id in "${memory_ids[@]}"; do
        echo "--- $id ---"
        get_memory "$id"
        echo ""
    done
}

cmd_status() {
    echo "=== CC-Mem 状态 ==="
    echo ""
    echo "数据库：$CCMEM_MEMORY_DB"
    if [ -f "$CCMEM_MEMORY_DB" ]; then
        local mem_count=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT COUNT(*) FROM memories;")
        local session_count=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT COUNT(*) FROM sessions;")
        local project_count=$(sqlite3 "$CCMEM_MEMORY_DB" "SELECT COUNT(*) FROM projects;")

        # 兼容 macOS 和 Linux 的 du 命令
        local db_size=""
        if du -h "$CCMEM_MEMORY_DB" &> /dev/null; then
            db_size=$(du -h "$CCMEM_MEMORY_DB" | cut -f1)
        elif du -k "$CCMEM_MEMORY_DB" &> /dev/null; then
            # macOS 回退方案
            local size_kb=$(du -k "$CCMEM_MEMORY_DB" | cut -f1)
            if [ "$size_kb" -lt 1024 ]; then
                db_size="${size_kb}K"
            else
                db_size="$((size_kb / 1024))M"
            fi
        else
            # 使用 stat 命令
            if stat -f%z "$CCMEM_MEMORY_DB" &> /dev/null; then
                local size_bytes=$(stat -f%z "$CCMEM_MEMORY_DB")
                db_size="$((size_bytes / 1024))K"
            elif stat -c%s "$CCMEM_MEMORY_DB" &> /dev/null; then
                local size_bytes=$(stat -c%s "$CCMEM_MEMORY_DB")
                db_size="$((size_bytes / 1024))K"
            else
                db_size="unknown"
            fi
        fi

        echo "  记忆数量：$mem_count"
        echo "  会话数量：$session_count"
        echo "  项目数量：$project_count"
        echo "  数据库大小：$db_size"
    else
        echo "  状态：未初始化"
    fi
    echo ""

    print_failed_queue_summary
    echo ""
    print_recent_cleanup_summary
    echo ""

    echo "配置目录：$CONFIG_DIR"
    echo "脚本目录：$SCRIPT_DIR"
}

cmd_stats() {
    local days=7
    local project_path=""
    local project_root=""
    local where_clause="timestamp_epoch >= CAST(strftime('%s', 'now', '-7 days') AS INTEGER)"
    local summary_row=""
    local mem_count=0
    local content_bytes=0
    local preview_bytes=0
    local durable_count=0
    local working_count=0
    local temporary_count=0
    local preview_ratio="0.0%"
    local durable_ratio="0.0%"
    local working_ratio="0.0%"
    local temporary_ratio="0.0%"
    local avg_per_day="0.0"
    local active_days=0
    local daily_rows=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -d|--days) days="$2"; shift ;;
            -p|--project) project_path="$2"; shift ;;
            -h|--help)
                print_command_usage "stats [--days n] [--project path]"
                echo "显示最近记忆统计"
                echo ""
                echo "选项："
                echo "  -d, --days       统计最近天数（默认 7）"
                echo "  -p, --project    仅统计指定项目"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    if [[ ! "$days" =~ ^[0-9]+$ ]] || [ "$days" -le 0 ]; then
        echo "错误：days 必须是正整数"
        return 1
    fi

    where_clause="timestamp_epoch >= CAST(strftime('%s', 'now', '-$days days') AS INTEGER)"
    if [ -n "$project_path" ]; then
        project_root=$(resolve_project_root "$(resolve_effective_project_path "$project_path")")
        where_clause="$where_clause AND project_root = '$(sql_escape "$project_root")'"
    fi

    summary_row=$(sqlite3 -separator '|' "$CCMEM_MEMORY_DB" <<EOF
SELECT
  COUNT(*),
  COALESCE(SUM(LENGTH(content)), 0),
  COALESCE(SUM(LENGTH(content_preview)), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'durable' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'working' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'temporary' THEN 1 ELSE 0 END), 0)
FROM memories
WHERE $where_clause;
EOF
)

    mem_count=$(printf "%s" "$summary_row" | cut -d'|' -f1)
    content_bytes=$(printf "%s" "$summary_row" | cut -d'|' -f2)
    preview_bytes=$(printf "%s" "$summary_row" | cut -d'|' -f3)
    durable_count=$(printf "%s" "$summary_row" | cut -d'|' -f4)
    working_count=$(printf "%s" "$summary_row" | cut -d'|' -f5)
    temporary_count=$(printf "%s" "$summary_row" | cut -d'|' -f6)
    preview_ratio=$(format_ratio_percent "$preview_bytes" "$content_bytes")
    durable_ratio=$(format_ratio_percent "$durable_count" "$mem_count")
    working_ratio=$(format_ratio_percent "$working_count" "$mem_count")
    temporary_ratio=$(format_ratio_percent "$temporary_count" "$mem_count")
    avg_per_day=$(format_decimal "$mem_count" "$days")

    daily_rows=$(sqlite3 -separator '|' "$CCMEM_MEMORY_DB" <<EOF
SELECT
  date(datetime(timestamp_epoch, 'unixepoch', 'localtime')) AS day,
  COUNT(*),
  COALESCE(SUM(LENGTH(content)), 0),
  COALESCE(SUM(LENGTH(content_preview)), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'durable' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'working' THEN 1 ELSE 0 END), 0),
  COALESCE(SUM(CASE WHEN memory_kind = 'temporary' THEN 1 ELSE 0 END), 0)
FROM memories
WHERE $where_clause
GROUP BY day
ORDER BY day DESC;
EOF
)

    if [ -n "$daily_rows" ]; then
        active_days=$(printf "%s\n" "$daily_rows" | grep -c . | tr -d ' ')
    fi

    echo "=== CC-Mem 统计 ==="
    echo ""
    echo "范围：最近 ${days} 天"
    echo "项目：${project_root:-全部项目}"
    echo ""
    echo "总览："
    echo "  记忆数量：$mem_count"
    echo "  平均每日新增：$avg_per_day"
    echo "  活跃天数：$active_days/$days"
    echo "  Content 字节：$content_bytes"
    echo "  Preview 字节：$preview_bytes"
    echo "  Preview 占比：$preview_ratio"
    echo "  分层分布：durable=$durable_count working=$working_count temporary=$temporary_count"
    echo "  分层占比：durable=$durable_ratio working=$working_ratio temporary=$temporary_ratio"
    echo ""
    echo "每日明细："
    if [ -z "$daily_rows" ]; then
        echo "  （无数据）"
        return
    fi

    echo "  日期 | 数量 | Preview 占比 | durable | working | temporary"
    printf "%s\n" "$daily_rows" | while IFS='|' read -r day day_count day_content day_preview day_durable day_working day_temporary; do
        echo "  $day | $day_count | $(format_ratio_percent "$day_preview" "$day_content") | $day_durable | $day_working | $day_temporary"
    done
}

cmd_inject_context() {
    local project_path=""
    local limit
    limit=$(get_injection_session_start_limit)

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -l|--limit) limit="$2"; shift ;;
            -h|--help)
                print_command_usage "inject-context [-p project] [-l limit]"
                echo "生成开场注入上下文"
                echo ""
                echo "选项："
                echo "  -p, --project    项目路径（默认当前目录）"
                echo "  -l, --limit      高价值记忆数量（默认来自配置，缺省 3）"
                return
                ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    generate_injection_context "$project_path" "$limit"
}

main() {
    load_config

    local command="${1:-help}"
    shift || true

    case $command in
        init|help|--help|-h)
            ;;
        *)
            ensure_db_ready
            ;;
    esac

    case $command in
        init)
            init_db
            ;;
        capture)
            cmd_capture "$@"
            ;;
        search)
            cmd_search "$@"
            ;;
        recall)
            cmd_recall "$@"
            ;;
        timeline)
            cmd_timeline "$@"
            ;;
        get)
            cmd_get "$@"
            ;;
        history)
            cmd_history "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        export)
            cmd_export "$@"
            ;;
        retry)
            cmd_retry "$@"
            ;;
        projects)
            cmd_projects
            ;;
        related-projects)
            cmd_related_projects "$@"
            ;;
        link-projects)
            cmd_link_projects "$@"
            ;;
        unlink-projects)
            cmd_unlink_projects "$@"
            ;;
        refresh-project-links)
            cmd_refresh_project_links "$@"
            ;;
        cleanup)
            cmd_cleanup "$@"
            ;;
        status)
            cmd_status
            ;;
        stats)
            cmd_stats "$@"
            ;;
        inject-context)
            cmd_inject_context "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "未知命令：$command"
            echo "运行 'ccmem-cli.sh help' 查看帮助"
            exit 1
            ;;
    esac
}

main "$@"
