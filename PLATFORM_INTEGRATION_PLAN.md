# Stet 跨平台架构集成与迁移计划 (macOS & iOS)

本文档旨在规划如何将当前的 iOS 项目 (`testvoice`) 与 macOS 端正在开发的共享核心逻辑进行对齐，实现“一套调度逻辑，多端自适应执行”。

---

## 1. 现状：iOS 端的模块化准备 (Current State)

经过最近的重构，iOS 项目已经完成了从“平铺结构”到“模块化结构”的转变，为接入共享包打下了基础：

*   **Features 层**：每个功能（Dictation, Dictionary, Home）拥有独立的 View 和 ViewModel，且 ViewModel 仅负责 UI 状态。
*   **Core 层 (待迁移)**：
    *   `Core/Engine`：包含了目前的 ASR (SherpaOnnx) 核心。
    *   `Core/Shared`：包含了 `SharedDictationManager`，解决了主 App 与键盘扩展之间的通信。
*   **工程配置**：采用了 Xcode 16 的“文件系统同步组”，支持文件夹级别的自动同步，方便未来直接引入共享文件夹或 Swift Package。

---

## 2. 目标现状：共享核心接入 (Target State)

未来的目标是让 iOS 端的 `Core/Engine` 逻辑完全消失，转而调用来自 macOS 端的共享包（如 `StetKit` 或 `StetShared`）。

### 核心变更点：
*   **代码删除**：删除 iOS 本地的 `SherpaOnnx.swift`、`SenseVoiceResources.swift` 等，改由共享包提供。
*   **统一接口**：iOS 和 macOS 共同实现一个 `TranscriptionService` 协议。
*   **资源管理**：模型文件 (ONNX) 依然保留在各端的 `Resources` 中，但加载逻辑由共享包统一控制。

---

## 3. 跨平台模型调度逻辑 (Unified Dispatch Logic)

这是本计划的核心：**你不希望管理两个包，只希望管理如何调度。**

我们将引入一个共享的 `TranscriptionExecutionRoute`（执行路由），其内部逻辑如下：

```swift
// 共享包中的伪代码逻辑
public class TranscriptionExecutionRoute {
    public static func getService() -> any TranscriptionService {
        #if os(iOS)
            // iOS 平台硬编码策略：极致速度，固定使用 SenseVoice
            return SherpaOnnxSenseVoiceService()
        #elseif os(macOS)
            // macOS 平台自由策略：根据用户设置切换 Whisper/SenseVoice/Cloud
            let userPreference = Settings.selectedModel
            return TranscriptionServiceFactory.create(for: userPreference)
        #endif
    }
}
```

### 调度原则：
1.  **iOS 端 (性能优先)**：自动锁定在 SenseVoice 引擎上，不提供模型切换 UI，确保在移动端达到 0.2 以下的极低 RTF（实时率）。
2.  **macOS 端 (功能优先)**：支持多引擎切换，利用 Mac 强大的性能提供更高精度的 Whisper 或云端重写功能。
3.  **单点维护**：所有的“条件编译”逻辑 (`#if os(iOS)`) 都集中在共享包的 Factory 层面，业务层（ViewModel）只管调用 `getService().transcribe()`。

---

## 4. 迁移实施步骤

### 第一步：建立链接 (The Bridge)
*   将 macOS 端的 `StetShared` 以 **Local Swift Package** 的形式引入 iOS 项目。
*   将 iOS 的 `SharedDictationManager` 迁入共享包，统一 App Group 的读写逻辑。

### 第二步：替换引擎 (The Swap)
*   在 iOS 的 `SenseVoiceViewModel` 中，将对本地 `SherpaOnnx` 的直接调用，替换为对共享包接口的调用。
*   验证 iOS 键盘扩展是否能通过共享包获取到同样的 `DictationSession` 模型。

### 第三步：清理冗余 (The Cleanup)
*   删除 iOS 项目中 `Core/Engine` 下的所有旧代码。
*   确保 `StetKeyboard` Target 同样引用了共享包，从而实现全链路的代码复用。

---

## 5. 结论
通过这种方式，你只需要在共享包中维护一份“模型调度表”，而 iOS 项目将变成一个纯粹的“外壳”，仅负责 UI 呈现和调用共享包。这达到了“只管理调度逻辑”的目标。
