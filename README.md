# CC-mem

Claude Code 轻量级记忆管理系统

**测试**: ✅ 全量回归通过 | **许可**: MIT

---

## 产品定位

**CC-mem** 是一个专为 Claude Code 设计的**轻量级记忆管理工具**，采用纯 Bash 实现，零额外依赖。

**目标用户**: 个人开发者、技术博主、AI 助手重度用户

**核心价值**:
- 🪶 **轻量简洁** - 纯 Bash 脚本，仅需 SQLite，无需 Python/Node 运行时
- 🔒 **本地优先** - 所有数据本地存储，无云端依赖，隐私可控
- 📦 **开箱即用** - 安装即用，无需复杂配置
- 🧪 **测试完备** - 存储、CLI、Hooks、边界条件全量回归通过

**适用场景**:
- ✅ 个人知识管理和会话记忆
- ✅ 跨会话上下文保持
- ✅ 技术决策和解决方案记录
- ✅ 项目级记忆隔离

**不适用场景**:
- ❌ 企业级多用户协作
- ❌ 需要向量检索的复杂场景
- ❌ 需要 Graph 知识图谱

---

## 功能特性

- **自动捕获**：PostToolUse / Stop / SessionEnd 自动沉淀工作过程
- **实时注入**：SessionStart 预热上下文 + UserPromptSubmit query-aware recall
- **分层记忆**：按来源、生命周期和自动注入资格组织记忆
- **自动裁剪**：Stop / SessionEnd 会对超长回复和日志做本地裁剪
- **持久化存储**：SQLite 数据库 + FTS5 全文检索
- **智能检索**：支持 FTS、中文 fallback、timeline、related project recall
- **Markdown 导出**：导出为标准 Markdown 文件
- **Hooks 集成**：SessionStart/PostToolUse/UserPromptSubmit/Stop/SessionEnd 自动注入和捕获
- **记忆历史**：记录 create/update/delete 事件
- **内容去重**：SHA256 哈希，自动检测重复内容
- **概念标签**：7 种预定义概念，自动识别

## 快速链接

- [🔧 兼容性指南](docs/COMPATIBILITY.md) - macOS/Ubuntu/Windows
- [🧪 测试报告](tests/TEST-REPORT.md) - 当前测试结构与说明
- [📖 文档索引](docs/INDEX.md) - 完整文档导航

## 安装

### 系统要求

- **macOS** 10.15+ - 自带 Bash 和 SQLite
- **Linux** Ubuntu 18.04+ / Debian 10+ - 需安装 sqlite3
- **Windows** Windows 10/11 + WSL2

详细的依赖要求和安装说明见 **[兼容性指南](docs/COMPATIBILITY.md)**。

### 方法一：一键安装脚本（推荐）

```bash
curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/install-plugin.sh | bash
```

安装完成后重启 Claude Code：
```bash
exit
# 重新运行 claude
```

### 方法二：让 Claude Code 帮你安装（最简单）

直接告诉 Claude Code：

```
安装 https://github.com/haiyuan-ai/cc-mem
```

Claude Code 会自动：
1. 克隆仓库到正确的目录
2. 注册 marketplace 配置
3. 注册已安装插件
4. 初始化数据库

安装完成后，重启 Claude Code：
```bash
exit
# 重新运行 claude
```

然后启用插件：
```
/plugin install cc-mem@haiyuan-ai-cc-mem
```

最后再次重启 Claude Code 以激活 hooks。

### 方法三：手动安装

**步骤 1: 克隆仓库**

```bash
git clone https://github.com/haiyuan-ai/cc-mem.git ~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem
```

**步骤 2: 注册 Marketplace**

编辑 `~/.claude/plugins/known_marketplaces.json`，添加：

```json
{
  "haiyuan-ai-cc-mem": {
    "source": {
      "source": "github",
      "repo": "haiyuan-ai/cc-mem"
    },
    "installLocation": "/Users/YOUR_USERNAME/.claude/plugins/marketplaces/haiyuan-ai-cc-mem",
    "lastUpdated": "2026-03-07T00:00:00.000Z"
  }
}
```

**步骤 3: 注册已安装插件**

