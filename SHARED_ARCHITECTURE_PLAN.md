# Stet 跨平台共享架构方案 (macOS & iOS)

本文档旨在指导如何将 `Stet` (macOS) 的核心逻辑提取出来，构建一个共享的 `StetShared` 库。

## 1. 核心目标：三大支柱
为了方便后续更新，我们将以下三个核心模块作为共享的重点：

*   **API Key 管理 (APIK)**：统一管理所有 AI Provider 的密钥。通过 **iCloud Keychain** (kSecAttrSynchronizable) 实现跨设备同步。
*   **词典管理 (Personal Dictionary)**：共享用户自定义词典和首选拼写规则。通过 **iCloud Key-Value Storage (NSUbiquitousKeyValueStore)** 实现静默同步。
*   **模型切换逻辑 (Model Switching)**：
    *   **macOS**: 支持 Whisper, SenseVoice, Parakeet 等多模型自由切换。
    *   **iOS (特殊限制)**: 默认不允许切换模型，固定使用 SenseVoice 以保证性能和响应速度。

---

## 2. 共享方案选择：Swift Package (SPM)
**推荐 Swift Package (Local)**：
*   直接引用源码，所见即所得。
*   支持针对 iOS 和 macOS 的条件编译。
*   Xcode 完美原生支持。

---

## 3. 建议提取的模块清单

### A. 网络与 AI 提供商 (Networking & AI Providers)
统一管理云端请求逻辑。
*   **源路径 (Stet)**: `Stet/Core/AIProviders/`
*   **关键文件**:
    *   `OpenAISDKClientFactory.swift`: 统一的 SDK 客户端构建。
    *   `OpenAIRewriteService.swift` 等具体 Provider 实现。
    *   `KeychainSecretStore.swift`: **APIK 管理的核心**，利用 Keychain 安全存储密钥。

### B. 词典与重写引擎 (Dictionary & Rewrite)
*   **源路径 (Stet)**: `Stet/Core/Rewrite/`
*   **关键文件**:
    *   `TextRewriteService.swift`: 包含所有清洗规则。
    *   `TextRewriteRequest.swift`: 包含 `preferredSpellings`（词典项）。

### C. 离线引擎与模型策略 (ASR & Model Policy)
*   **源路径 (Stet)**: `Stet/Core/SenseVoice/` 和 `Stet/Core/DictationPipeline/`
*   **关键文件**:
    *   `SherpaOnnxSenseVoiceTranscriptionService.swift`: ASR 核心。
    *   `DictationExecutionRoute.swift`: **模型切换逻辑**，在此处添加平台判断逻辑。

---

## 4. 阶段性实施计划 (Phased Implementation Plan)

### 第一阶段：基础设施与 APIK 同步 (Foundation & APIK)
**目标**：建立共享包，实现 API Key 的跨设备安全同步。
*   **任务**：
    1.  在根目录创建 `StetShared` 文件夹并初始化 `Package.swift`。
    2.  搬移 `KeychainSecretStore.swift`，并修改其底层逻辑以支持 `kSecAttrSynchronizable = true`。
    3.  在两个项目中引入 `StetKit` 库并替换原有的密钥读写逻辑。
*   **验收标准**：
    *   [ ] `StetKit` 能在 iOS 和 macOS 模拟器/真机上成功编译。
    *   [ ] 在 macOS 上输入 OpenAI Key 后，iOS App 能自动读取到该 Key 而无需重新输入。

### 第二阶段：转写引擎与词典同步 (Engine & Dictionary)
**目标**：统一识别核心，实现用户词典的静默同步。
*   **任务**：
    1.  搬移 `SherpaOnnxSenseVoiceTranscriptionService` 和 `ModelManager`。
    2.  利用 `NSUbiquitousKeyValueStore` 实现 `SharedDictionaryStore`。
    3.  统一 `DictationSession` 数据模型。
*   **验收标准**：
    *   [ ] iOS 和 macOS 使用同一套转写逻辑，识别率一致。
    *   [ ] 在 iOS 词典中新增一个专有名词（如 "Stet"），macOS 端的 `preferredSpellings` 列表能自动感知更新。

### 第三阶段：网络重写层与策略统一 (Networking & Prompts)
**目标**：共享 AI 处理能力，确保清洗逻辑完全一致。
*   **任务**：
    1.  搬移 `AIProviders` (OpenAI, Claude 等) 适配器。
    2.  搬移 `TextRewriteService.swift` 及其所有 System Prompts。
    3.  针对 iOS 实现“锁定 SenseVoice”的模型策略逻辑。
*   **验收标准**：
    *   [ ] 同一份原始转写文本，在 iOS 和 macOS 上通过“云端清洗”得到的最终文本完全一致。
    *   [ ] iOS 端设置界面无法切换离线模型，而 macOS 端可以。

---

## 5. 实施注意事项
1.  **权限声明**：在 iOS 和 macOS 的 `Entitlements` 中必须同时开启 `iCloud` 服务及其子项（Key-Value Storage 和 Keychain Sharing）。
2.  **模块化边界**：共享库中严禁 import `UIKit` 或 `AppKit`。如果必须使用 UI 相关功能，请定义 Protocol，由主项目实现。
3.  **资源路径**：模型文件由于体积大，不建议放入 SPM 包内，应保持在各项目的 `Resources` 中，由 `ModelManager` 动态寻找路径。
