# Stet 验证

本文件只保留仓库级验证入口、适用范围与报告边界。端内定向命令由各端文档维护；硬约束见 [rules/](rules/index.md) 与 [ARCHITECTURE.md](ARCHITECTURE.md)。

不要把计划执行或 CI 配置推断为已通过。Agent 必须报告实际命令、退出码和未运行项。

## 常用入口

| 范围 | 直接命令 | 详细入口 |
|------|----------|----------|
| macOS build | <!-- TODO --> | <!-- TODO --> |
| macOS test | <!-- TODO --> | <!-- TODO --> |
| iOS build | <!-- TODO --> | <!-- TODO --> |
| lint / format | <!-- TODO --> | <!-- TODO --> |
| Harness 入口检查 | `scripts/validate-agent-entrypoints` | 本文件 |

## Hook 与 CI

<!-- TODO: pre-commit、GitHub Actions、Makefile 目标与绑定关系 -->

## 执行与报告

Agent 必须区分：

- `passed`：适用命令已运行且退出码为零。
- `failed`：至少一个适用命令运行失败。
- `skipped`：有意跳过并记录原因。
- `not_run`：验证适用但未执行。
