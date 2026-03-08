# CC-mem

Claude Code 轻量级记忆管理系统

**测试**: ✅ 全量回归通过 | **许可**: MIT

---

## 产品定位

**CC-mem** 是一个面向 Claude Code 的**本地优先、规则驱动、分层存储、可解释注入的记忆系统**。

**目标用户**: 个人开发者、技术博主、AI 助手重度用户

**核心价值**:
- 🪶 **轻量简洁** - 纯 Bash 脚本，核心依赖 SQLite，运行链路不依赖 Node
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

- **自动采集**：PostToolUse / UserPromptSubmit / Stop / SessionEnd 持续沉淀工作过程
- **实时注入**：SessionStart 预热上下文 + UserPromptSubmit query-aware recall
- **分层记忆**：按来源、生命周期和自动注入资格组织记忆
- **跨项目关联**：通过 `project_links` 受控补充 related project 记忆
- **自动裁剪**：Stop / SessionEnd 会对超长回复和日志做本地裁剪
- **预览压缩**：`content_preview` 会按 `durable / working / temporary` 分层生成，兼顾保真度与存储效率
- **规则分类**：自动采集路径共享同一套本地分类器，生成类别、置信度与原因，并参与分层决策
- **Prompt 复用判断**：`user_prompt_submit` 会优先提取可复用的偏好、约束、规则和决策，跳过一次性确认语
- **Tool 信号提炼**：`post_tool_use` 更偏向提炼错误、修复、验证和文件变更信号，而不是把整段输出都提升为记忆
- **持久化存储**：SQLite 本地数据库
- **分层检索**：支持 FTS、中文 fallback、timeline、related project recall
- **失败兜底**：hooks 写库失败时会把原始日志转入本地待处理队列，避免直接丢失
- **MCP 工具**：支持通过 MCP 暴露 capture/search/get/timeline/inject-context/recall
- **Markdown 导出**：导出为标准 Markdown 文件
- **Hooks 集成**：SessionStart / UserPromptSubmit 自动注入，PostToolUse / Stop / SessionEnd 自动采集
- **记忆历史**：记录记忆事件与变更轨迹
- **内容去重**：基于内容哈希自动检测重复记忆
- **概念标签**：预定义概念自动识别

## 安装

### 系统要求

- **macOS** 10.15+ - 自带 Bash 和 SQLite
- **Linux** Ubuntu 18.04+ / Debian 10+ - 需安装 sqlite3
- **Windows** Windows 10/11 + WSL2

详细的依赖要求和安装说明见 **[兼容性指南](docs/COMPATIBILITY.md)**。