编辑 `~/.claude/plugins/installed_plugins.json`，在 `plugins` 对象中添加：

```json
"cc-mem@haiyuan-ai-cc-mem": [
  {
    "scope": "user",
    "installPath": "/Users/YOUR_USERNAME/.claude/plugins/marketplaces/haiyuan-ai-cc-mem",
    "version": "1.5.0",
    "installedAt": "2026-03-07T00:00:00.000Z",
    "lastUpdated": "2026-03-07T00:00:00.000Z",
    "gitCommitSha": "COMMIT_SHA_HERE"
  }
]
```

**步骤 4: 重启 Claude Code 会话**

```bash
exit
# 重新运行 claude
```

---

## 卸载

### 方法一：使用 `/plugin` 命令（推荐）

```bash
/plugin uninstall cc-mem@haiyuan-ai-cc-mem
```

然后重启 Claude Code 会话：

```bash
exit
# 重新运行 claude
```

### 方法二：手动卸载

**步骤 1: 删除插件目录**

```bash
rm -rf ~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem
```

> **说明**：插件级别的 hooks 会自动移除，无需手动编辑配置文件。

**步骤 2: 清理 Marketplace 注册（可选）**

编辑 `~/.claude/plugins/known_marketplaces.json`，删除 `haiyuan-ai-cc-mem` 条目。

**步骤 3: 删除数据库（可选）**

```bash
# 默认路径
rm -rf ~/.claude/cc-mem/memory.db
# 或自定义路径
rm -rf ~/.config/cc-mem/memory.db
```

**步骤 4: 重启 Claude Code 会话**

```bash
exit
# 重新运行 claude
```

---

## 使用方法

### 基本命令

```bash
# 初始化
ccmem-cli.sh init

# 查看状态
ccmem-cli.sh status

# 捕获记忆
echo "重要内容" | ccmem-cli.sh capture -c "decision" -t "tag1,tag2"

# 检索记忆
ccmem-cli.sh search -p "/path/to/project" -q "关键词"

# 获取时间线上下文
ccmem-cli.sh timeline -a mem_xxx -b 3 -A 3

# 获取记忆详情
ccmem-cli.sh get mem_123 mem_456

# 列出最近记忆
ccmem-cli.sh list

# 手动创建记忆
ccmem-cli.sh store -p "/path/to/project" -c "pattern" -t "tag" -m "摘要"

# 导出记忆
ccmem-cli.sh export -o "~/exports"

# 生成开场注入上下文
ccmem-cli.sh inject-context -p "/path/to/project" -l 3

# 列出所有项目
ccmem-cli.sh projects

# 清理过期记忆
ccmem-cli.sh cleanup -d 30

# 查看记忆历史
ccmem-cli.sh history -r -l 10

# 修复 FTS 全文索引（维护工具）
./scripts/repair-fts.sh --force --no-backup
```

### 命令详解

#### capture - 捕获记忆

```bash
# 从 stdin 读取
echo "决策内容：选择 SQLite 作为存储方案" | \
  ccmem-cli.sh capture -c "decision" -t "sqlite,architecture"

# 指定项目路径
ccmem-cli.sh capture -p "/path/to/project" -c "solution" -t "bugfix"
```

**类别说明：**
- `decision` - 重要决策
- `solution` - 解决方案
- `pattern` - 可复用模式
- `debug` - 调试记录
- `context` - 上下文信息

#### search - 检索记忆

```bash
# 按项目路径检索
ccmem-cli.sh search -p "/path/to/project"

# 按关键词检索
ccmem-cli.sh search -q "SQLite full-text search"

# 按类别检索
ccmem-cli.sh search -c "debug"

# 组合检索
ccmem-cli.sh search -p "/path/to/project" -q "API" -c "solution" -l 5
```

补充说明：
- 英文/普通关键词优先走 FTS5
- 中文查询会自动启用 `LIKE` fallback
- `search` 更适合找候选记忆，细节可继续用 `timeline` 和 `get`

#### export - 导出记忆

```bash
# 导出所有记忆到指定目录
ccmem-cli.sh export -o "~/cc-mem-exports"

# 导出指定项目记忆
ccmem-cli.sh export -p "/path/to/project" -o ~/exports
```

