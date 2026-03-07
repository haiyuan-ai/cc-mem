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

load_config() {
    if [ -f "$CONFIG_DIR/config.json" ]; then
        # 简单的 JSON 解析（仅支持基本类型）
        CONFIG_FILE="$CONFIG_DIR/config.json"
    fi
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
    mkdir -p "$(dirname "$MEMORY_DB")"

    if [ ! -f "$MEMORY_DB" ]; then
        init_db >/dev/null 2>&1
        return
    fi

    local has_memories
    has_memories=$(sqlite3 "$MEMORY_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='memories';" 2>/dev/null || true)
    if [ "$has_memories" != "memories" ]; then
        init_db >/dev/null 2>&1
    fi
}

show_help() {
    cat <<EOF
CC-Mem CLI - Claude Code 记忆管理工具

用法：ccmem-cli.sh <command> [options]

命令:
  init              初始化数据库
  capture           捕获当前会话记忆
  store             手动存储一条记忆
  search            搜索记忆（三层检索第一步）
  timeline          获取时间线上下文（三层检索第二步）
  get               获取记忆详情（三层检索第三步）
  history           查看记忆历史
  list              列出最近的记忆
  export            导出记忆到 Markdown
  inject-context    生成开场注入上下文
  projects          列出所有项目
  related-projects  列出关联项目
  link-projects     手动建立项目关联
  unlink-projects   删除项目关联
  refresh-project-links 刷新自动项目关联
  cleanup           清理过期记忆（默认安全模式）
  status            显示记忆库状态
  help              显示此帮助信息

示例:
  ccmem-cli.sh search -p "/path/to/project" -q "API endpoint"
  ccmem-cli.sh timeline -a mem_xxx -b 3 -A 3
  ccmem-cli.sh get mem_123 mem_456
  ccmem-cli.sh capture -c "decision" -t "important,core"
  ccmem-cli.sh export -o "~/exports"
  ccmem-cli.sh related-projects -p "/path/to/project"
选项:
  -p, --project     项目路径
  -c, --category    记忆类别 (decision|solution|pattern|debug|context)
  -t, --tags        标签（逗号分隔）
  --concepts        概念标签（how-it-works|problem-solution|gotcha|pattern|trade-off|why-it-exists|what-changed）
  -q, --query       检索关键词
  -o, --output      导出目录（默认：$HOME/cc-mem-export）
  -l, --limit       限制结果数量（默认：10）
  -s, --session     会话 ID
  -h, --help        显示帮助

EOF
}

cmd_capture() {
    local project_path=""
    local category="context"
    local tags=""
    local concepts=""
    local session_id="${CLAUDE_SESSION_ID:-$$}"
    local source="manual"
    local memory_kind=""
    local auto_inject_policy=""
    local project_root=""
    local expires_at=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -c|--category) category="$2"; shift ;;
            -t|--tags) tags="$2"; shift ;;
            --concepts) concepts="$2"; shift ;;
            -s|--session) session_id="$2"; shift ;;
            --source) source="$2"; shift ;;
            --memory-kind) memory_kind="$2"; shift ;;
            --inject-policy) auto_inject_policy="$2"; shift ;;
            --project-root) project_root="$2"; shift ;;
            --expires-at) expires_at="$2"; shift ;;
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

            local summary
            summary=$(build_default_summary "$filtered_content")

            # 如果没有指定 concepts，尝试自动识别
            if [ -z "$concepts" ]; then
                concepts=$(detect_concepts "$filtered_content")
                if [ -n "$concepts" ]; then
                    echo "  自动识别概念：$concepts"
                fi
            fi

            local id=$(store_memory "$session_id" "$project_path" "$category" "$filtered_content" "$summary" "$tags" "$concepts" "$source" "$memory_kind" "$auto_inject_policy" "$project_root" "$expires_at")

            if ! handle_store_memory_result "$id" "  " "$private_warning" "记忆 ID: $id"; then
                return 1
            fi
            echo "记忆已存储"
            return 0
        fi
    fi

    echo "没有捕获到内容（从 stdin 为空）"
}

