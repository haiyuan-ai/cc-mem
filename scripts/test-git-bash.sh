#!/bin/bash
# CC-Mem Git Bash 兼容性测试脚本
# 用法：在 Git Bash 中运行 bash test-git-bash.sh

echo "=============================================="
echo "     CC-Mem Git Bash 兼容性测试"
echo "=============================================="
echo ""

PASS=0
FAIL=0
WARN=0

# 测试函数
test_case() {
    local name="$1"
    local result="$2"

    if [ "$result" -eq 0 ]; then
        echo "  ✅ PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  ❌ FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

warn_case() {
    local name="$1"
    echo "  ⚠️  WARN: $name"
    WARN=$((WARN + 1))
}

# 1. 环境检测
echo "=== 1. 环境信息 ==="
echo "  uname -s: $(uname -s)"
echo "  uname -r: $(uname -r)"
echo "  Bash 版本：$(bash --version 2>&1 | head -1)"
echo "  HOME: $HOME"
echo "  USERPROFILE: ${USERPROFILE:-未设置}"
echo ""

if [[ "$(uname -s)" == "MSYS"* ]] || [[ "$(uname -s)" == "MINGW"* ]]; then
    echo "  ✅ 检测到 Git Bash 环境"
    test_case "Git Bash 环境检测" 0
else
    echo "  ⚠️  不是 Git Bash 环境，部分测试可能不准确"
    warn_case "非 Git Bash 环境"
fi
echo ""

# 2. 路径处理测试
echo "=== 2. 路径处理测试 ==="

# 测试 HOME 路径
if [ -n "$HOME" ]; then
    test_case "HOME 变量已设置" 0
else
    test_case "HOME 变量已设置" 1
fi

# 测试 USERPROFILE（Git Bash 特有）
if [ -n "$USERPROFILE" ]; then
    test_case "USERPROFILE 变量已设置" 0
else
    warn_case "USERPROFILE 变量未设置（正常，可能不是 Git Bash）"
fi

# 测试路径存在性
TEST_DIR="$HOME/.claude/cc-mem"
if [ -d "$TEST_DIR" ] || [[ "$(uname -s)" != "MSYS"* && "$(uname -s)" != "MINGW"* ]]; then
    test_case "目录路径可访问" 0
else
    test_case "目录路径可访问" 1
fi
echo ""

# 3. 命令兼容性测试
echo "=== 3. 命令兼容性测试 ==="

# sqlite3
if command -v sqlite3 &> /dev/null; then
    test_case "sqlite3 命令可用" 0
else
    test_case "sqlite3 命令可用" 1
    echo "     提示：choco install sqlite"
fi

# grep
if echo "test" | grep -o "e" &> /dev/null; then
    test_case "grep -o 可用" 0
else
    test_case "grep -o 可用" 1
fi

# sed
if echo "test" | sed 's/test/ok/' &> /dev/null; then
    test_case "sed 替换可用" 0
else
    test_case "sed 替换可用" 1
fi

# date
if date +%s &> /dev/null; then
    test_case "date +%s 可用" 0
else
    test_case "date +%s 可用" 1
fi

# date -Iseconds (可选)
if date -Iseconds &> /dev/null 2>&1; then
    test_case "date -Iseconds 可用" 0
else
    warn_case "date -Iseconds 不可用（正常，cc-mem 有回退）"
fi

# du
if du -h "$HOME" &> /dev/null 2>&1; then
    test_case "du -h 可用" 0
else
    warn_case "du -h 不可用（cc-mem 有回退方案）"
fi

# /dev/urandom
if [ -e /dev/urandom ]; then
    test_case "/dev/urandom 可用" 0
else
    warn_case "/dev/urandom 不可用（cc-mem 使用\$RANDOM 回退）"
fi
echo ""

# 4. cc-mem 脚本加载测试
echo "=== 4. cc-mem 脚本加载测试 ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCMEM_DIR="$(dirname "$SCRIPT_DIR")"

# 测试 sqlite.sh 加载
if [ -f "$CCMEM_DIR/lib/sqlite.sh" ]; then
    # 尝试加载（不执行）
    if bash -n "$CCMEM_DIR/lib/sqlite.sh" 2>&1; then
        test_case "sqlite.sh 语法检查" 0
    else
        test_case "sqlite.sh 语法检查" 1
    fi
else
    test_case "sqlite.sh 文件存在" 1
fi

# 测试 ccmem-cli.sh 加载
if [ -f "$CCMEM_DIR/bin/ccmem-cli.sh" ]; then
    if bash -n "$CCMEM_DIR/bin/ccmem-cli.sh" 2>&1; then
        test_case "ccmem-cli.sh 语法检查" 0
    else
        test_case "ccmem-cli.sh 语法检查" 1
    fi
else
    test_case "ccmem-cli.sh 文件存在" 1
fi
echo ""

# 5. 实际功能测试（如果有数据库）
echo "=== 5. 实际功能测试 ==="

if [ -f "$HOME/.claude/cc-mem/memory.db" ]; then
    # 测试数据库连接
    RESULT=$(sqlite3 "$HOME/.claude/cc-mem/memory.db" "SELECT COUNT(*) FROM memories;" 2>&1)
    if [ $? -eq 0 ]; then
        test_case "SQLite 数据库连接" 0
        echo "     记忆数量：$RESULT"
    else
        test_case "SQLite 数据库连接" 1
        echo "     错误：$RESULT"
    fi

    # 测试 ccmem-cli.sh status
    if [ -x "$CCMEM_DIR/bin/ccmem-cli.sh" ]; then
        OUTPUT=$("$CCMEM_DIR/bin/ccmem-cli.sh" status 2>&1)
        if echo "$OUTPUT" | grep -q "记忆数量"; then
            test_case "ccmem-cli.sh status 运行" 0
        else
            test_case "ccmem-cli.sh status 运行" 1
        fi
    fi
else
    warn_case "数据库不存在，跳过功能测试"
    echo "     提示：运行 ccmem-cli.sh init 初始化"
fi
echo ""

# 6. Git Bash 特定测试
echo "=== 6. Git Bash 特定测试 ==="

if [[ "$(uname -s)" == "MSYS"* ]] || [[ "$(uname -s)" == "MINGW"* ]]; then
    # 仅在 Git Bash 下运行

    # 测试路径转换
    if command -v cygpath &> /dev/null; then
        WIN_PATH=$(cygpath -w "$HOME" 2>&1)
        if [ $? -eq 0 ]; then
            test_case "cygpath 路径转换" 0
            echo "     Windows 路径：$WIN_PATH"
        else
            test_case "cygpath 路径转换" 1
        fi
    else
        warn_case "cygpath 不可用"
    fi

    # 测试 USERPROFILE 回退
    if [ -n "$USERPROFILE" ] && [ "$HOME" = "$USERPROFILE" ]; then
        test_case "HOME=USERPROFILE 回退" 0
    else
        warn_case "HOME=USERPROFILE 回退未触发"
    fi
else
    echo "  (仅在 Git Bash 下运行特定测试)"
    echo ""
fi

# 总结
echo "=============================================="
echo "     测试结果总结"
echo "=============================================="
echo "  ✅ PASS: $PASS"
echo "  ⚠️  WARN: $WARN"
echo "  ❌ FAIL: $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "  🎉 所有测试通过！cc-mem 可以在 Git Bash 下正常运行。"
    exit 0
else
    echo "  ⚠️  有 $FAIL 个测试失败，请检查上述输出。"
    exit 1
fi
