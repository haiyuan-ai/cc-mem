# CC-mem 兼容性指南

本文档说明 CC-mem 在不同操作系统上的兼容性要求和注意事项。

## 系统要求

### 必需依赖

| 依赖 | macOS | Ubuntu/Debian | 用途 |
|------|-------|---------------|------|
| Bash | 3.2+ (自带) | bash (默认) | 脚本执行 |
| SQLite3 | 3.35+ | sqlite3 (默认) | 数据存储 |
| grep | BSD/GNU | GNU grep | 文本匹配 |
| sed | BSD/GNU | GNU sed | 文本替换 |

### 可选依赖

| 依赖 | 用途 | 缺失时的回退方案 |
|------|------|-----------------|
| perl | 私有内容过滤 | 使用 sed 简单模式 |
| jq | JSON 处理 | Hooks 输入解析依赖 |
| du | 数据库大小显示 | 使用 stat 命令替代 |

## 安装方法

### macOS

```bash
# 系统自带 SQLite3 和 Bash，无需额外安装
# 可选：安装 jq
brew install jq
```

### Ubuntu/Debian

```bash
# 安装依赖
sudo apt-get update
sudo apt-get install -y sqlite3 jq perl

# 如果 Bash 版本 < 4.0，建议升级
sudo apt-get install -y bash
```

## 已知的兼容性处理

### 1. 日期格式

**问题**: `date -Iseconds` 在 macOS 和 Linux 上行为不同

**解决方案**: 使用 `format_iso8601()` 函数自动检测
```bash
format_iso8601() {
    if date -Iseconds &> /dev/null; then
        # GNU date (Linux)
        date -Iseconds
    else
        # BSD date (macOS)
        date -u +"%Y-%m-%dT%H:%M:%S%z"
    fi
}
```

### 2. 数据库大小显示

**问题**: `du -h` 输出格式在不同系统上不同

**解决方案**: 多重检测
```bash
if du -h "$FILE" &> /dev/null; then
    db_size=$(du -h "$FILE" | cut -f1)
elif du -k "$FILE" &> /dev/null; then
    # macOS 回退
    size_kb=$(du -k "$FILE" | cut -f1)
    db_size="$((size_kb / 1024))M"
else
    # 使用 stat
    db_size=$(stat -f%z "$FILE")  # macOS
    # 或
    db_size=$(stat -c%s "$FILE")  # Linux
fi
```

### 3. 随机数生成

**问题**: `/dev/urandom` 在某些容器环境中不可用

**解决方案**: 回退到 `$RANDOM`
```bash
if [ -e /dev/urandom ]; then
    random_str=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
else
    random_str="${RANDOM}${RANDOM}"
fi
```

### 4. Sed 兼容性

**问题**: BSD sed 和 GNU sed 参数不同

**解决方案**: 避免使用 `sed -i`，改用临时文件
```bash
# 不推荐
sed -i 's/old/new/g' file.txt

# 推荐（跨平台）
sed 's/old/new/g' file.txt > /tmp/tmp && mv /tmp/tmp file.txt
```

## 运行兼容性检查

```bash
# 运行兼容性检查脚本
bash ~/.claude/plugins/marketplaces/cc-mem/scripts/check-compat.sh
```

### 检查输出示例

```
=== CC-mem 兼容性检查 ===

系统：Darwin 25.3.0
Bash 版本：GNU bash, version 3.2.57

=== 依赖检查 ===
  ✅ sqlite3: 3.41.2
  ✅ bash: GNU bash, version 3.2.57
  ✅ grep: grep (BSD grep, GNU compatible)
  ✅ sed: sed (BSD sed)

=== 可选功能依赖 ===
  ✅ perl: 已安装
  ✅ du: 已安装
  ✅ jq: jq-1.7.1
  ✅ curl: curl 8.7.1

=== Date 命令兼容性 ===
  ✅ ISO 8601 格式：支持
  ✅ Unix 时间戳：支持

=== 随机数生成 ===
  ✅ /dev/urandom: 可用

=== SQLite FTS5 支持 ===
  ✅ FTS5: 支持

=== 检查完成 ===
```

## 故障排除

---

## Windows 用户指南

### 方案 1: 使用 WSL2 (推荐)

**适用场景**: Windows 10/11 用户，希望获得完整功能体验

**步骤 1: 安装 WSL2**

以管理员身份打开 PowerShell，执行：

```powershell
# 安装 WSL
wsl --install

# 如果上述命令失败，手动启用功能
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# 重启电脑后，设置 WSL2 为默认
wsl --set-default-version 2
```

**步骤 2: 安装 Ubuntu**

```powershell
# 从 Microsoft Store 安装 Ubuntu
# 或命令行安装
wsl --install -d Ubuntu
```

**步骤 3: 在 WSL2 中安装 cc-mem**

打开 WSL2 终端 (Ubuntu)，执行：

