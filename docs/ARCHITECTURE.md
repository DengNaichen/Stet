# Stet 架构地图

本文件是当前仓库的粗粒度架构地图。它帮助 agent 和贡献者在修改前找到正确的代码区域。本文件不是工作流规范、API 参考或详细设计文档。

## 仓库地图


- [`StetMac/`](../StetMac/) 是 macOS SwiftUI 应用层；[`StetApp.swift`](../StetMac/StetApp.swift) 创建 `MacAppModel`，并呈现菜单栏、设置与命令界面 [ARCHITECTURE-0001]。
- [`Packages/StetEngine/`](../Packages/StetEngine/) 是本地 Swift Package，提供 `StetCore`、`StetASR`、`StetRewrite` 和 `StetAI` library targets [ARCHITECTURE-0002]。
- [`Stet.xcodeproj`](../Stet.xcodeproj/project.pbxproj) 将 `Packages/StetEngine` 作为本地 package，并使用这四个产品 [ARCHITECTURE-0003]。

## 核心领域 / 数据模型

记录系统的核心领域实体和数据模型（主要"名词"和它们的关系），帮助 agent 改业务前建立心智地图。这是领域模型的唯一来源；不要在 rules 或 AGENTS 复述：

`DictationSettingsStore` 组装 `DictationSettingsSnapshot`；设置和个人词典使用 `UserDefaults`，provider API key 通过 `KeychainSecretStore` 读取 [ARCHITECTURE-0004]。

## 生成资产和外部状态

如果本仓库会生成文件、写入持久配置、发布包或维护外部状态，请在这里记录入口、集成系统及其用途和边界：

此地图未记录额外的生成源头；持久化设置和密钥边界见上节。

## 关键运行链路

记录 agent 修改前需要理解的主要执行链路、数据链路或生成链路：

`StetApp` 创建 `MacAppModel`，后者组装 `MacAppSessionController` 与 `MacDictationWorkflowController`。`DictationPipelineFactory.makePipeline(from:)` 使用 settings snapshot 选择语言、词典和 rewrite；其 `live()` local-transcription closure 从 `UserDefaultsModelStorage` 读取已选转写引擎 [ARCHITECTURE-0005]。

## 依赖方向判定

如果仓库存在模块、package、layer、workspace 或服务边界，请在这里记录依赖方向：

| 来源 | 允许依赖 | 禁止依赖 | 判断依据 |
|---|---|---|---|
| `StetMac` | `Packages/StetEngine` 的 `StetCore`、`StetASR`、`StetRewrite`、`StetAI` products | — | Xcode project 的 local package products |

## 边界说明

记录容易混淆、需要 agent 特别注意的边界：

`StetMac` 是 macOS app adapter；`Packages/StetEngine` 以 macOS/iOS library targets 承载可复用 engine 代码。

## 放置规则

新增代码容易误放时，在这里记录正确归属，避免放错模块或绕过生成源头。本节是放置规则的唯一来源（编码内部风格见 [docs/rules/CODING.md](rules/CODING.md)）：

| 场景 | 容易误放 | 正确位置 |
|---|---|---|
| 新增需跨模块共享的非 UI 听写引擎代码 [ARCHITECTURE-0006] | `StetMac` | 对应的 `Packages/StetEngine` target |

## 硬约束

以下规则必须始终成立，违反即为错误：

无额外已确认的架构硬约束。

## 更新规则

当主要模块、持久化边界或 package dependency 发生变化时，同步更新本文件。只有新路径改变 agent 首先应该查看的位置时，才把它加入这里。
