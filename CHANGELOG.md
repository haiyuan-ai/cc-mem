# CC-mem 变更日志

## [1.5.2] - 2026-03-07

### ✨ Major Improvements

#### 1. MCP Server 正式加入
- 新增零依赖 stdio MCP server：`mcp/server.py`
- 首批提供 6 个 MCP 工具：
  - `ccmem_capture`
  - `ccmem_search`
  - `ccmem_get`
  - `ccmem_timeline`
  - `ccmem_inject_context`
  - `ccmem_recall`
- MCP server 复用现有 `capture / search / get / timeline / inject-context / recall` 逻辑，不额外引入服务端存储层
- 为跨 agent 使用 `cc-mem` 铺平基础，便于 Claude / Codex / OpenCode 等通过 MCP 共用同一记忆库

#### 2. query-aware recall 提升为正式命令
- 新增 `ccmem-cli.sh recall`
- 统一输出 `<cc-mem-recall>` 注入块
- 让 CLI、MCP 和 hooks 三条链路共用同一套 recall 能力

#### 3. 新增 OpenCode 扩展骨架
- 新增 `extensions/opencode/`，作为仓库内独立扩展目录
- 通过 `cc-mem` MCP 提供：
  - 开场上下文注入
  - query-aware recall
  - 工具执行后的高价值记忆捕获
- 当前定位为实验性扩展，不影响主 Bash/SQLite 运行时稳定性
- 扩展侧增加：
  - session 级 `inject-context` 去重
  - fail-open MCP 调用
  - tool 输出本地降噪与裁剪
- 保持主 Bash/SQLite 运行时不引入额外 Node 依赖

#### 4. 记忆采集与注入链路增强
- hooks 捕获改为“成功才清空日志，失败则进入本地待处理队列”，降低自动采集路径的数据丢失风险
- `content_preview` 从固定长度截断升级为按 `memory_kind` 分层压缩：
  - `durable` 保留更长上下文
  - `working` 折叠空白后轻量压缩
  - `temporary` 优先提取 `[FILE_CHANGE]` / `[BASH]` / error / fix 等关键签名
- 机会式 cleanup 从“纯时间节流”升级为“时间节流 + 当前项目近期增长速率绕过”，在当前项目短时间内记忆增长过快时可提前执行安全清理
- 新增 `ccmem-cli.sh stats`，提供最近 N 天的记忆数量、分层分布与 Preview 压缩占比统计

### 🧪 Testing

- 新增 `tests/test_mcp.sh`
- 新增 `tests/test_extensions.sh`
- MCP smoke test 覆盖：
  - `initialize`
  - `tools/list`
  - `ccmem_capture`
  - `ccmem_recall`
- 扩展 smoke test 覆盖：
  - OpenCode 扩展目录结构
  - 插件入口 hook 契约
- CLI 新增 `recall` 命令回归测试
- CLI 新增 `stats` 命令回归测试
- 新增 hooks 失败入队测试，覆盖 `post-tool-use` / `stop` / `session-end`
- 新增 `content_preview` 分层压缩测试，覆盖 `durable` / `working` / `temporary`
- 新增 cleanup 增长速率绕过节流测试

## [1.5.1] - 2026-03-07

### ✨ Major Improvements

#### 1. 跨项目记忆关联正式落地
- 新增 `project_links` 表，显式管理受控的跨项目关联
- 新增 `related-projects`、`link-projects`、`unlink-projects`、`refresh-project-links` 命令
- `inject-context` 和 query recall 改为优先读取 `project_links`
- 自动关联支持 Git worktree、同仓库和父子项目路径，手动关联不会被自动刷新覆盖

#### 2. 记忆清理升级为双模式
- `cleanup` 默认改为安全模式，只清理低优先级临时记忆
- 新增 `cleanup --aggressive`，支持人工扩大到所有已过期记忆和超龄 `working` 记忆
- `stop` / `session-end` 增加机会式自动清理，采用限频 + 小批量删除策略
- 清理逻辑统一基于 `memory_kind`、`auto_inject_policy` 和 `expires_at`

