# 数据埋点方案

## 概述

Stet 的核心用户旅程是：**激活 → 录音 → 转录 → 改写 → 输出**。埋点围绕这条主线展开，优先覆盖能回答"用户用得多不多"和"哪里出了问题"的关键节点。

---

## 平台：TelemetryDeck

专为 Apple 平台设计，隐私优先（数据传输前哈希处理，不收集 PII），Swift SDK 原生支持，免费额度 10 万信号/月。

- 官网：[telemetrydeck.com](https://telemetrydeck.com)
- Swift SDK：[TelemetryDeck/SwiftSDK](https://github.com/TelemetryDeck/SwiftSDK)

### 集成方式

通过 Swift Package Manager 添加依赖，然后在 `StetApp.swift` 初始化：

```swift
import TelemetryDeck

// StetApp.init() 或 applicationDidFinishLaunching
TelemetryDeck.initialize(config: .init(appID: "YOUR-APP-ID"))
```

### 封装

在 `stet/Shared/Utilities/` 下新建 `AnalyticsService.swift`，统一调用入口，方便日后切换平台：

```swift
import TelemetryDeck

enum AnalyticsService {
    static func track(_ signal: String, parameters: [String: String] = [:]) {
        TelemetryDeck.signal(signal, parameters: parameters)
    }
}
```

TelemetryDeck 的 `parameters` 要求值为 `String`，数值类型转换后传入即可。

---

## 埋点清单

### 1. 核心转录流程

文件：`stet/App/Workflows/MacDictationWorkflowController.swift`

| 事件名 | 埋点位置 | 属性 |
|---|---|---|
| `dictation_started` | `startDictationCapture` 入口 | `source: "hotkey" / "interface"` |
| `dictation_capture_ended` | `stopActiveCapture` | — |
| `dictation_cancelled` | `cancelActiveCapture` | — |
| `dictation_completed` | `handleCompletedResult` 成功路径 | `word_count`, `duration_seconds`, `provider`, `rewrite_enabled` |

`word_count` 和 `duration_seconds` 已有现成计算逻辑（`pendingSessionDuration` / `countWords`），直接复用。

---

### 2. 输出结果

文件：`stet/App/Workflows/MacDictationCaptureCoordinator.swift`

`handleCompletedCapture` 已有详细本地日志（`emitOutputTrace`），在各 return 点追加外部上报：

| 事件名 | 触发条件 | 属性 |
|---|---|---|
| `output_success` | 返回 `.completed` | `method: "auto_paste" / "clipboard"` |
| `output_clipboard_pending` | 返回 `.clipboardPending` | — |
| `output_failed` | 返回 `.failed` | `failure: failure.classification` |

---

### 3. 错误追踪

文件：`stet/Features/Dictation/DictationFailure.swift`

`DictationFailure.classification` 已分好类别，直接作为属性上报。重点关注：

| 分类 | 对应问题 |
|---|---|
| `.noSpeech` (emptyTranscription) | 误触发率 |
| `.permissions` (autoPastePermissionMissing) | 权限引导转化率 |
| `.network` | 网络稳定性 |
| `.providerAPI` (含 statusCode) | API 错误率 |
| `.configuration` | API Key 配置完成率 |

---

### 4. Onboarding 漏斗

文件：`stet/Features/Onboarding/Steps/` 各 step

每个步骤完成时埋 `onboarding_step_completed`：

| step 值 | 对应步骤 |
|---|---|
| `permissions` | 权限授予 |
| `shortcut` | 快捷键设置 |
| `model_download` | 本地模型下载 |
| `first_success` | 首次转录成功 |
| `done` | Onboarding 完成 |

漏斗分析可直接定位哪一步流失最多。

---

### 5. 设置变更

文件：`stet/Features/MacShell/GeneralSetting/MacGeneralSettingsViewModel.swift`  
文件：`stet/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift`

| 事件名 | 属性 |
|---|---|
| `provider_changed` | `transcription_provider`, `rewrite_provider` |
| `rewrite_toggled` | `enabled: true / false` |
| `hotkey_changed` | — |

---

## 优先级

| 优先级 | 事件 | 原因 |
|---|---|---|
| P0 | `dictation_completed` | 核心留存指标，word_count + 时长直接反映使用深度 |
| P0 | `output_failed` | 发现影响体验的系统性问题 |
| P1 | `dictation_started` / `dictation_cancelled` | 计算取消率 |
| P1 | `onboarding_step_completed` | 新用户漏斗 |
| P2 | `provider_changed` / `rewrite_toggled` | 功能使用分布 |
