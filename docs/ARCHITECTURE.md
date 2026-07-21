# Stet 架构地图

本文件给出修改前需要掌握的粗粒度代码、数据和生成边界。本地环境见 [DEVELOPMENT.md](DEVELOPMENT.md)，验证入口见 [VALIDATION.md](VALIDATION.md)。

## 仓库地图

- `Stet.xcodeproj` 是构建入口：app target `Stet` 使用 `StetMac/`，test targets `StetTests`/`StetUITests` 使用 `StetMacTests/`/`StetMacUITests/`；`StetVisuals` 是 app 依赖并嵌入的 framework target，`Packages/StetEngine` 是本地 Swift package。[ARCHITECTURE-0009]
- `StetMac/App` 负责生命周期、装配、窗口和工作流；`Features` 负责用户界面；`Core` 负责音频、转写、重写、剪贴板/文本注入等底层服务；权限底层能力部分在 `Core`，统一权限状态与流程协调在 `App/Lifecycle/MacPermissionManager` 和 session controller；`Shared` 放共享模型与 utilities。[ARCHITECTURE-0010]
- `StetVisuals` 集中 dictation capsule UI、Metal shader/rendering、audio feature mapping 与视觉 signal/model。[ARCHITECTURE-0016]

## 核心领域 / 数据模型

- Dictation pipeline 以 settings snapshot 选择本地 ASR 与可选 rewrite；history/stats 使用 SwiftData，普通偏好使用 UserDefaults，provider API keys 使用 Keychain，本地 ASR models 位于 Application Support，录音/处理文件位于临时目录。[ARCHITECTURE-0014]

## 生成资产和外部状态

- 正式 macOS Release 固定生成 signed/notarized DMG 与 Sparkle appcast 并发布 GitHub Release；release candidate 关闭 appcast、只上传 Actions artifact。`dist/github-release/<tag>/` 是被 gitignore 的脚本生成输出，不是可编辑源头。[ARCHITECTURE-0015]

## 关键运行链路

- 启动装配按 `StetApp → MacAppModel → MacDictationWorkflowController → MacAppSessionController` 连接；convenience initializer 创建 presentation controllers 与 hotkey registrar，`configure()` 绑定 state/lifecycle/hotkey，`activate()` 处理权限门禁和 onboarding 呈现，`MacAppModel` 另按配置启动 MCP server。[ARCHITECTURE-0012]
- Dictation 从录音、音频后处理和本地 ASR 进入可选 rewrite，再由 `MacDictationCaptureCoordinator` 通过 text injection 投递，失败时保留 clipboard fallback。转写推理始终本地；配置成功的 cloud rewrite、ASR model download、Sparkle update 与 telemetry 是不同网络路径。[ARCHITECTURE-0013]

## 依赖方向判定

- `Packages/StetEngine/Package.swift` 以 `StetCore` 为基础：`StetRewrite` 依赖 Core，`StetAI` 依赖 Core 与 Rewrite，`StetASR` 依赖 Core 及 vendored ASR packages。[ARCHITECTURE-0011]

## 边界说明

- Xcode target 名与源码目录名不同；定位 build/test 配置时看 target，定位实现时看对应源码根。
- 用户可见流程在 `Features`，但状态和副作用 owner 可能位于 `App`、`Core` 或 `Packages/StetEngine`；沿实际装配链核对后再修改。

## 放置规则

当前职责边界以上述仓库地图和依赖方向为准；未确认新的长期放置规则。