#### 3. 规则自动分类接入真实决策链
- 新增 `lib/classification.sh`，为自动采集路径提供统一的规则分类器
- `post_tool_use`、`user_prompt_submit`、`session_end`、`stop_summary` 共享同一套分类逻辑
- 分类结果现在不只有 `category`，还会生成 `confidence` 和 `reason`
- 第二阶段已接入记忆分层决策：
  - 自动分类结果会继续影响 `memory_kind`
  - 自动分类结果会继续影响 `auto_inject_policy`
- 分类结果现在会以写入时快照形式持久化到 `memories`：
  - `classification_confidence`
  - `classification_reason`
  - `classification_source`
  - `classification_version`
- 新写入记忆会冻结当时的分类结果，后续规则调整不会自动重写历史记录
- `inject-context` 和 query recall 的 salience 排序现在优先读取库中的分类快照，旧记录缺字段时才运行时兜底重算
- hooks debug log 会记录完整决策链：
  - `CLASSIFICATION_SOURCE`
  - `CLASSIFICATION_VERSION`
  - `CATEGORY`
  - `CONFIDENCE`
  - `REASON`
  - `MEMORY_KIND`
  - `AUTO_INJECT_POLICY`

### 🛠 Internal Improvements

- 抽离 `hook_utils.sh`，统一 hooks 的运行时辅助逻辑
- 抽离 `memory_policy.sh` 和 `injection.sh`，降低 `sqlite.sh` 的职责耦合
- 移除旧的 `compress` 命令、`context` / `CLAUDE.md` 导出路线和已失效的 LLM 压缩残留
- 安装脚本与文档同步到当前运行时依赖和命令语义

### 🧪 Testing

- 新增 `project_links` 数据层和 CLI 回归测试
- 新增 safe / aggressive cleanup 测试
- 新增 hook 自动清理与节流测试
- 新增规则分类器单元测试
- 新增 `user-prompt-submit` / `session-end` 分类与分层联动测试
- 新增分类快照落库测试
- 新增 salience 排序与主项目优先级测试
- 真实 Git worktree、related project 注入 / recall 回归继续通过

## [1.5.0] - 2026-03-07

### ✨ Major Improvements

#### 1. 引入分层记忆模型
- `memories` 表新增 `source`、`memory_kind`、`auto_inject_policy`、`project_root`、`expires_at`
- 新写入会按来源和类别自动推导长期记忆、工作记忆和临时记忆
- 旧数据会按既有 tags/source 特征自动回填分层元数据

#### 2. 自动注入链路升级
- `SessionStart` 从普通搜索切换为结构化 `<cc-mem-context>` 注入
- `UserPromptSubmit` 新增基于当前 prompt 的 `<cc-mem-recall>` 轻量 recall
- 自动注入前会过滤过期临时记忆，并避免注入块再次回流入库

#### 3. 受控 related project 与 timeline hint
- related project 解析优先使用 Git/worktree `common-dir` 关系
- SessionStart 在主项目上下文不足时可补 1 条 related project 记忆
- 连续 debug / 连续决策链会自动附加短 `timeline hint`

### 🧪 Testing

- 新增旧数据回填测试
- 新增 related project / timeline hint / query recall 测试
- 新增真实 Git worktree 场景回归测试
- 全量测试套件通过

## [1.4.0] - 2026-03-06

### 🐛 Bug Fixes

#### 1. 修复全文检索功能（Critical）
**问题**: `retrieve_memories` 和 `retrieve_memories_staged` 函数中，FTS 查询使用 `id IN (SELECT rowid FROM memories_fts ...)` 进行匹配，但 `memories.id` 是 TEXT 类型（如 `mem_1234567890_abc`），而 FTS 的 `rowid` 是 INTEGER 类型，导致类型不匹配，任何关键词搜索都返回空结果。

