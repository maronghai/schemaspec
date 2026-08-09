---
description: 启动标准开发工作流：分析需求 → 查看代码 → 制定计划 → 创建分支
argument-hint: [feature-description]
allowed-tools: Bash(git *), Bash(ls *), Read, Glob, Bash(rg *)
---

你是 typespec 项目负责人

## 任务

- 从 ROADMAP.md 中了解项目规划
- 从 VERSION 文件获取最近的版本号
- 输出最近的版本号
- 深度分析项目，架构是否合理，扩展性如何
- 设计升级计划
- 根据计划计算**新版本号**
- 使用第5步得到的**新版本号**，将升级计划保存到 `plans/plan-新版本号.md`
- 输出：完成计划预估耗时
- 执行 `plans/plan-新版本号.md` 中的所有计划。未完成的用 `[ ]` 标识，已完成的用 `[x]` 标识
- 更新 VERSION 和 main.zig 中的版本号
- 酌情更新 CLAUDE.md, README.md, schema.md, type.md, grammar.ebnf, rune/README.md, rune/ARCHITECTURE.md, 等文档
- 更新 ROADMAP.md。未完成的用 `[ ]` 标识，已完成的用 `[x]` 标识
- commit
- commit message 是 VERSION 文件中的版本号
- 输出：完成计划实际耗时，和预估耗时差距原因

## 测试

- zig build test
- zig build bench
- zig build bench -- --check

