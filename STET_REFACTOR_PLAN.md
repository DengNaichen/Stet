# Stet 项目重构计划 (Refactoring Plan)

为了提升 `Stet` 代码的可维护性，并为跨平台迁移（iOS 适配）做准备，我们需要对当前 `Stet` 的核心模块进行以下重构。

## 1. 日志系统升级 (Logging System)
**现状**：使用自定义的 `AppLogger`，强依赖于 `MacPreferences` 和硬编码的子系统名称。
**目标**：切换到苹果原生的 `os.Logger`，实现轻量化和高性能。

*   **任务**：
    1.  在核心 Service 中引入 `import os`。
    2.  删除对 `AppLogger.info/error` 的调用。
    3.  使用 `Logger(subsystem: Bundle.main.bundleIdentifier!, category: "...")` 替代。
*   **验收标准**：
    *   删除 `AppLogger.swift` 后，核心逻辑层编译通过。
    *   在 macOS 控制台 (Console.app) 中能按类别筛选日志。

## 2. 消除硬编码路径与标识符 (Hardcoded Values)
**现状**：`ModelManager` 中硬编码了 `"Stet"` 文件夹名；`TranscriptionService` 中硬编码了 Bundle ID。
**目标**：实现“环境感知”的路径解析。

*   **任务**：
    1.  **路径参数化**：`ModelManager` 的 `init` 增加 `rootDirectoryName: String` 参数。
    2.  **标识符动态化**：使用 `Bundle.main.bundleIdentifier` 获取子系统名称。
*   **验收标准**：
    *   通过初始化参数，可以让模型存储在任意命名的文件夹下。

## 3. 偏好设置解耦 (Settings Decoupling)
**现状**：`ModelManager` 直接读取 `MacPreferences.sherpaOnnxSenseVoiceModelPath`。
**目标**：通过协议（Protocol）或依赖注入传递配置，不再依赖具体的 `MacPreferences` 枚举。

*   **任务**：
    1.  定义 `ModelStorageConfiguration` 协议。
    2.  `ModelManager` 仅持有该协议的实例，不直接访问 `UserDefaults`。
*   **验收标准**：
    *   核心代码中不再出现 `import MacPreferences`。

## 4. 模型策略与平台适配 (Platform Strategy)
**现状**：模型切换逻辑分散在 ViewModel 和 PipelineFactory 中。
**目标**：统一模型可用性判断。

*   **任务**：
    1.  重构 `DictationExecutionRouteResolver`，增加平台判断。
    2.  针对 iOS 目标，强制返回 `.senseVoice` 路由，屏蔽其他离线模型。
*   **验收标准**：
    *   iOS 编译目标下，所有非 SenseVoice 的代码分支通过 `#if os(macOS)` 屏蔽。

## 5. 错误处理标准化
**现状**：`SenseVoiceError` 的描述信息中包含了一些特定于 macOS 的文案。
**目标**：根据运行平台返回不同的错误描述。

*   **任务**：
    1.  使用 `LocalizedError` 扩展，通过 `os` 判断返回“在设置中修改” (macOS) 或“请重新安装” (iOS) 等文案。
