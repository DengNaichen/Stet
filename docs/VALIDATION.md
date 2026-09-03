# Stet 验证

本文件只保留仓库级验证入口、适用范围与报告边界。端内定向命令由各端文档维护；硬约束见 [rules/](rules/index.md) 与 [ARCHITECTURE.md](ARCHITECTURE.md)。

不要把计划执行或 CI 配置推断为已通过。Agent 必须报告实际命令、退出码和未运行项。

## 常用入口

| 范围 | 直接命令 | 详细入口 |
|------|----------|----------|
| macOS build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build` | [`Public/Stet/AGENTS.md`](../Public/Stet/AGENTS.md) |
| macOS test | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` | [`Public/Stet/AGENTS.md`](../Public/Stet/AGENTS.md) |
| iOS build | `make ios-build` | [`Private/StetMobile/AGENTS.md`](../Private/StetMobile/AGENTS.md) |
| lint / format | `make lint` | 根 [`Makefile`](../Makefile) |
| Harness 入口检查 | `scripts/validate-agent-entrypoints` | 本文件 |

macOS-only 目标（`ci-build`、`release-github`、`doctor` 等）见 [`Public/Stet/Makefile`](../Public/Stet/Makefile)。

## Hook 与 CI

- Pre-commit：`.githooks/`（若已安装）。
- GitHub Actions 总览：[`.github/README.md`](../.github/README.md)。
- 根 `Makefile` 将 macOS 目标委托给 `Public/Stet/Makefile`，iOS 目标直接构建 `Private/StetMobile/StetMobile.xcodeproj`。

### monorepo-ci.yml

仓库根 [`.github/workflows/monorepo-ci.yml`](../.github/workflows/monorepo-ci.yml) 在 PR 与 push 到 `main`、`migration/**` 时运行：

| CI job | 本地等价命令 |
|--------|--------------|
| Swift Quality | `make lint` |
| macOS Build | `make ci-build` |
| macOS Tests | `make test` |

### Release workflows

签名 release 与 RC 构建在根 [`.github/workflows/`](../.github/workflows/)（`macos-release.yml`、`macos-release-candidate.yml`），job 使用 `working-directory: Public/Stet`，因 Xcode 工程与 release 脚本位于该子树。

### 本地-only

`make ios-build` 目前不在 CI 中；本地验证 iOS 时使用，详见 [`Private/StetMobile/AGENTS.md`](../Private/StetMobile/AGENTS.md)。

## 执行与报告

Agent 必须区分：

- `passed`：适用命令已运行且退出码为零。
- `failed`：至少一个适用命令运行失败。
- `skipped`：有意跳过并记录原因。
- `not_run`：验证适用但未执行。
