# Stet Mac 客户端历史记录功能设计文档

## 1. 概述
本功能旨在记录用户每一次语音输入的全生命周期数据。通过记录从“原始转写”到“大语言模型（LLM）处理”再到“最终发送”的三个关键阶段，为用户提供可追溯的记录，并在输出失败或用户需要找回之前的输入时提供保障。

## 2. 核心记录内容
每条历史记录应包含以下三类文本：
1.  **原始转写输出 (Raw Transcription)**：ASR 引擎（如 Whisper 或 SenseVoice）直接生成的文本。
2.  **LLM 优化输出 (LLM Output)**：经过模型（如 GPT、Claude 或 Apple Intelligence）改写、纠错或润色后的文本。
3.  **最终发送输出 (Final Output)**：用户在确认阶段最终按下 Enter 键（或点击发送）后，实际发送到目标 App 的文本。这保证了记录的是用户认可并最终发出的最终版本。

## 3. 技术架构建议

### 3.1 核心组件：`DictationHistoryService` (位于 `StetEngine` Package)
为了保证核心逻辑的解耦和跨平台复用，建议将历史记录的核心逻辑实现在 **`Packages/StetEngine`** 中（建议放在 `StetCore` 或新建 `StetHistory` target）。

*   **模型定义**：在 `StetCore` 中定义 `HistoryEntry` (SwiftData 模型)。
*   **Service 实现**：`DictationHistoryService` 作为一个单例服务实现在 `StetCore` 中，负责数据库的初始化、数据写入和查询。
*   **导出逻辑**：JSON 转换逻辑也应实现在 Package 内部，以保证数据格式的统一。

### 3.2 调用关系
*   **Mac App**：通过 `import StetCore` 调用 Package 中的服务。
*   **UI 层**：设置页面 (`MacSettingsView`) 直接绑定 Package 提供的查询接口或 ViewModel。

### 3.2 追踪标识：`SessionID`
为了将分布在不同类中的三个阶段关联起来，需要在 `DictationViewModel` 开始捕获时生成一个唯一的 `sessionID` (UUID)，并随 Pipeline 流转或通过服务进行全局状态追踪。

---

## 4. 关键改动点与插入位置

### 阶段一：原始转写与 LLM 输出记录
**位置**：`Stet/Features/Dictation/DictationViewModel.swift`
**具体逻辑**：在 `stopCapture` 方法的异步任务中。

*   **插入点 A (Raw)**：在 `speechService.stopRecording` 返回后。
*   **插入点 B (LLM)**：在 `resultTransformer` 执行返回后。

```swift
// DictationViewModel.swift -> stopCapture()

// 1. 获取原始转写
let text = try await speechService.stopRecording(...) 
// [记录位置 A]: 记录 text 为 rawTranscription

let finalText: String
if let resultTransformer {
    // 2. 执行 LLM 变换
    finalText = try await resultTransformer(text)
    // [记录位置 B]: 更新记录的 llmOutput 为 finalText
} else {
    finalText = text
}

// 3. 进入结果状态
send(.transcriptionSucceeded(finalText))
```

### 阶段二：最终发送输出记录
**位置**：`Stet/App/Workflows/MacDictationCaptureCoordinator.swift`
**具体逻辑**：在 `handleCompletedCapture` 方法中。此方法负责将文本注入目标 App。

*   **插入点 C (Final)**：在确认注入成功或成功写入剪贴板后。

```swift
// MacDictationCaptureCoordinator.swift -> handleCompletedCapture(...)

// ... 执行注入逻辑 ...
if pasteOutcome == .verifiedSuccess {
    // [记录位置 C]: 确认发送成功，记录 text 为 finalOutput，状态标记为 Success
    return .completed
}

// ... 处理复制到剪贴板逻辑 ...
if outcome == .completed {
    // [记录位置 C]: 确认已存入剪贴板，记录 text 为 finalOutput
    return .completed
}
```

### 阶段三：手动确认提交（补漏）
**位置**：`Stet/App/Workflows/MacAppSessionController+Dictation.swift`
**具体逻辑**：在 `commitPendingCopy` 方法中。此方法通常由用户按下 Enter 键或点击 UI 上的发送按钮触发。

*   **插入点 D**：在用户最终按下 Enter 键，将处于待定状态（Pending）的文本正式提交并发送时。

---

## 5. 详细改动方案建议

### 5.1 SwiftData 持久化
1.  **模型定义**：在 `Packages/StetEngine/Sources/StetCore/Models/HistoryEntry.swift` 中定义 `HistoryEntry`。
    *   字段：`id`, `timestamp`, `targetBundleID`, `rawText`, `llmText`, `finalText`, `status`。
2.  **Service 实现**：`DictationHistoryService` 实现在 `Packages/StetEngine/Sources/StetCore/Services/` 下。

### 5.2 设置界面 (Settings UI)
1.  **添加 Tab**：在 `Stet/Features/MacShell/Setting/MacSettingsView.swift` 的 `MacSettingsTab` 中增加 `.history` 选项。
    *   **图标**：`clock.arrow.circlepath`
    *   **标题**：History
2.  **列表展示**：创建 `MacHistorySettingsView.swift`，使用 `List` 展示历史记录。每条记录应能清晰展示 ASR 原始文本、LLM 优化文本以及最终发送文本这三层状态。
3.  **导出功能**：在 History 页面添加一个“Export JSON”按钮。

### 5.3 JSON 导出逻辑
1.  **实现**：使用 `JSONEncoder` 将 `[HistoryEntry]` 转换为 JSON 格式。
2.  **交互**：点击导出按钮后弹出 `NSSavePanel`，允许用户保存为 `.json` 文件。

## 6. 任务清单 (Tasks)
1. [ ] 创建 `HistoryEntry` SwiftData 模型。
2. [ ] 实现 `DictationHistoryService` 服务类。
3. [ ] 在 `DictationViewModel` 中记录 Raw 与 LLM 输出。
4. [ ] 在 `CaptureCoordinator` 中记录按下 Enter 后的 Final 输出。
5. [ ] 在设置页面 (`MacSettingsView`) 增加 History 栏目。
6. [ ] 开发 `MacHistorySettingsView` 并实现 JSON 导出。

## 7. 注意事项与优化
1.  **异步持久化**：所有的写入操作必须在后台进行，不得阻塞语音识别主流程。
2.  **空内容过滤**：不记录空白的转写结果。