**修复**: 将 `id IN (...)` 改为 `rowid IN (...)`，共修改 3 处：
- `lib/sqlite.sh:173` - `retrieve_memories`
- `lib/sqlite.sh:228` - `retrieve_memories_staged` 阶段 2
- `lib/sqlite.sh:245` - `retrieve_memories_staged` 阶段 3

#### 2. 修复写库失败的错误处理（Critical）
**问题**: `store_memory` 函数执行 INSERT 后不检查 `sqlite3` 退出码，即使数据库操作失败也会记录历史并返回成功，导致假成功和脏历史记录。

**修复**:
- 添加 `sqlite3` 退出码检查
- 失败时返回 `error:...` 而不是记忆 ID
- CLI 层处理 `error:` 前缀，显示错误信息并返回非零退出码

#### 3. 修复 init_db 后 FTS 索引丢失
**问题**: `init_db` 函数每次运行都会 `DROP TABLE memories_fts` 然后重建，导致已有数据的 FTS 索引被清空，搜索失效。

**修复**: 在创建 FTS 表后添加 `INSERT INTO memories_fts(memories_fts) VALUES('rebuild')`，确保已有数据被重新索引。

#### 4. 修复 stop.sh 统计逻辑不一致
**问题**: `stop.sh` 统计日志中的 `[EDIT]` 和 `[WRITE]` 标签，但 `post-tool-use.sh` 实际写入的是 `[FILE_CHANGE]`，导致统计永远为 0。

**修复**: 将统计逻辑改为匹配 `[FILE_CHANGE]`，并简化输出为 `Files=N`。

#### 5. 修复 test_framework.sh 路径错误
**问题**: `test_framework.sh` 的 `setup_test_db` 函数使用 `$SCRIPT_DIR` 变量，但该变量依赖于调用者定义，导致路径解析错误（`lib/lib/sqlite.sh`）。

**修复**: 让 `test_framework.sh` 自己检测路径（`TEST_FRAMEWORK_DIR`），不依赖外部变量。

#### 6. 修复边界测试断言
**问题**: `test_edge_cases.sh` 的 "空类别" 测试使用旧断言 `[[ "$id" == *"mem_"* || "$id" == *"CHECK"* ]]`，没有接受新的 `error:*` 行为。

**修复**: 更新断言为 `[[ "$id" == error:* ]]`，正确验证错误处理。

#### 7. 修复 test_hooks.sh 假测试
**问题**: `test_stop_generate_summary` 在没找到 "操作统计" 时仍然 PASS，只是文案不同（"摘要已生成"），不能防止回归。

**修复**: 没找到 "Files=" 时返回 FAIL。

#### 8. 添加中文 FTS 支持（CJK Fallback）
**问题**: SQLite FTS5 默认对中文分词支持不好，中文查询无法命中。

**修复**: 实现 CJK 检测 + LIKE 回退策略：
- 添加 `contains_cjk()` 函数检测 CJK 字符
- 中文查询自动启用 `content LIKE '%关键词%'` 回退
- 英文查询继续使用 FTS5 全文检索
- 支持 `retrieve_memories` 和 `retrieve_memories_staged` 两个函数

### 🧪 测试改进

- 添加真正的 FTS 全文检索测试用例（6 个新测试）
- 修复 `test_hooks.sh` 使用伪造 `[EDIT]/[WRITE]` 格式的问题，改为真实 `[FILE_CHANGE]` 格式
- 修复测试计数逻辑，避免因 `grep -c` 输出换行符导致的误报
- 修复测试框架路径问题
- 添加中文搜索测试用例（3 个新测试）

### 📊 测试统计

- SQLite 库测试: 46 个用例
- CLI 命令测试: 41 个用例
- 边界条件测试: 39 个用例
- Hooks 功能测试: 22 个用例
- **总计: 148 个测试用例，100% 通过**

---

## [1.3.0] 及更早版本

参见 Git 提交历史。