补充说明：
- 安装脚本推荐环境包含 `git`、`sqlite3`、`jq`
- 缺少 `jq` 时仍可完成基础安装注册，但 hooks 的自动注入 / 自动捕获能力建议安装 `jq`
- 如果要启用 MCP server，建议安装 `python3`

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
    "installLocation": "/ABSOLUTE/PATH/TO/.claude/plugins/marketplaces/haiyuan-ai-cc-mem",
    "lastUpdated": "2026-03-07T00:00:00.000Z"
  }
}
```

请填写真实绝对路径，不要写 `$HOME` 或 `~`。
例如：
- macOS: `/Users/yourname/.claude/plugins/marketplaces/haiyuan-ai-cc-mem`
- Linux/WSL: `/home/yourname/.claude/plugins/marketplaces/haiyuan-ai-cc-mem`

**步骤 3: 注册已安装插件**

编辑 `~/.claude/plugins/installed_plugins.json`，在 `plugins` 对象中添加：

```json
"cc-mem@haiyuan-ai-cc-mem": [
  {
    "scope": "user",
    "installPath": "/ABSOLUTE/PATH/TO/.claude/plugins/marketplaces/haiyuan-ai-cc-mem",
    "version": "main",
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

# 查看最近统计
ccmem-cli.sh stats --days 7

# 重试失败队列
ccmem-cli.sh retry

# 捕获记忆
echo "重要内容" | ccmem-cli.sh capture -c "decision" -t "tag1,tag2"

# 检索记忆
ccmem-cli.sh search -p "/path/to/project" -q "关键词"

# 生成 query-aware recall
ccmem-cli.sh recall -p "/path/to/project" -q "当前问题"

# 获取时间线上下文
ccmem-cli.sh timeline -a mem_xxx -b 3 -A 3

# 获取记忆详情
ccmem-cli.sh get mem_123 mem_456

# 列出最近记忆
ccmem-cli.sh list

# 手动创建记忆（自定义摘要）
ccmem-cli.sh capture -p "/path/to/project" -c "pattern" -t "tag" -m "摘要"

# 导出记忆
ccmem-cli.sh export -o "~/exports"

# 生成开场注入上下文
ccmem-cli.sh inject-context -p "/path/to/project" -l 3

# 列出所有项目
ccmem-cli.sh projects

# 列出关联项目
ccmem-cli.sh related-projects -p "/path/to/project"

# 手动建立/删除项目关联
ccmem-cli.sh link-projects "/repo/app" "/repo/lib-common" --reason "shared architecture"
ccmem-cli.sh unlink-projects "/repo/app" "/repo/lib-common"

# 清理过期记忆
ccmem-cli.sh cleanup -d 30

# 查看记忆历史
ccmem-cli.sh history -r -l 10

# 修复 FTS 全文索引（维护工具）
./scripts/repair-fts.sh --force --no-backup
```

### 常用说明

#### `stats` - 查看最近记忆统计

```bash
# 查看最近 7 天统计
ccmem-cli.sh stats

# 查看指定项目最近 14 天统计
ccmem-cli.sh stats --days 14 --project "/path/to/project"
```

输出特点：
- 显示最近 N 天的记忆数量
- 显示 `content` / `content_preview` 的字节统计与 Preview 占比
- 显示 durable / working / temporary 分层分布
- 支持按 `project_root` 过滤

#### `capture` - 捕获记忆

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

#### `search` - 检索记忆

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

#### `export` - 导出记忆

```bash
# 导出所有记忆到指定目录
ccmem-cli.sh export -o "~/cc-mem-exports"

# 导出指定项目记忆
ccmem-cli.sh export -p "/path/to/project" -o ~/exports
```

**导出格式**：标准 Markdown 文件，可用任何 Markdown 编辑器打开（VS Code, Typora, Obsidian 等）

#### `retry` - 重试失败队列

```bash
# 重试所有失败项
ccmem-cli.sh retry

# 仅预览将处理的失败项
ccmem-cli.sh retry --dry-run

# 只处理某类 hook 的失败项
ccmem-cli.sh retry --hook stop
```

适用场景：
- hooks 写库失败后，补写本地失败队列中的记忆
- 恢复时保留失败发生时的原项目归属，避免记忆脱离上下文
- duplicate 会视为已恢复并自动移除队列文件

#### `timeline` / `get`

```bash
# 获取记忆的前后上下文
ccmem-cli.sh timeline -a mem_123 -b 3 -A 3

# 参数说明
# -a: 锚点记忆 ID
# -b: 锚点之前的记忆数量（默认 3）
# -A: 锚点之后的记忆数量（默认 3）
```

#### `inject-context` / `recall`

```bash
# 生成当前项目的开场注入上下文
ccmem-cli.sh inject-context -p "/path/to/project" -l 3
```

输出特点：
- 只输出结构化 `<cc-mem-context>` 块
- 默认优先注入 durable / conditional 记忆
- 结果不足时会补 1 条 related project 记忆
- 连续 debug / 连续决策链会自动附加 timeline hint

#### `projects` / `related-projects`

```bash
# 列出所有记忆项目
ccmem-cli.sh projects
```

#### `cleanup`

```bash
# 查看当前项目的关联项目
ccmem-cli.sh related-projects -p "/repo/app"

# 手动建立关联
ccmem-cli.sh link-projects "/repo/app" "/repo/lib-common" --reason "shared architecture"

# 删除关联
ccmem-cli.sh unlink-projects "/repo/app" "/repo/lib-common"
```

补充说明：
- 当前项目始终优先，关联项目只作为补充
- 自动注入和 recall 最多补 1-2 条关联项目记忆
- worktree / 父子项目会自动建立强关联，手动关联可覆盖自动规则

```bash
# 默认：安全清理，只删除低优先级临时记忆
ccmem-cli.sh cleanup

# 激进模式：扩大到所有已过期记忆和超龄 working 记忆
ccmem-cli.sh cleanup --aggressive
```

## 配置文件

编辑 `~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/config/config.json`：

```json
{
  "memory_db": "~/.claude/cc-mem/memory.db",
  "failed_queue_dir": "/tmp/ccmem_failed_queue",
  "debug_log": "/tmp/ccmem_debug.log",
  "markdown_export_path": "~/cc-mem-export",
  "cleanup": {
    "throttle_seconds": 43200,
    "growth_threshold": 100,
    "growth_window_seconds": 3600
  },
  "preview": {
    "durable_max_chars": 320,
    "working_max_chars": 220,
    "temporary_max_chars": 180
  },
  "hooks": {
    "post_tool_use_flush_lines": 3
  },
  "injection": {
    "session_start_limit": 3,
    "recall_limit": 3,
    "related_project_limit": 1
  }
}
```

已接入的主要配置项：

- `memory_db`
- `failed_queue_dir`
- `debug_log`
- `cleanup.*`
- `preview.*`
- `hooks.post_tool_use_flush_lines`
- `injection.session_start_limit`
- `injection.recall_limit`
- `injection.related_project_limit`
- `markdown_export_path`

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
4. 写库失败时把原始日志转入本地失败队列
5. 触发机会式安全清理，结束本次会话

### PostToolUse Hook

在工具使用后累积操作记录：

- **触发工具**：Edit、Write、Bash
- **记录内容**：文件变更、命令执行
- **累积阈值**：每 3 次操作自动保存一次

### UserPromptSubmit Hook

在用户输入提示前批量保存记忆，并执行轻量 recall：

- **规则分类**：根据来源、摘要、内容、标签、概念推导 `debug/solution/decision/pattern/context`
- **批量保存**：将累积的操作记录一次性保存到数据库
- **Query Recall**：基于当前 prompt 检索 2-3 条相关摘要
- **中文支持**：中文查询优先 FTS，结果不足时回退到 LIKE
- **输出约束**：stdout 只输出结构化 recall 注入块
- **失败兜底**：写库失败时原始日志会进入本地待处理队列
- **会话兜底**：SessionEnd Hook 保存剩余记录

**数据安全性提升**：从“仅 session-end 兜底”到“三层捕获机制”，可以降低会话意外中断导致的操作丢失风险。

## Markdown 导出格式

导出的 Markdown 文件包含：

- Frontmatter 元数据
- 摘要标题
- 完整正文内容
- 项目与标签等基础元数据

导出位置：由 `-o` 参数或配置文件指定（默认：`~/cc-mem-export`）

## 竞品对比

| 特性 | **CC-mem** | claude-mem | memU | mem0 |
|------|------------|------------|------|------|
| **实现语言** | Bash | TypeScript | Python | Python |
| **依赖要求** | SQLite | Node/Bun + SQLite + Chroma | Python | Python |
| **数据库** | SQLite + FTS5 | SQLite + FTS5 + Chroma | SQLite / Postgres / pgvector | 向量数据库为主 |
| **向量检索** | ❌ | ✅ Chroma 混合检索 | ✅ pgvector / 向量检索 | ✅ 多种向量后端 |
| **记忆历史** | ✅ | ✅ | ✅ | ✅ |
| **内容去重** | ✅ 内容哈希 | ✅ | ✅ | ✅ |
| **概念标签** | ✅ 自动识别 | ✅ | ✅ | ✅ |
| **三层检索** | ✅ | ✅ | ✅ | ⚠️ 通用检索 |
| **Hooks 集成** | ✅ | ✅ | ❌ 原生 hooks | ❌ 原生 hooks |
| **Graph 记忆** | ❌ | ❌ | ✅ | ✅ 可选 |
| **MCP 工具** | ✅ | ✅ | ❌ | ✅ |
| **Web UI** | ❌ | ✅ | ❌ | ✅ |
| **多模态** | ❌ | ❌ | ✅ | ✅ |

## 致谢

CC-mem 在开发过程中参考了以下优秀项目，感谢它们在产品功能特性层面提供的参考：

- **[claude-mem](https://github.com/thedotmack/claude-mem)** - Hooks 集成架构、会话上下文文件设计
- **[memU](https://github.com/NevaMind-AI/memU)** - 记忆作为文件系统理念、Proactive Memory 设计
- **[mem0](https://github.com/mem0ai/mem0)** - 事实提取 Prompt、记忆历史追踪、测试框架参考
- **[RTK](https://github.com/rtk-ai/rtk)** - 分层过滤、失败保留原始输出、节流与降级策略的实现思路参考

CC-mem 定位为轻量级替代方案，采用纯 Bash 实现，专注于个人用户的简单使用场景。

---

## 故障排除

### 数据库未初始化

```bash
~/.claude/plugins/marketplaces/haiyuan-ai-cc-mem/bin/ccmem-cli.sh init
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
- 支持敏感内容过滤（如 `<private>` 标签）
- 支持按项目隔离记忆（基于 `project_root`）
- 支持清理过期数据（可手动执行 `cleanup`，hooks 也会机会式安全清理低优先级过期记忆）

## License

MIT
