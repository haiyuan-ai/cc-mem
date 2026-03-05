# CC-mem 文档索引

本文档索引整理了 cc-mem 项目的所有用户文档，方便查阅。

---

## 🚀 快速开始

| 文档 | 说明 |
|------|------|
| [README.md](../README.md) | 项目介绍、安装、功能、使用示例、最佳实践 |
| [COMPATIBILITY.md](./COMPATIBILITY.md) | macOS/Ubuntu/Windows 兼容性指南 |

---

## 📖 用户文档

### 测试与兼容性

| 文档 | 说明 |
|------|------|
| [GIT-BASH-TEST.md](./GIT-BASH-TEST.md) | Git Bash (Windows) 测试指南（开发者） |

---

## 🧪 测试文档

| 文档 | 说明 |
|------|------|
| [TEST-REPORT.md](../tests/TEST-REPORT.md) | 测试报告与覆盖总结（180 个测试 100% 通过） |

---

## 📁 项目结构

```
cc-mem/
├── README.md                 # 主文档（含快速开始、示例、最佳实践）
├── LICENSE                   # MIT 许可
├── .gitignore                # Git 忽略规则
├── docs/
│   ├── INDEX.md              # 文档索引
│   ├── COMPATIBILITY.md      # 兼容性指南
│   └── GIT-BASH-TEST.md      # Git Bash 测试（89 行精简版）
├── tests/
│   ├── TEST-REPORT.md        # 测试报告（133 个用例）
│   ├── test_sqlite.sh        # SQLite 测试（66 个函数）
│   ├── test_cli.sh           # CLI 测试（40 个函数）
│   ├── test_edge_cases.sh    # 边界测试（56 个函数）
│   ├── test_hooks.sh         # Hooks 功能测试（22 个函数）
│   ├── test_framework.sh     # 测试框架（12 个函数）
│   └── run_tests.sh          # 测试运行器
├── bin/
│   └── ccmem-cli.sh          # CLI 工具 (625 行)
├── lib/
│   ├── sqlite.sh             # SQLite 操作库 (623 行，20 个函数)
│   └── llm.sh                # LLM 压缩功能 (329 行，12 个函数)
├── hooks/
│   ├── hooks.json            # Hooks 配置（插件级别，自动加载）
│   ├── session-start.sh      # SessionStart Hook
│   ├── session-end.sh        # SessionEnd Hook（正常结束）
│   ├── stop.sh               # Stop Hook（会话中断时触发，可访问 transcript）
│   ├── post-tool-use.sh      # PostToolUse Hook (实时捕获)
│   └── user-prompt-submit.sh # UserPromptSubmit Hook (批量保存)
├── config/
│   └── config.json           # 配置文件
└── scripts/
    ├── check-compat.sh       # 兼容性检查脚本
    └── test-git-bash.sh      # Git Bash 测试脚本
```

---

## 🔗 相关链接

- **GitHub 仓库**: https://github.com/haiyuan-ai/cc-mem
- **问题反馈**: https://github.com/haiyuan-ai/cc-mem/issues
- **参考项目**:
  - [claude-mem](https://github.com/thedotmack/claude-mem)
  - [memU](https://github.com/NevaMind-AI/memU)
  - [mem0](https://github.com/mem0ai/mem0)

---

## 版本信息

**核心功能**:
- 自动捕获与语义压缩
- SQLite 持久化存储 + FTS5 全文检索
- 三层检索（search → timeline → get）
- 内容哈希去重
- 记忆历史追踪
- 概念标签自动识别
- 私有内容过滤
- Markdown 导出
- **Hooks 实时捕获**：PostToolUse + UserPromptSubmit + Stop + SessionEnd 四层捕获机制
  - Stop Hook 支持访问 transcript 生成会话摘要