**导出格式**：标准 Markdown 文件，可用任何 Markdown 编辑器打开（VS Code, Typora, Obsidian 等）

#### timeline - 获取时间线上下文

```bash
# 获取记忆的前后上下文
ccmem-cli.sh timeline -a mem_123 -b 3 -A 3

# 参数说明
# -a: 锚点记忆 ID
# -b: 锚点之前的记忆数量（默认 3）
# -A: 锚点之后的记忆数量（默认 3）
```

#### get - 获取记忆详情

```bash
# 获取单条记忆详情
ccmem-cli.sh get mem_123

# 获取多条记忆详情
ccmem-cli.sh get mem_123 mem_456 mem_789
```

#### store - 手动创建记忆

```bash
# 手动创建一条记忆
echo "记忆内容" | ccmem-cli.sh store -p "/path/to/project" -c "pattern" -t "tag" -m "自定义摘要"

# 交互模式（从 stdin 读取）
ccmem-cli.sh store -p "/path/to/project" -c "context"
# 然后输入内容，Ctrl+D 结束
```

#### inject-context - 生成结构化开场上下文

```bash
# 生成当前项目的开场注入上下文
ccmem-cli.sh inject-context -p "/path/to/project" -l 3
```

输出特点：
- 只输出结构化 `<cc-mem-context>` 块
- 默认优先注入 durable / conditional 记忆
- 结果不足时会补 1 条 related project 记忆
- 连续 debug / 连续决策链会自动附加 timeline hint

#### projects - 列出所有项目

```bash
# 列出所有记忆项目
ccmem-cli.sh projects
```

#### cleanup - 清理过期记忆

```bash
# 清理 30 天前的记忆（默认）
ccmem-cli.sh cleanup

# 清理指定天数前的记忆
ccmem-cli.sh cleanup -d 60
```

---

## 💡 使用示例

### 捕获技术决策

```bash
# 记录技术选型
echo "选择 SQLite 而非 PostgreSQL，因为轻量且不需要独立服务器" | \
  ccmem-cli.sh capture -c "decision" -t "database,architecture"
```

### 记录问题解决方案

```bash
# 记录 Bug 修复
echo "问题：SQLite 锁超时。解决方案：设置 busy_timeout=5000" | \
  ccmem-cli.sh capture -c "solution" -t "bugfix,sqlite"
```

### 记录注意事项（Gotcha）

```bash
# 记录警告
echo "注意：SQLite 在并发场景下可能锁超时" | \
  ccmem-cli.sh capture -c "debug" -t "warning" --concepts "gotcha"
```

### 检索记忆

```bash
# 按关键词搜索
ccmem-cli.sh search -q "SQLite timeout"

# 按项目搜索
ccmem-cli.sh search -p "/path/to/project"

# 按类别搜索
ccmem-cli.sh search -c "solution"
```

### 查看记忆历史

```bash
# 查看最近历史
ccmem-cli.sh history -r -l 10

# 查看特定记忆的历史
ccmem-cli.sh history -m mem_xxx
```

---

## 🔧 高级用法

### 使用环境变量

```bash
# 设置默认导出目录
export CCMEM_MARKDOWN_DIR="$HOME/notes"

# 设置默认数据库路径
export MEMORY_DB="$HOME/.config/cc-mem/memory.db"
```

### 自动化脚本

```bash
#!/bin/bash
# daily-capture.sh - 每日工作记录

DATE=$(date +%Y-%m-%d)
echo "=== 每日工作记录 - $DATE ==="

read -p "今日决策：" DECISION
echo "$DECISION" | ccmem-cli.sh capture -c "decision" -t "daily,$DATE"

read -p "解决问题：" SOLUTION
echo "$SOLUTION" | ccmem-cli.sh capture -c "solution" -t "daily,$DATE"

echo "记录完成！"
```

### 批量导入

```bash
# 从文件批量导入记忆
while IFS= read -r line; do
    echo "$line" | ccmem-cli.sh capture -c "context" -t "import"
done < notes.txt
```

---

## 📌 最佳实践

