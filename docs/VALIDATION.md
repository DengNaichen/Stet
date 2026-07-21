# Stet 验证

本文件只记录当前仓库自身已确认的验证项、真实执行入口、自动化绑定和结果报告要求。硬约束分布在各实践文件和 [ARCHITECTURE.md](ARCHITECTURE.md) 的“硬约束”段，操作入口放在 [AGENTS.md](../AGENTS.md)。

不要假设仓库使用特定 VCS、runner、hook、CI 或平台 gate。只有从目标仓库已有配置、脚本、清单、workflow、测试或团队确认中核对过的内容，才能写成已配置 validation。

## 验证项

| 项目 | 状态 | 命令 / 入口 | 适用范围 | 证据 |
| --- | --- | --- | --- | --- |
| 静态检查 [VALIDATION-0001] | 已配置 | `make lint` | SwiftLint 与 Swift Format lint | `Makefile` |
| 无签名 Debug 构建 [VALIDATION-0002] | 已配置 | `make ci-build` | macOS `Stet` scheme | `Makefile` |
| macOS 单元测试 [VALIDATION-0003] | 已配置 | `make test` | `StetTests`，macOS arm64 | `Makefile`、`Stet.xcodeproj/xcshareddata/xcschemes/Stet.xcscheme` |

## 执行入口与绑定

当前的 `macOS CI` 在拉取请求和推送到 `main` 时，分别执行 `make swiftlint`、`make format-lint`、`make ci-build` 和 `make test` [VALIDATION-0004]。它仅在 workflow 列出的路径变更时触发；当前 `Packages/StetEngine/**` 不在该列表中。

`Packages/StetEngine/**` 的改动必须触发现有 macOS CI 检查 [VALIDATION-0005]。

## 结果报告

- 已运行项：报告实际命令或入口及结果。
- 未运行或无法运行项：报告项目、原因和影响。
- 失败项：保留真实失败状态，不把局部通过概括为完整验证通过。
