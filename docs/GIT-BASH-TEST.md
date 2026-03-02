# Git Bash 测试指南

本文档说明如何在 Windows 上的 Git Bash 环境中运行和测试 cc-mem。

---

## 快速开始

### 1. 安装依赖

```powershell
# 安装 Git for Windows
# https://gitforwindows.org/

# 安装 SQLite
choco install sqlite
# 或
scoop install sqlite
```

### 2. 运行兼容性检查

```bash
cd /c/Users/YourName/.claude/plugins/marketplaces/cc-mem
bash scripts/check-compat.sh
```

### 3. 运行完整测试

```bash
bash scripts/test-git-bash.sh
```

---

## 预期输出

```
=== CC-Mem 兼容性检查 ===
环境：Git Bash for Windows
HOME: /c/Users/YourName (USERPROFILE: C:\Users\YourName)

=== 依赖检查 ===
  ✅ sqlite3: 3.x.x
  ✅ bash: GNU bash, version 5.x.x
  ✅ grep: grep (GNU grep)
  ✅ sed: sed (GNU sed)

=== Date 命令兼容性 ===
  ⚠️  ISO 8601 格式：不支持，使用替代方案
  ✅ Unix 时间戳：支持

✅ 所有检查通过
```

---

## 功能测试

```bash
# 初始化
bash bin/ccmem-cli.sh init

# 查看状态
bash bin/ccmem-cli.sh status

# 捕获记忆
echo "Git Bash 测试" | bash bin/ccmem-cli.sh capture -c "test" -t "gitbash"

# 检索
bash bin/ccmem-cli.sh search -q "Git Bash"

# 导出
bash bin/ccmem-cli.sh export -o "/c/Users/YourName/cc-mem-export"
```

---

## 故障排除

### 问题：sqlite3 命令未找到

```powershell
choco install sqlite
```

### 问题：路径转换错误

cc-mem 已自动处理 Git Bash 路径转换，无需手动配置。