1. **及时记录** - 重要决策和解决方案立即记录
2. **使用标签** - 添加有意义的标签便于检索
3. **概念标注** - 使用 `--concepts` 标注概念类型
4. **定期导出** - 定期导出记忆备份
5. **项目隔离** - 不同项目使用不同路径
6. **区分长期与临时记忆** - 决策/方案适合 durable，自动捕获流水更适合 temporary

---

## 配置文件

编辑 `~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/config/config.json`：

```json
{
  "memory": {
    "db_path": "~/.claude/cc-mem/memory.db",
    "markdown_export_path": "~/cc-mem-export"
  },
  "capture": {
    "auto_capture": true,
    "capture_tool_calls": true
  }
}
```

## 数据库结构

### memories 表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT | 主键 |
| session_id | TEXT | 会话 ID |
| timestamp | DATETIME | 时间戳 |
| project_path | TEXT | 项目路径 |
| project_root | TEXT | 稳定项目根路径（git root 或当前路径） |
| category | TEXT | 类别 |
| source | TEXT | 来源（manual/post_tool_use/user_prompt_submit/stop_summary/...） |
| memory_kind | TEXT | 分层类型（durable/working/temporary） |
| auto_inject_policy | TEXT | 自动注入策略（always/conditional/manual_only/never） |
| expires_at | TEXT | 自动注入过期时间 |
| content | TEXT | 内容 |
| summary | TEXT | 摘要 |
| tags | TEXT | 标签（逗号分隔） |

### sessions 表

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT | 会话 ID |
| start_time | DATETIME | 开始时间 |
| end_time | DATETIME | 结束时间 |
| project_path | TEXT | 项目路径 |
| project_root | TEXT | 项目根路径 |
| message_count | INTEGER | 消息数 |
| summary | TEXT | 会话摘要 |

## Hooks

### SessionStart Hook

在每次会话启动时自动执行：

1. 记录会话开始
2. 按 `project_root` 加载当前项目高价值记忆
3. 必要时补 1 条 related project 记忆
4. 连续 debug / 连续决策链时追加 timeline hint
5. 输出结构化 `<cc-mem-context>` 注入块

### SessionEnd Hook

在会话结束时自动执行：

1. 更新会话状态和摘要
2. 检查是否还有未落库的操作日志
3. 将剩余日志作为最终兜底记忆写入数据库
4. 清空临时日志，结束本次会话

### PostToolUse Hook

在工具使用后累积操作记录：

- **触发工具**：Edit、Write、Bash
- **记录内容**：文件变更、命令执行
- **累积阈值**：每 3 次操作自动保存一次

### UserPromptSubmit Hook

在用户输入提示前批量保存记忆，并执行轻量 recall：

- **自动分类**：根据内容识别 debug/solution/decision/context
- **批量保存**：将累积的操作记录一次性保存到数据库
- **Query Recall**：基于当前 prompt 检索 2-3 条相关摘要
- **中文支持**：中文查询优先 FTS，结果不足时回退到 LIKE
- **输出约束**：stdout 只输出结构化 recall 注入块
- **会话兜底**：SessionEnd Hook 保存剩余记录

**数据安全性提升**：从"仅 session-end 兜底"到"三层捕获机制"，会话意外中断时最多丢失最近 5 次操作。

## Markdown 导出格式

导出的 Markdown 文件包含：

- Frontmatter 元数据
- 标签（YAML 格式）
- 项目链接
- 元数据信息

导出位置：由 `-o` 参数、环境变量或配置文件指定（默认：`~/cc-mem-export`）

## 高级用法

### 手动创建记忆

```bash
ccmem-cli.sh store -p "/path/to/project" -c "pattern" -t "react,hooks" -m "自定义 Hook 模式"
# 然后输入内容，以 EOF 结束
```

### 全文检索

```bash
# 使用 SQLite FTS5 全文检索
ccmem-cli.sh search -q "database schema design" -l 10
```

### 项目隔离

记忆默认按 `project_root` 隔离；在 Git worktree 或父子项目场景下，会受控补充 related project 记忆，而不是做全局跨项目混入。

### 标签系统

使用逗号分隔的标签：

```bash
ccmem-cli.sh capture -t "important,architecture,database"
```

