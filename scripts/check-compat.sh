#!/bin/bash
# CC-Mem 兼容性检查脚本
# 用法：bash check-compat.sh

echo "=== CC-Mem 兼容性检查 ==="
echo ""

# 系统信息
SYSTEM=$(uname -s)
echo "系统：$SYSTEM $(uname -r)"

# Git Bash 检测
if [[ "$SYSTEM" == "MSYS"* ]] || [[ "$SYSTEM" == "MINGW"* ]]; then
    echo "环境：Git Bash for Windows"
    echo "HOME: $HOME (USERPROFILE: $USERPROFILE)"
else
    echo "Bash 版本：$(bash --version 2>&1 | head -1)"
fi
echo ""

# 依赖检查
echo "=== 依赖检查 ==="

check_command() {
    local cmd="$1"
    local required="$2"

    if command -v "$cmd" &> /dev/null; then
        # 尝试获取版本，处理 BSD/GNU 差异
        local version=""
        if "$cmd" --version &> /dev/null; then
            version=$("$cmd" --version 2>&1 | head -1)
        elif "$cmd" -V &> /dev/null; then
            version=$("$cmd" -V 2>&1 | head -1)
        else
            version="已安装"
        fi
        echo "  ✅ $cmd: $version"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo "  ❌ $cmd: 未安装 (必需)"
            return 1
        else
            echo "  ⚠️  $cmd: 未安装 (可选)"
            return 1
        fi
    fi
}

# 必需依赖
check_command "sqlite3" "required"
check_command "bash" "required"
check_command "grep" "required"
check_command "sed" "required"

# 可选依赖
echo ""
echo "=== 可选功能依赖 ==="
check_command "perl" "optional"  # 私有内容过滤
check_command "du" "optional"    # 数据库大小
check_command "jq" "optional"    # Hooks JSON 解析

# 检查 date 命令兼容性
echo ""
echo "=== Date 命令兼容性 ==="
if date -Iseconds &> /dev/null; then
    echo "  ✅ ISO 8601 格式：支持 (date -Iseconds)"
else
    echo "  ⚠️  ISO 8601 格式：不支持，使用替代方案"
    echo "     替代：$(date +%Y-%m-%dT%H:%M:%S%z)"
fi

if date +%s &> /dev/null; then
    echo "  ✅ Unix 时间戳：支持 (date +%s)"
else
    echo "  ❌ Unix 时间戳：不支持"
fi

# 检查 /dev/urandom
echo ""
echo "=== 随机数生成 ==="
if [ -e /dev/urandom ]; then
    echo "  ✅ /dev/urandom: 可用"
else
    echo "  ⚠️  /dev/urandom: 不可用，需要替代方案"
fi

# SQLite FTS5 支持
echo ""
echo "=== SQLite FTS5 支持 ==="
if sqlite3 ":memory:" "CREATE VIRTUAL TABLE t USING fts5(content);" 2>/dev/null; then
    echo "  ✅ FTS5: 支持"
else
    echo "  ⚠️  FTS5: 不支持 (全文检索功能将不可用)"
fi

echo ""
echo "=== 检查完成 ==="
