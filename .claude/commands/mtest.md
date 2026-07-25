---
description: 启动标准开发工作流：分析需求 → 查看代码 → 制定计划 → 创建分支
argument-hint: [feature-description]
allowed-tools: Bash(git *), Bash(ls *), Read, Glob
---

## 任务

1. 从 VERSION 文件获取最近的版本号
2. 输出最近的版本号
3. 深度分析项目，架构是否合理，扩展性如何
4. 设计升级计划
5. 根据计划计算**新版本号**
6. 使用第5步得到的**新版本号**，将升级计划保存到 `plans/plan-新版本号.md`
7. 执行 `plans/plan-新版本号.md` 中的所有计划。未完成的用 `[ ]` 标识，已完成的用 `[x]` 标识
8. 更新 main.zig 中的版本号
9. 如有必要，更新 CLAUDE.md, README.md, schema.md, type.md, grammar.ebnf, rune/README.md, rune/ARCHITECTURE.md 等文档