### 记忆分层

默认映射：

- `manual + decision/solution/pattern` -> `durable + always`
- `manual + debug/context` -> `working + conditional`
- `user_prompt_submit / stop_summary` -> `working + conditional`
- `post_tool_use / session_end` -> `temporary + never`
- `stop_final_response` -> `temporary + manual_only`

---

## 竞品对比

| 特性 | **CC-mem** | claude-mem | memU | mem0 |
|------|------------|------------|------|------|
| **实现语言** | Bash | TypeScript | Python | Python |
| **依赖要求** | 仅 SQLite | Node/Bun | Python | Python |
| **数据库** | SQLite + FTS5 | SQLite + FTS5 | SQLite/Postgres | SQLite + Vector DB |
| **向量检索** | ❌ FTS5 全文检索 | ❌ FTS5 | ✅ pgvector | ✅ 25+ Vector DB |
| **记忆历史** | ✅ | ✅ | ✅ | ✅ |
| **内容去重** | ✅ SHA256 | ✅ | ✅ | ✅ |
| **概念标签** | ✅ 7 种自动识别 | ✅ | ✅ | ✅ |
| **三层检索** | ✅ | ✅ | ✅ | ✅ |
| **Hooks 集成** | ✅ | ✅ | ✅ | ✅ |
| **Graph 记忆** | ❌ | ❌ | ✅ | ✅ |
| **MCP 工具** | ❌ | ✅ | ❌ | ✅ |
| **Web UI** | ❌ | ✅ | ❌ | ✅ |
| **多模态** | ❌ | ❌ | ✅ | ✅ |

### 选择建议

| 需求 | 推荐项目 |
|------|----------|
| 个人轻量使用 | **CC-mem** ✅ |
| 企业级部署 | mem0 |
| 需要向量检索 | mem0 / memU |
| 需要 Graph 记忆 | memU |
| 需要 Web UI | claude-mem / mem0 |
| 零依赖安装 | **CC-mem** ✅ |

---

## 技术选型说明

### 为什么使用 SQLite 而不是 Markdown 文件？

**SQLite 是系统内置的**（macOS/Linux 自带），不是额外依赖。选择 SQLite 的原因：

| 考量 | SQLite | Markdown 文件 |
|------|--------|--------------|
| **检索效率** | ✅ FTS5 全文检索，毫秒级 | ❌ 需要遍历所有文件 |
| **去重检测** | ✅ 哈希索引，O(1) 查询 | ❌ 需要遍历比较 |
| **结构化查询** | ✅ 按类别/项目/时间筛选 | ❌ 需要手动解析 |
| **事务安全** | ✅ 原子操作，不会损坏 | ❌ 并发写入可能损坏 |

**结论**：SQLite 提供零额外依赖的高性能存储方案，适合大规模记忆管理。

---

## 致谢

CC-mem 在开发过程中参考了以下优秀项目，感谢它们在产品功能特性层面提供的参考：

- **[claude-mem](https://github.com/thedotmack/claude-mem)** - Hooks 集成架构、会话上下文文件设计
- **[memU](https://github.com/NevaMind-AI/memU)** - 记忆作为文件系统理念、Proactive Memory 设计
- **[mem0](https://github.com/mem0ai/mem0)** - 事实提取 Prompt、记忆历史追踪、测试框架参考

CC-mem 定位为轻量级替代方案，采用纯 Bash 实现，专注于个人用户的简单使用场景。

---

## 故障排除

### 数据库未初始化

```bash
ccmem-cli.sh init
```

### 权限问题

```bash
chmod +x ~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/bin/*.sh
chmod +x ~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/hooks/*.sh
```

### 检索不到记忆

1. 检查项目路径是否匹配
2. 尝试不使用 `-p` 参数进行全局检索
3. 检查标签拼写

## 隐私和安全

- 所有数据本地存储
- 可配置敏感信息过滤
- 支持按项目隔离记忆
- 定期清理过期数据

## 开发计划

- [ ] 向量检索支持
- [ ] 更智能的自动分类
- [ ] Graph 视图关联
- [ ] 跨项目记忆关联
- [ ] 定时任务支持

## License

MIT
