# CC-mem 变更日志

## [1.5.1] - 2026-03-07

### 🧹 Cleanup Strategy Upgrade

- `cleanup` 命令改为默认安全模式，只清理低优先级临时记忆
- 新增 `cleanup --aggressive`，可手动扩大到所有已过期记忆和超龄 working 记忆
- `stop` / `session-end` 新增机会式自动清理，采用限频 + 小批量删除策略
- 自动清理基于 `memory_kind`、`auto_inject_policy` 和 `expires_at`，不再使用粗粒度全量清理

### ✨ Cross-Project Memory Linking

- 新增 `project_links` 表，用于存储受控跨项目关联
- 新增 `related-projects`、`link-projects`、`unlink-projects`、`refresh-project-links` 命令
- `inject-context` 和 query recall 改为优先读取 `project_links`
- 自动关联支持 Git worktree / 父子项目路径，手动关联可覆盖自动规则

### 🧪 Testing

- 新增 safe/aggressive cleanup 测试
- 新增 hook 自动清理与节流测试
- 新增 `project_links` 数据层测试
- 新增项目关联 CLI 测试
- 原有 related project 注入 / recall / worktree 回归测试继续通过

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
