# Stet 验证

本文件记录 Stet 仓库自身的验证入口与自动化绑定。HarnessKit 的内部 verifier、runner 和 receipts 不属于这些项目验证项。

## 验证项

| 项目 | 状态 | 命令 / 入口 | 适用范围 |
| --- | --- | --- | --- |
| Swift 风格与静态检查 | 已配置 | `make lint` | 严格 SwiftLint 与 swift-format lint。[VALIDATION-0001] |
| macOS Debug 构建 | 已配置 | `make build` | `Stet` scheme 的 Debug macOS build。[VALIDATION-0002] |
| macOS tests | 已配置 | `make test` | 无代码签名运行 `StetTests`。[VALIDATION-0003] |

## 执行入口与绑定

- `.github/workflows/macos-ci.yml` 在 pull request 和 `main` push 命中其 path filter 时，分别运行 SwiftLint、swift-format lint、无签名 build 与 tests 四个 job。[VALIDATION-0004]
- `.githooks/pre-commit` 只在存在 staged Swift 文件时执行；它会用 `make format` 格式化四个源码/测试根，只重新暂存原先 staged 的 Swift 文件，再运行 `make swiftlint`，因此可能同时修改工作树和暂存区。[VALIDATION-0005]
- CI filter 登记的是 `StetTests/**` 与 `StetUITests/**`，而实际测试源码位于 `StetMacTests/**` 与 `StetMacUITests/**`；仅修改实际测试目录不会触发该 workflow。[VALIDATION-0006]

## 结果报告

- 报告实际运行的命令或 CI job 及其结果。
- 未运行、无法运行或失败时保留真实状态，并说明影响范围。
- `make lint`、`make build` 与 `make test` 是独立入口；局部通过不代表其余检查通过。