cmd_store() {
    local project_path=""
    local category="context"
    local tags=""
    local summary=""
    local session_id="${CLAUDE_SESSION_ID:-$$}"
    local source="manual"
    local memory_kind=""
    local auto_inject_policy=""
    local project_root=""
    local expires_at=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--project) project_path="$2"; shift ;;
            -c|--category) category="$2"; shift ;;
            -t|--tags) tags="$2"; shift ;;
            -s|--session) session_id="$2"; shift ;;
            -m|--summary) summary="$2"; shift ;;
            --source) source="$2"; shift ;;
            --memory-kind) memory_kind="$2"; shift ;;
            --inject-policy) auto_inject_policy="$2"; shift ;;
            --project-root) project_root="$2"; shift ;;
            --expires-at) expires_at="$2"; shift ;;
            -h|--help) show_help; return ;;
            *) print_unknown_option "$1"; return 1 ;;
        esac
        shift
    done

    project_path="$(resolve_effective_project_path "$project_path")"

    echo "请输入记忆内容（以 EOF 结束）："
    local content=$(cat)
    content=$(strip_injected_context_blocks "$content")

    if [ -z "$content" ]; then
        echo "错误：记忆内容不能为空"
        return 1
    fi

    if [ -z "$summary" ]; then
        summary=$(build_default_summary "$content")
    fi

    local id=$(store_memory "$session_id" "$project_path" "$category" "$content" "$summary" "$tags" "" "$source" "$memory_kind" "$auto_inject_policy" "$project_root" "$expires_at")
    handle_store_memory_result "$id" "" "" "记忆已存储：$id"
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

    sqlite3 -header -column "$MEMORY_DB" <<EOF
SELECT id, timestamp, category, concepts, summary, project_path, tags
FROM memories
$where_clause
ORDER BY timestamp DESC
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

    # 配置优先级：命令行参数 > 环境变量 > 配置文件 > 默认值
    if [ -z "$output_dir" ]; then
        # 尝试从环境变量读取
        if [ -n "$CCMEM_EXPORT_DIR" ]; then
            output_dir="$CCMEM_EXPORT_DIR"
        elif [ -n "$CCMEM_MARKDOWN_DIR" ]; then
            output_dir="$CCMEM_MARKDOWN_DIR"
        # 尝试从配置文件读取
        elif [ -f "$CONFIG_DIR/config.json" ] && command -v jq &> /dev/null; then
            output_dir=$(jq -r '.memory.markdown_export_path // .memory.obsidian_export_path // empty' "$CONFIG_DIR/config.json" 2>/dev/null)
        fi

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
    echo "数据库：$MEMORY_DB"
    if [ -f "$MEMORY_DB" ]; then
        local mem_count=$(sqlite3 "$MEMORY_DB" "SELECT COUNT(*) FROM memories;")
        local session_count=$(sqlite3 "$MEMORY_DB" "SELECT COUNT(*) FROM sessions;")
        local project_count=$(sqlite3 "$MEMORY_DB" "SELECT COUNT(*) FROM projects;")

        # 兼容 macOS 和 Linux 的 du 命令
        local db_size=""
        if du -h "$MEMORY_DB" &> /dev/null; then
            db_size=$(du -h "$MEMORY_DB" | cut -f1)
        elif du -k "$MEMORY_DB" &> /dev/null; then
            # macOS 回退方案
            local size_kb=$(du -k "$MEMORY_DB" | cut -f1)
            if [ "$size_kb" -lt 1024 ]; then
                db_size="${size_kb}K"
            else
                db_size="$((size_kb / 1024))M"
            fi
        else
            # 使用 stat 命令
            if stat -f%z "$MEMORY_DB" &> /dev/null; then
                local size_bytes=$(stat -f%z "$MEMORY_DB")
                db_size="$((size_bytes / 1024))K"
            elif stat -c%s "$MEMORY_DB" &> /dev/null; then
                local size_bytes=$(stat -c%s "$MEMORY_DB")
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

    echo "配置目录：$CONFIG_DIR"
    echo "脚本目录：$SCRIPT_DIR"
}

cmd_inject_context() {
    local project_path=""
    local limit=3

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
                echo "  -l, --limit      高价值记忆数量（默认 3）"
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
        store)
            cmd_store "$@"
            ;;
        search)
            cmd_search "$@"
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
