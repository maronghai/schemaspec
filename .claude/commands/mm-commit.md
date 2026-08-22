---
description: 启动提交工作流
argument-hint: [提交版本]
allowed-tools: Bash(git *), Bash(ls *), Read, Glob, Bash(rg *)
---

你是 typespec 项目负责人

## 任务

- 从 VERSION 文件获取最近的版本号
- 输出最近的版本号
- 计算**新版本号**
- 更新 VERSION 和 main.zig 中的版本号
- 酌情更新 CLAUDE.md, README.md, schemaspec/schema.md, schemaspec/type.md, schemaspec/grammar.ebnf, rune/README.md, rune/ARCHITECTURE.md, 等文档
- 更新 ROADMAP.md。未完成的用 `[ ]` 标识，已完成的用 `[x]` 标识
- commit
- commit message 是 VERSION 文件中的版本号

## 测试

- zig build test
- zig build bench
- zig build bench -- --check

## 本地部署

- d:\zbin\zb.cmd rune