```bash
# 克隆或复制 cc-mem 到 WSL2 环境
# 注意：路径需要使用 WSL2 格式

# 访问 Windows 文件（可选）
cd /mnt/c/Users/YourName/.claude/plugins/marketplaces/cc-mem

# 或者直接复制到 WSL2 home 目录
cp -r /mnt/c/Users/YourName/.claude/plugins/marketplaces/cc-mem ~/cc-mem
cd ~/cc-mem

# 运行
bash bin/ccmem-cli.sh status
```

**步骤 4: 验证 hooks 工作**

WSL2 环境下，cc-mem 的插件级 hooks 配置会自动生效。重启 Claude Code 后检查调试日志：

```bash
# 在 WSL2 中查看日志
cat /tmp/ccmem_debug.log
```

**WSL2 方案优缺点**:

---

### 方案 2: 使用 Git Bash

**适用场景**: 不想使用 WSL2，希望轻量级方案

**步骤 1: 安装 Git for Windows**

下载安装：https://gitforwindows.org/

安装时确保勾选：
- ✅ Git Bash Here
- ✅ Add Git to PATH

**步骤 2: 在 Git Bash 中运行 cc-mem**

```bash
# 打开 Git Bash
# 导航到 cc-mem 目录
cd /c/Users/YourName/.claude/plugins/marketplaces/cc-mem

# 运行
bash bin/ccmem-cli.sh status
```

**Git Bash 方案注意事项**:

1. 路径使用 Unix 风格 (`/c/Users/` 而非 `C:\Users\`)
2. 部分命令可能需要适配（已内置兼容性处理）
3. SQLite 需要单独安装

**代码兼容性**:

✅ **已内置 Git Bash 兼容性修复** (v1.0+)

- 自动检测 Git Bash 环境
- 自动处理 `$HOME` 和 `$USERPROFILE` 路径
- Obsidian 导出路径自动适配

**无需修改代码即可运行！**

**安装 SQLite (Windows)**:

```powershell
# 使用 Chocolatey
choco install sqlite

# 或使用 Scoop
scoop install sqlite
```

---

### 方案 3: 使用 Windows 版 SQLite 直接调用

**适用场景**: 高级用户，希望最小化依赖

**步骤**:

1. 下载 SQLite: https://www.sqlite.org/download.html
2. 解压并将 `sqlite3.exe` 添加到 PATH
3. 使用 Git Bash 或 WSL2 运行脚本

---

### Windows 路径转换参考

| Windows 路径 | WSL2/Git Bash 路径 |
|-------------|-------------------|
| `C:\Users\Name` | `/mnt/c/Users/Name` |
| `D:\Projects` | `/mnt/d/Projects` |
| `%USERPROFILE%` | `~` 或 `/mnt/c/Users/Name` |

---

### 常见问题

#### Q: WSL2 中访问 Windows 文件很慢

**A**: 建议将项目复制到 WSL2 文件系统内：

```bash
# 从 /mnt/c/ 复制到 ~/
cp -r /mnt/c/Users/Name/.claude ~/claude

# 然后在 WSL2 内使用
cd ~/claude
```

#### Q: Git Bash 中提示 `sqlite3: command not found`

**A**: 安装 SQLite 并确保添加到 PATH：

```bash
# 检查是否安装
which sqlite3

# 如果未找到，使用 Chocolatey 安装
choco install sqlite
```

---

## 故障排除

### 问题：`date: illegal option -- I`

**原因**: 使用旧版 macOS，`date -Iseconds` 不支持

**解决**: 系统已自动使用替代格式，不影响使用

### 问题：`/dev/urandom: No such file or directory`

**原因**: 容器环境或特殊系统

**解决**: 系统会自动回退到 `$RANDOM` 生成随机数

### 问题：`sqlite3: command not found`

**macOS**:
```bash
# macOS 自带 sqlite3，检查 PATH
echo $PATH
```

**Ubuntu/Debian**:
```bash
sudo apt-get install sqlite3
```

### 问题：FTS5 不支持

**原因**: SQLite 版本过旧 (< 3.9.0)

**解决**:
```bash
# macOS (使用 Homebrew)
brew install sqlite

# Ubuntu/Debian
sudo apt-get install sqlite3
```

## 版本信息

| 组件 | 最低版本 | 推荐版本 |
|------|---------|---------|
| Bash | 3.2 | 4.0+ |
| SQLite | 3.35 (FTS5) | 3.40+ |
| macOS | 10.15+ | 12.0+ |
| Ubuntu | 18.04+ | 22.04+ |

## 测试状态

| 系统 | 测试状态 | 备注 |
|------|---------|------|
| macOS 13+ (arm64) | ✅ 通过 | M1/M2 芯片 |
| macOS 12+ (x86_64) | ✅ 通过 | Intel 芯片 |
| Ubuntu 22.04 LTS | ✅ 通过 | - |
| Ubuntu 20.04 LTS | ✅ 通过 | - |
| Debian 11 | ✅ 通过 | - |
| WSL2 (Ubuntu) | ⚠️ 待测试 | 理论上支持 |

## 反馈

如遇到兼容性问题，请提供：
1. 操作系统版本 (`uname -a`)
2. Bash 版本 (`bash --version`)
3. SQLite 版本 (`sqlite3 --version`)
4. 错误信息
