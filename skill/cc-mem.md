---
name: cc-mem
description: |
  操作 cc-mem SQLite 记忆插件（非 Claude 内置 memory）
  轻量级本地记忆管理系统，支持 list/search/status/capture/export 等

triggers:
  - /cc-mem
  - /ccmem
category: productivity
author: haiyuan-ai
version: 1.5.3
---

# CC-Mem Skill

## 说明

本 Skill 用于操作 **cc-mem 插件**（SQLite 本地记忆数据库），
**不是** Claude Code 内置的 auto-memory 系统。

## 命令

### 查看状态
```
/cc-mem status
```
显示数据库状态、记忆数量、失败队列等信息。

### 列出记忆
```
/cc-mem list
/cc-mem list -l 10
```
列出最近的记忆记录，`-l` 指定数量。

### 搜索记忆
```
/cc-mem search <关键词>
/cc-mem search -c decision API
```
搜索记忆内容，`-c` 按类别过滤。

### 查看统计
```
/cc-mem stats
/cc-mem stats --days 14
```
显示最近 N 天的记忆统计。

### 手动捕获
```
/cc-mem capture <内容>
/cc-mem capture -c decision "选择 SQLite 作为存储"
```
手动创建一条记忆。

### 导出记忆
```
/cc-mem export
/cc-mem export -o ~/exports
```
导出记忆为 Markdown 文件。

### 重试失败队列
```
/cc-mem retry
```
重试之前失败的记忆捕获。

### 清理过期记忆
```
/cc-mem cleanup
```
清理过期的临时记忆。

### 获取帮助
```
/cc-mem help
```

## 与内置 memory 的区别

| 特性 | cc-mem (本 Skill) | Claude auto-memory |
|------|-------------------|-------------------|
| 存储位置 | SQLite 数据库 | 文件系统 |
| 项目隔离 | ✅ 按项目路径隔离 | ❌ 全局 |
| FTS 搜索 | ✅ 支持 | ❌ 不支持 |
| Hooks 集成 | ✅ Session/Tool/Stop | ⚠️ 仅 SessionStart |
| 导出 | ✅ Markdown | ❌ 不支持 |

## 安装

```bash
# 方法1：一键安装
curl -sSL https://raw.githubusercontent.com/haiyuan-ai/cc-mem/main/install.sh | bash

# 方法2：让 Claude 帮你安装
安装 https://github.com/haiyuan-ai/cc-mem
```

## 数据库位置

默认：`~/.claude/cc-mem/memory.db`

## 更多信息

GitHub: https://github.com/haiyuan-ai/cc-mem
