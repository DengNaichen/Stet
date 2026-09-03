# Stet Harness

本文件说明 Stet 的 agent harness：文档分层、workflow 入口与 drift 处理。它不是产品知识库；具体事实见各 owner 文档与代码。

## 文档分层

| 文档 | 职责 | 不是什么 |
|------|------|----------|
| [AGENTS.md](../AGENTS.md) | agent 如何开始与路由 | 知识库 |
| [CLAUDE.md](../CLAUDE.md) | Claude Code 入口（symlink → AGENTS.md） | 独立 Claude 指南 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 系统地图与模块边界 | 产品需求 |
| [specs/](specs/index.md) | 产品 WHAT / WHY | 实现细节 |
| [exec-plans/](exec-plans/README.md) | 冻结的技术方案 | 当前行为真相 |
| [VALIDATION.md](VALIDATION.md) | 验证命令与 done 定义 | 架构 |
| [rules/](rules/index.md) | 硬约束与产品判断 | workflow 步骤 |
| [reference/](../reference/README.md) | Apple 平台参考库（按需读） | 项目 spec / 真相 |
| [.cursor/](../.cursor/README.md) / [.claude/](../.claude/README.md) / [.codex/](../.codex/README.md) | 各工具 lifecycle 适配 | agent 知识 |
| 代码 | 当前行为真相 | — |

## Skills

Workflow skills（若存在）放在 `.agents/skills/`。平台参考库在 [`reference/apple-platform/`](../reference/apple-platform/index.md)，**不得**再注册为独立 skills。

## Legacy 与归档

旧 specs 已移至 `docs/archive/specs-legacy/`（gitignored）。说明见 [archive/README.md](archive/README.md)。

## CI 与 release

Plan A 迁移后，可执行的 workflow 均在仓库根 [`.github/workflows/`](../.github/workflows/)。[`Public/Stet/.github/workflows/`](../Public/Stet/.github/workflows/) 下保留的副本仅供对照，GitHub 不会执行。

- CI 与验证映射：[`.github/README.md`](../.github/README.md)、[VALIDATION.md](VALIDATION.md)
- macOS release 流程：[`Public/Stet/docs/release.md`](../Public/Stet/docs/release.md)

## 漂移处理

若 AGENTS、架构地图、rules、VALIDATION 或代码互相冲突，不要 silent pick 一边；先核对真实文件，再同步修复 owner artifact。
