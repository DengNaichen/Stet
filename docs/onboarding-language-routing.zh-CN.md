# Onboarding 语言选择与模型路由设计

## 背景

Stet 内置两个本地转录引擎：

| 引擎 | 标识 | 特点 |
| --- | --- | --- |
| NVIDIA Parakeet TDT V3 | `fluidAudio` | 高性能，单语言，不支持 code-switching |
| Local Whisper | `localWhisper` | 覆盖语言广，支持多语言混合（code-switching） |

两个引擎的能力差异对用户不可见。Onboarding 通过语言选择隐式完成路由，用户始终只看到"语言"而非"模型"。

---

## Onboarding 第一步：语言选择

### 页面设计

**标题：** `How will you be speaking?`

**副标题：** `Select the language(s) you'll use.`

**交互：**

```
Primary language    [下拉 / 搜索]   ← 必填，预选系统语言
Secondary language  [下拉 / 搜索]   ← 可选，点击 "+ Add a language" 展开

[Continue]  →  [⏳ Getting ready...]  →  自动跳转下一步
```

- 预选值来自 `Locale.current.language.languageCode`
- Secondary 字段默认折叠，点击后展开
- 界面不出现任何模型名称，不出现"本地"/"云端"等技术描述
- **点击 Continue 后锁定语言选择**，开始下载对应引擎的模型
- 下载期间 Continue 变为 spinner 状态（文案如 `"Getting ready..."`），语言选择器禁用
- 下载完成后立即触发预热（detached task，不阻塞跳转），然后自动进入下一步：
  - Whisper 路径：`LocalWhisperWarmupCoordinator.shared.warmup()`（现有逻辑，保持）
  - Parakeet 路径：`LocalParakeetContextManager.shared.loadModel(...)`（**目前缺失，需补上**）
- 下载失败时 spinner 变回 Continue（文案改为 `"Try again"`），语言选择器重新可用

---

## 路由规则

```
┌─ 有 secondary 语言？
│   └── 是 → Whisper（混合语言，Parakeet 不支持 code-switching）
│
└─ 没有 secondary
    └─ primary 在 Parakeet 支持列表？
        ├── 是 → Parakeet
        └── 否 → Whisper
```

**等价逻辑（代码视角）：**

```swift
func resolveEngine(primary: LanguageCode, secondary: LanguageCode?) -> TranscriptionEngine {
    guard secondary == nil, parakeetSupportedLanguages.contains(primary) else {
        return .localWhisper(languageHint: nil)
    }
    return .fluidAudio
}
```

---

## Language Code 传递策略

### Parakeet 路径

不传 language code。`AsrManager.transcribe()` API 无此参数，模型自动检测。

### Whisper 路径

| 触发原因 | 传给 Whisper 的 `languageCode` | 理由 |
| --- | --- | --- |
| 有 secondary（混合语言） | `nil` | 语言不固定，让 Whisper 自动检测 |
| primary 不在 Parakeet 列表（单语言） | primary 的 BCP-47 code | 跳过语言检测，提升准确率和速度 |

实现位置：`DictationPipelineFactory` 或 `ConfigurableSpeechService` 在构建 pipeline 时，将 onboarding 存下来的 `(primary, secondary)` 转换为引擎选择 + language hint。

---

## Parakeet 支持的语言列表

> 需要根据 Parakeet TDT V3 实际词表维护，以下为参考起点。

```swift
static let parakeetSupportedLanguages: Set<LanguageCode> = [
    "en", "es", "fr", "de", "it", "pt",
    "zh", "ja", "ko",
    "hi", "ar", "ru",
    "nl", "pl", "sv", "da", "no", "fi",
    "cs", "ro", "hu", "tr",
]
```

不在此列表内的语言（如越南语、泰语等）统一走 Whisper。

---

## Rewrite 引擎：自动配置，不进入 Onboarding

Rewrite（转录后清理）不作为独立 onboarding 步骤。

- **Apple Intelligence**：在 Permissions 步骤中引导开启（见下节），开启后自动作为默认 rewrite 引擎
- **API Key**：进阶配置，放在 Settings → Rewrite，不进入 onboarding
- **不用**：无 Apple Intelligence 时的自然默认状态

### Apple Intelligence 在 Permissions 步骤中的处理

Permissions 步骤新增第三行，规则如下：

| 设备状态 | 显示 |
| --- | --- |
| 不支持（非 Apple Silicon / macOS < 15.1） | 整行隐藏 |
| 支持但未开启 | 显示引导行 + "Open Settings" 按钮 |
| 已开启 | 显示 ✅ 状态，无需操作 |

**与其他权限的关键区别：Apple Intelligence 是可选项，不拦住 Continue 按钮。**

```text
[Microphone]                ← 必须，拦住 Continue
[Accessibility]             ← 必须，拦住 Continue
[Apple Intelligence]        ← 可选，不拦住 Continue（设备不支持时隐藏）
```

"Open Settings" 按钮深链到 System Settings → Apple Intelligence。用户返回 app 后自动刷新状态。

### Onboarding 完成时的 Rewrite 自动配置

```swift
if AppleIntelligenceRewriteService.isAvailable {
    settingsStore.saveRewriteProvider(.appleIntelligence)
    settingsStore.setRewriteEnabled(true)
} else {
    settingsStore.setRewriteEnabled(false)
}
```

用户之后可在 **Settings → Rewrite** 中切换到 OpenAI / Groq 并填写 API Key。

---

## Onboarding 步骤枚举（更新后）

原 7 步精简为 6 步（language 合并 download，去掉独立 rewrite 步骤）。

```swift
enum MacOnboardingStep: Int, CaseIterable {
    case language    // 语言选择 + 自动下载
    case permissions
    case shortcut
    case firstSuccess
    case appearance
    case done
}

enum MacOnboardingMode: String {
    case fluidAudio    // Parakeet 路径
    case localWhisper  // Whisper 路径
}
```

---

## 后续步骤（无需改动）

`.shortcut`、`.firstSuccess`、`.appearance`、`.done` 的实现保持现状，不受本次改动影响。

---

## 存储

Onboarding 完成后持久化到 `UserDefaults`：

| Key | 类型 | 内容 |
| --- | --- | --- |
| `transcriptionPrimaryLanguage` | `String` | BCP-47 code，如 `"zh"` |
| `transcriptionSecondaryLanguage` | `String?` | BCP-47 code 或 `nil` |
| `transcriptionEngine` | `String` | `"fluidAudio"` / `"localWhisper"` |

Settings 里"语言"设置项修改后，重新执行路由逻辑并更新 `transcriptionEngine`。如果新引擎的模型尚未下载，在 Settings 内静默触发下载，完成前继续用当前引擎。

---

## Analytics

语言选择步骤的埋点（参考 `analytics.zh-CN.md`）：

```swift
AnalyticsService.track("onboarding_step_completed", parameters: [
    "step": "language",
    "engine_selected": "fluidAudio" | "localWhisper",
    "has_secondary": "true" | "false",
])
```

不上报具体语言名称（隐私）。
