# 音频输入链路调研报告

## 概述

本文档记录了 Stet 项目音频输入链路的完整架构调研结果。该链路负责从用户麦克风采集音频，经过处理后发送到转录服务。

## 整体架构

```
用户启动录音
    ↓
ConfigurableSpeechService.startRecording()
    ↓
MacAudioCaptureService.startRecording()
    ↓
MacAudioFileRecorder.startRecording()
    ├─ AudioInputDeviceManager.defaultInputDevice() [获取麦克风]
    ├─ AVAudioEngine 设置输入 tap
    └─ 音频缓冲区写入 AVAudioFile (16kHz mono PCM WAV)
    ↓
用户停止录音
    ↓
DefaultAudioPostProcessor.processAudioFile()
    ├─ 加载音频样本
    └─ AudioSignalAnalyzer.analyze() [语音检测]
    ↓
如果检测到语音:
    ├─ DictationPipelineFactory.makePipeline() [构建转录管道]
    ├─ OpenAITranscriptionService.transcribe() 或 RelayDictationTranscriptionService
    └─ 返回转录文本
    ↓
MacDictationCaptureCoordinator.handleCompletedCapture()
    ├─ 复制到剪贴板
    └─ 自动粘贴到目标应用
```

## 核心组件

### 1. 设备层 (Stet/Core/Audio/)

| 文件 | 职责 |
|------|------|
| `AudioInputDeviceManager.swift` | 通过 CoreAudio 查询默认输入设备，获取设备 UID、名称、传输类型 |

### 2. 捕获层 (Stet/Core/Speech/)

| 文件 | 职责 |
|------|------|
| `AudioCaptureService.swift` | 捕获服务协议，定义 startRecording/stopRecording 等接口 |
| `MacAudioCaptureService.swift` | macOS 捕获服务实现，使用 AVAudioEngine |

### 3. 录制引擎 (Stet/Core/Audio/)

| 文件 | 职责 |
|------|------|
| `MacAudioFileRecorder.swift` | 核心录制引擎，安装 tap 捕获音频缓冲区 |
| `LinearPCMConversion.swift` | 音频格式转换（采样率、声道转换） |

### 4. 后处理层 (Stet/Core/Audio/)

| 文件 | 职责 |
|------|------|
| `DefaultAudioPostProcessor.swift` | 音频后处理，调用语音检测 |
| `AudioSignalAnalyzer.swift` | 使用 FluidAudio VadManager 进行语音活动检测 |
| `AudioLevelBridge.swift` | 管理实时音频电平流 |
| `AudioLevelNormalizer.swift` | 将原始音频样本归一化到 0-1 范围 |

### 5. 转录层 (Stet/Core/Transcribed/)

| 文件 | 职责 |
|------|------|
| `AudioFileTranscriptionService.swift` | 转录服务协议 |
| `OpenAITranscriptionService.swift` | 直接调用 OpenAI API 转录 |
| `RelayDictationTranscriptionService.swift` | 通过 Relay 服务转录 |

### 6. 编排层 (Stet/Core/Speech/)

| 文件 | 职责 |
|------|------|
| `SpeechService.swift` | 高级语音服务协议 |
| `ConfigurableSpeechService.swift` | 管道编排器，协调整个流程 |
| `DictationPipelineFactory.swift` | 根据设置构建转录管道 |

### 7. 工作流层 (Stet/App/Workflows/)

| 文件 | 职责 |
|------|------|
| `MacDictationCaptureCoordinator.swift` | 录音完成后的处理（剪贴板、自动粘贴） |

## 音频格式规范

| 平台 | 采样率 | 声道 | 位深 | 格式 |
|------|--------|------|------|------|
| macOS | 16kHz | Mono | 16-bit | WAV |
| iOS | 44.1kHz | Mono | AAC | M4A |

## 关键协议

```swift
protocol AudioCaptureService: Sendable {
    func startRecording() async throws
    func activateRecordingWindow() async throws
    func stopRecording() async throws -> (url: URL, duration: TimeInterval?)
    func cancelRecording() async
    func prewarm() async
}

protocol AudioFileTranscriptionService: Sendable {
    func transcribe(
        audioFileAt fileURL: URL,
        languageCode: String?,
        prompt: String?,
        audioDurationSeconds: TimeInterval?
    ) async throws -> String
}

protocol AudioPostProcessing: Sendable {
    func processAudioFile(at sourceURL: URL, duration: TimeInterval?) async throws -> AudioPostProcessingResult
}
```

## 语音检测配置

- 语音概率阈值: 0.8
- 最小语音片段时长: 0.4 秒
- 过滤短暂噪音（咳嗽、点击声）

## 待完善事项

1. 缺少现有 spec 文档
2. 某些错误处理路径需要明确
3. 设备切换时的行为需要定义
4. 性能监控指标可以进一步文档化

## 详细组件分析

### AudioInputDeviceManager

负责与 macOS CoreAudio 交互，获取系统默认音频输入设备。

**核心功能:**
- `defaultInputDeviceID()` - 获取默认输入设备 ID
- `defaultOutputDeviceID()` - 获取默认输出设备 ID
- `hardwareDevice(deviceID:)` - 获取设备详细信息（UID、名称、传输类型）

**传输类型:**
- `kAudioDeviceTransportTypeBuiltIn` - 内置麦克风
- `kAudioDeviceTransportTypeUSB` - USB 麦克风
- `kAudioDeviceTransportTypeBluetooth` - 蓝牙麦克风

### MacAudioFileRecorder

核心录制引擎，使用 AVAudioEngine。

**关键特性:**
- 在输入节点安装 tap 捕获音频缓冲区
- 使用 LinearPCMConversion 进行格式转换
- 支持语音处理（Voice Processing）模式
- 写入 AVAudioFile（16kHz mono PCM WAV）

**语音处理配置:**
- 蓝牙设备：启用语音处理
- 内置麦克风：禁用语音处理（避免延迟）

### AudioSignalAnalyzer

使用 FluidAudio 库的 VadManager 进行语音活动检测（VAD）。

**分析结果:**
- `shouldDiscardAsNoSpeech` - 是否应丢弃（无语音）
- `speechFrameRatio` - 语音帧占比
- `longestSpeechDurationSeconds` - 最长语音片段时长
- `totalSpeechDurationSeconds` - 总语音时长
- `noiseFloorDBFS` - 噪音基准
- `speechLevelP75DBFS` - 语音电平 P75

### 转录服务

**OpenAITranscriptionService:**
- 直接调用 OpenAI Whisper API
- 支持重试（最多 3 次）
- 超时时间根据音频时长计算
- 支持语言代码和提示词

**RelayDictationTranscriptionService:**
- 通过 Relay 服务转发
- 支持文本重写（rewrite）
- 支持首选拼写（preferredSpellings）
- 需要音频时长用于计费

## 错误处理

主要错误类型定义在 `SpeechServiceError`:
- `alreadyRecording` - 已在录音中
- `notRecording` - 未在录音
- `microphonePermissionDenied` - 麦克风权限被拒绝
- `failedToStart` - 启动失败

## 性能监控

项目包含多个探针用于性能追踪:
- `DictationStartupProbe` - 启动阶段探针
- `DictationRuntimeProbe` - 运行时探针
- `DictationLatencyProbe` - 延迟探针

## 后续工作

基于此调研，可以创建以下 spec:
1. 音频输入设备管理 spec（设备切换、枚举）
2. 音频录制管道 spec（格式、转换、缓冲）
3. 语音检测 spec（VAD 配置、阈值）
4. 转录服务 spec（API 集成、错误处理）

## 执行路由 (DictationExecutionRoute)

系统支持三种转录执行模式：

### 模式分类

| 模式 | 说明 | 路由目标 |
|------|------|----------|
| `.automatic` | 自动选择，有 Relay 认证用 Relay，否则用 Direct | Relay 或 Direct |
| `.managed` | 强制使用 Relay 服务 | Relay |
| `.byok` | Bring Your Own Key，直接使用 OpenAI API | Direct |

### 路由决策逻辑

```
DictationExecutionRouteResolver.resolve()
    ↓
检查执行模式
    ├─ .automatic: 优先 Relay，有认证就用
    ├─ .managed: 必须 Relay
    └─ .byok: 必须 Direct
    ↓
检查必要条件
    ├─ 需要认证但无认证 → 错误
    └─ 需要 API Key 但无配置 → 错误
```

### RelayAuthenticationContext

```swift
struct RelayAuthenticationContext: Sendable, Equatable {
    let functionsBaseURL: URL      // Functions 基础 URL
    let publishableKey: String     // 发布密钥
    let accessToken: String        // 访问令牌
}
```

## 文本重写服务 (TextRewriteService)

在转录完成后，可以选择性地对文本进行清理或重写。

### 请求类型

1. **cleanup** - 清理原始转录
   - 添加标点和大小写
   - 修正明显的语音转文字错误
   - 移除填充词（um, uh）
   - 保留有意义的重复和自我纠正

2. **rewriteSelection** - 重写选中文本
   - 根据用户语音指令重写选中文本

### 系统提示词 (cleanup 模式)

```
You are a conservative transcript editor.

Your job is to clean raw speech-to-text transcripts with minimal edits.

Rules:
1. You must add punctuation and capitalization throughout the transcript.
2. You must correct obvious speech-to-text errors when the intended meaning is clear from context.
3. Remove filler words like "um" and "uh" and obvious transcription noise.
4. Do not rewrite, summarize, paraphrase, or translate.
5. Keep meaningful repetition, hesitation, and self-correction.
6. If a correction is uncertain, keep the original wording.

Output only the cleaned transcript.
```

## 错误类型

### SpeechServiceError

| 错误 | 描述 |
|------|------|
| `alreadyRecording` | 录音会话已在进行中 |
| `notRecording` | 没有活动的录音会话 |
| `microphonePermissionDenied` | 麦克风权限被拒绝 |
| `unsupportedLocale` | 当前语言不支持设备端转录 |
| `unsupportedAudioFormat` | 设备无法提供兼容的音频格式 |
| `failedToStart` | 转录引擎无法启动 |
| `emptyTranscription` | 未捕获到语音 |

### AIExecutionError

| 错误 | 描述 |
|------|------|
| `managedRequiresAuthenticatedSession` | Managed Relay 需要已登录的 Stet 账户 |
| `relayInvocationFailed` | Relay 服务调用失败 |

### OpenAIError

与 OpenAI API 相关的错误（见 `Stet/Core/OpenAI/OpenAIError.swift`）

## 协议层次

```
┌─────────────────────────────────────────┐
│         SpeechService                   │  高级协议
│  (startRecording, stopRecording, etc.)  │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│    ConfigurableSpeechService            │  编排层
│  (管理 pipeline, 音频电平, 录音状态)     │
└────────────────┬────────────────────────┘
                 │
    ┌────────────┴────────────┐
    ▼                         ▼
┌──────────────┐    ┌──────────────────────┐
│AudioCapture  │    │  DictationPipeline   │
│  Service     │    │  (transcription +    │
│ (录音)       │    │   rewrite services)  │
└──────────────┘    └──────────────────────┘
```

## 音频电平流

```swift
protocol AudioLevelSource: Sendable {
    func makeAudioLevelStream() async -> AsyncStream<Double>
}
```

- `AudioLevelBridge` 管理多个并发电平流
- `AudioLevelNormalizer` 将 RMS 值归一化到 0-1 范围
- 最小可见电平: 0.08（避免 UI 闪烁）

## 性能探针

项目使用多个探针追踪性能：

| 探针 | 用途 |
|------|------|
| `DictationStartupProbe` | 启动阶段（pipeline 就绪、权限等） |
| `DictationRuntimeProbe` | 运行时事件 |
| `DictationLatencyProbe` | 延迟追踪（上传开始等） |

## 设置模型 (DictationSettingsStore)

### DictationSettingsSnapshot

```swift
struct DictationSettingsSnapshot: Sendable {
    let provider: DictationProvider              // 转录服务提供商
    let executionMode: AIExecutionMode           // 执行模式
    let isRewriteEnabled: Bool                   // 是否启用文本重写
    let dictationLanguageMode: DictationLanguageMode  // 语言模式
    let shouldPauseMediaDuringDictation: Bool    // 录音时暂停媒体
    let providerConfiguration: OpenAIConfiguration?  // API 配置
    let translationTargetLanguage: TranslationTargetLanguage  // 翻译目标语言
    let translateSelectedTextOnTranslationHotkey: Bool  // 翻译热键是否翻译选中文本
    let personalDictionary: [String]             // 个人词典
    let interactionSoundsEnabled: Bool           // 交互音效
    let interactionSoundPreset: InteractionSoundPreset  // 音效预设
}
```

### 提供商 (DictationProvider)

| 值 | 显示名称 | 描述 |
|---|---------|------|
| `openAI` | OpenAI | Audio capture + OpenAI transcription |
| `groq` | Groq | Audio capture + Groq transcription |

### 执行模式 (AIExecutionMode)

| 值 | 标题 | 副标题 | 条件 |
|---|------|--------|------|
| `automatic` | Automatic | Managed Relay | 优先 Relay，否则 Direct |
| `managed` | Managed Relay | authenticated relay | 必须已认证 |
| `byok` | BYOK | local provider API key | 必须有本地 API Key |

### 语言模式 (DictationLanguageMode)

| 值 | 标题 | 转录语言代码 | 重写上下文 |
|---|------|-------------|-----------|
| `automatic` | Automatic | nil | 保持原语言 |
| `mixedChineseEnglish` | Mixed Chinese + English | nil | 保留中英混合 |
| `primarilyChinese` | Primary Chinese | "zh" | 偏向中文 |
| `primarilyEnglish` | Primary English | "en" | 偏向英文 |

### 存储机制

- **普通设置**: UserDefaults (`MacPreferences` 定义键名)
- **敏感数据**: Keychain (`DictationSecretStore` 协议)
- **个人词典**: SQLite via `DictionaryModel`

### 偏好设置键名 (MacPreferences)

```swift
static let pauseMediaDuringDictation = "mac.pauseMediaDuringDictation"
static let transcriptionProvider = "mac.transcriptionProvider"
static let aiExecutionMode = "mac.aiExecutionMode"
static let rewriteEnabled = "mac.rewriteEnabled"
static let dictationLanguageMode = "mac.dictationLanguageMode"
static let translationTargetLanguage = "mac.translationTargetLanguage"
static let translateSelectedTextOnTranslationHotkey = "mac.translateSelectedTextOnTranslationHotkey"
static let interactionSoundsEnabled = "mac.interactionSoundsEnabled"
static let interactionSoundPreset = "mac.interactionSoundPreset"
```
## 音频辅助功能

### 交互音效 (InteractionSoundPlayer)

在录音开始和结束时播放音效，提供用户反馈。

**音效预设 (InteractionSoundPreset)**

| 值 | 标题 | 开始提示音 | 结束音效 |
|---|------|-----------|---------|
| `soft` | Soft | DictationStartSoft.wav | Morse |
| `glass` | Glass | DictationStartGlass.wav | Hero |

**接口**

```swift
@MainActor
protocol InteractionSoundPlaying: AnyObject {
    func playStartPrompt(preset: InteractionSoundPreset) async
    func playFinish(preset: InteractionSoundPreset)
    func playPreview(preset: InteractionSoundPreset)
}
```

### 系统音频静音 (SystemAudioMuteController)

在录音期间自动静音系统音频输出，避免回声和干扰。

**工作原理:**
1. 创建进程音频 tap（`AudioHardwareCreateProcessTap`）
2. 创建聚合设备，将 tap 添加为子设备
3. 设置静音行为
4. 录音结束后恢复

**特性:**
- 仅静音 Stet 应用自身的音频输出
- 使用 `CATapDescription` 配置
- 支持进程恢复（`isProcessRestoreEnabled`）

---

## 调研总结

### 完整链路

```
用户启动录音
    ↓
[设置层] DictationSettingsStore.loadSnapshot()
    ├─ provider: DictationProvider
    ├─ executionMode: AIExecutionMode
    ├─ dictationLanguageMode: DictationLanguageMode
    └─ personalDictionary: [String]
    ↓
[设备层] AudioInputDeviceManager.defaultInputDevice()
    └─ 获取麦克风设备信息
    ↓
[捕获层] MacAudioCaptureService.startRecording()
    ├─ 请求麦克风权限
    ├─ 配置音频会话
    └─ 启动 MacAudioFileRecorder
    ↓
[录制引擎] MacAudioFileRecorder
    ├─ AVAudioEngine 安装输入 tap
    ├─ LinearPCMConversion 格式转换
    └─ 写入 16kHz mono PCM WAV
    ↓
[电平监控] AudioLevelBridge + AudioLevelNormalizer
    └─ 实时音频电平流 → UI 显示
    ↓
用户停止录音
    ↓
[后处理] DefaultAudioPostProcessor
    ├─ FluidAudio 加载音频
    └─ AudioSignalAnalyzer 语音检测
    ↓
如果检测到语音:
    ↓
[管道工厂] DictationPipelineFactory.makePipeline()
    ├─ DictationExecutionRouteResolver.resolve()
    │   ├─ .automatic → 优先 Relay
    │   ├─ .managed → 必须 Relay
    │   └─ .byok → 必须 Direct
    └─ 构建 DictationPipeline
    ↓
[转录服务]
    ├─ OpenAITranscriptionService (Direct)
    │   └─ OpenAI Whisper API
    └─ RelayDictationTranscriptionService (Relay)
        └─ Relay 服务 → OpenAI/Groq
    ↓
[可选] TextRewriteService.rewrite()
    └─ 清理/重写转录文本
    ↓
[工作流] MacDictationCaptureCoordinator
    ├─ 复制到剪贴板
    └─ 自动粘贴到目标应用
```

### 关键设计决策

1. **音频格式**: 16kHz mono 16-bit PCM (WAV) - 平衡质量和大小
2. **语音检测**: 使用 FluidAudio VadManager，阈值 0.8，最小片段 0.4s
3. **执行路由**: 支持三种模式（automatic/managed/byok），灵活适应不同场景
4. **语言处理**: 四种语言模式，支持中英混合输入
5. **系统集成**: 录音时自动静音系统输出，避免回声

### 潜在改进点

1. **设备管理**: 目前仅支持默认设备，可考虑设备切换功能
2. **实时处理**: 考虑流式转录支持
3. **错误恢复**: 增强网络错误重试逻辑
4. **监控指标**: 可增加更多性能指标
## UI 层 (DictationViewModel)

### 状态机 (DictationState)

```
┌────────┐     start      ┌─────────┐    activate   ┌──────────┐
│ idle   │ ──────────────▶│ starting│ ────────────▶│ listening│
└────────┘                └─────────┘               └──────────┘
    ▲                          │                          │
    │                          │ stop                     │ stop
    │                          ▼                          ▼
    │                   ┌───────────┐              ┌───────────┐
    │◀──────────────────│ processing│◀─────────────│ processing│
    │                   └───────────┘              └───────────┘
    │                          │                          │
    │                          ▼                          ▼
    │                   ┌────────────┐            ┌────────────┐
    └───────────────────│   result   │            │   error    │
                        └────────────┘            └────────────┘
```

| 状态 | 描述 |
|------|------|
| `idle` | 空闲，准备就绪 |
| `starting` | 正在启动麦克风 |
| `listening` | 正在监听 |
| `processing` | 处理中 |
| `result(String)` | 转录完成 |
| `clipboardPending(String)` | 等待复制到剪贴板 |
| `error(DictationFailure)` | 错误 |

### 操作 (DictationAction)

```swift
enum DictationAction: Equatable {
    case startTapped      // 用户点击开始
    case stopTapped       // 用户点击停止
    case resetTapped      // 用户点击重置
    case transcriptionSucceeded(String)  // 转录成功
    case clipboardPending(String)        // 等待剪贴板
    case transcriptionFailed(DictationFailure)  // 转录失败
}
```

### 错误分类 (DictationFailure.Classification)

| 分类 | 说明 |
|------|------|
| `permissions` | 权限问题（麦克风） |
| `configuration` | 配置问题（API Key、Base URL） |
| `authentication` | 认证问题（Relay 登录） |
| `network` | 网络问题 |
| `noSpeech` | 未检测到语音 |
| `service` | 服务端问题 |
| `state` | 状态不一致 |
| `unknown` | 未知错误 |

### 错误映射

| SpeechServiceError | DictationFailure |
|--------------------|------------------|
| `microphonePermissionDenied` | `.microphonePermissionDenied` |
| `unsupportedLocale` | `.unsupportedLocale` |
| `unsupportedAudioFormat` | `.unsupportedAudioFormat` |
| `failedToStart` | `.failedToStart` |
| `emptyTranscription` | `.emptyTranscription` |
| `alreadyRecording` | `.alreadyRecording` |
| `notRecording` | `.notRecording` |

### 性能探针

DictationViewModel 在关键节点记录探针:

- `DictationRuntimeProbe.markCaptureStartRequested()` - 开始录音请求
- `DictationRuntimeProbe.markCaptureStartError()` - 开始录音错误
- `DictationRuntimeProbe.markAction("enteredListening")` - 进入监听状态
- `DictationRuntimeProbe.markCaptureStopRequested()` - 停止录音请求
- `DictationRuntimeProbe.markAudioStopRequested()` - 音频停止请求
- `DictationStartupProbe.record()` - 启动阶段事件
## UI 层 (DictationView)

### 界面组件

**主按钮状态**

| 状态 | 按钮文字 | 按钮颜色 |
|------|---------|---------|
| `idle` | Start | 蓝色 |
| `starting` | Cancel | 橙色 |
| `listening` | Stop | 红色 |
| `processing` | Wait | 橙色 |
| `result` | Again | 绿色 |
| `clipboardPending` | Dismiss | 薄荷绿 |
| `error` | Again | 灰色 |

**消息区域内容**

| 状态 | 显示内容 |
|------|---------|
| `idle` | "Tap Start to begin dictation." |
| `starting` | ProgressView "Starting microphone..." |
| `listening` | "Speak naturally, then tap Stop when you are ready to finalize the transcript." |
| `processing` | ProgressView "Finalizing transcription..." |
| `result(String)` | 转录文本 |
| `clipboardPending(String)` | 转录文本 |
| `error(DictationFailure)` | 错误消息（红色） |

### 完整架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           DictationView (UI)                            │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  State: idle → starting → listening → processing → result      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      DictationViewModel                                 │
│  - 状态管理 (DictationState)                                            │
│  - 操作处理 (DictationAction)                                           │
│  - 音频电平监控                                                         │
│  - 性能探针记录                                                         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        SpeechService                                    │
│  (ConfigurableSpeechService - 编排层)                                   │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
              ┌──────────────────┴──────────────────┐
              ▼                                     ▼
┌─────────────────────────┐           ┌─────────────────────────┐
│    AudioCaptureService  │           │   DictationPipeline     │
│  (MacAudioCaptureService)│           │  (transcription +       │
│   - 录音生命周期         │           │   rewrite services)     │
│   - 权限管理             │           └───────────┬─────────────┘
│   - 音频电平流           │                       │
└───────────┬─────────────┘                       ▼
            │                       ┌─────────────────────────┐
            │                       │ AudioFileTranscription  │
            ▼                       │ Service                 │
┌─────────────────────────┐         │ - OpenAI               │
│  MacAudioFileRecorder   │         │ - Relay                │
│  - AVAudioEngine        │         └─────────────────────────┘
│  - 格式转换              │
│  - 文件写入              │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  AudioPostProcessing    │
│  - 语音检测              │
│  - 静音过滤              │
└─────────────────────────┘
```

---

## 文档索引

本文档包含以下章节:

1. 概述
2. 整体架构
3. 核心组件 (设备层、捕获层、录制引擎、后处理层、转录层、编排层、工作流层)
4. 音频格式规范
5. 关键协议
6. 语音检测配置
7. 执行路由
8. 文本重写服务
9. 错误类型
10. 协议层次
11. 音频电平流
12. 性能探针
13. 设置模型
14. 音频辅助功能
15. 调研总结
16. UI 层
## 翻译服务 (TextTranslationService)

### 目标语言 (TranslationTargetLanguage)

| 值 | 显示名称 | 指令名称 |
|---|---------|---------|
| `english` | English | English |
| `chineseSimplified` | Chinese (Simplified) | Simplified Chinese |
| `japanese` | Japanese | Japanese |
| `korean` | Korean | Korean |
| `spanish` | Spanish | Spanish |
| `french` | French | French |
| `german` | German | German |

### 翻译请求 (TextTranslationRequest)

```swift
struct TextTranslationRequest: Sendable, Equatable {
    var sourceText: String
    var targetLanguage: TranslationTargetLanguage
    var systemPrompt: String?
    var additionalUserContext: String?
    var model: String?
}
```

**默认系统提示词:**
```
You translate text into {targetLanguage}. Return only the translated text.
```

### OpenAI 配置 (OpenAIConfiguration)

**提供商默认值**

| 提供商 | 转录模型 | 翻译模型 | 重写模型 | 支持 Responses Store |
|--------|---------|---------|---------|---------------------|
| OpenAI | gpt-4o-mini-transcribe | gpt-5-mini | gpt-5-mini | 是 |
| Groq | whisper-large-v3-turbo | llama-3.3-70b-versatile | openai/gpt-oss-120b | 否 |

**API 基础 URL**

| 提供商 | 基础 URL |
|--------|---------|
| OpenAI | https://api.openai.com/v1 |
| Groq | https://api.groq.com/openai/v1 |

### 翻译功能设置

- `translationTargetLanguage`: 翻译目标语言
- `translateSelectedTextOnTranslationHotkey`: 翻译热键是否翻译选中文本

---

## 完整功能矩阵

| 功能 | 状态 | 说明 |
|------|------|------|
| 音频输入捕获 | ✅ | 麦克风采集 |
| 音频格式转换 | ✅ | 16kHz mono PCM |
| 语音活动检测 | ✅ | FluidAudio VadManager |
| 静音过滤 | ✅ | 丢弃无语音片段 |
| OpenAI 转录 | ✅ | Direct API |
| Relay 转录 | ✅ | Managed Relay |
| 文本重写 | ✅ | cleanup 模式 |
| 文本翻译 | ✅ | 多语言支持 |
| 系统音频静音 | ✅ | 录音时静音 |
| 交互音效 | ✅ | 开始/结束音效 |
| 设备管理 | ⚠️ | 仅默认设备 |
| 设备切换 | ❌ | 未实现 |

## 剪贴板和文本注入服务

### ClipboardService

```swift
@MainActor
protocol ClipboardService {
    func copy(_ text: String)
}
```

**实现:** `SystemClipboardService`
- macOS: 使用 `NSPasteboard`
- iOS: 使用 `UIPasteboard.general`

### TextInjectionService

文本注入服务用于将转录结果自动粘贴到目标应用。

**访问状态**

```swift
@MainActor
struct TextInjectionAccessState: Equatable {
    let hasAccessibilityAccess: Bool    // 辅助功能权限
    let hasPostEventAccess: Bool        // Post Event 权限

    var canSimulateInput: Bool {
        hasAccessibilityAccess || hasPostEventAccess
    }
}
```

**核心方法**

| 方法 | 说明 |
|------|------|
| `requestAccess()` | 请求权限（手动触发） |
| `requestAccessIfNeeded()` | 自动请求缺失权限 |
| `openAccessibilitySettings()` | 打开系统辅助功能设置 |
| `pasteClipboard(into:)` | 模拟 Command+V 粘贴 |
| `selectedText()` | 获取选中文本 |
| `replaceSelectedText(into:keepResultInClipboard:)` | 替换选中文本 |

**权限要求**

1. **辅助功能权限** (`AXIsProcessTrusted`)
   - 读取焦点元素
   - 获取选中文本
   - 验证粘贴结果

2. **Post Event 权限** (`CGPreflightPostEventAccess`)
   - 模拟键盘事件
   - 执行 Command+C / Command+V

**粘贴验证逻辑**

1. 记录粘贴前焦点元素状态
2. 激活目标应用（如果是外部应用）
3. 模拟 Command+V
4. 记录粘贴后焦点元素状态
5. 比较状态变化，确认粘贴成功

### 剪贴板恢复 (PasteboardRestoreCoordinator)

在自动粘贴场景下，需要临时覆盖剪贴板，粘贴完成后需要恢复原内容。

```swift
// 流程
1. prepareForTemporaryOverride(on: pasteboard)  // 保存当前剪贴板
2. clipboardService.copy(text)                   // 复制新内容
3. pasteClipboard(into: application)             // 粘贴
4. scheduleRestoreIfNeeded(on: pasteboard)       // 延迟恢复
   或
4. restoreImmediatelyIfNeeded(on: pasteboard)   // 立即恢复
```

---

## 权限系统

### 麦克风权限

- 使用 `AVAudioApplication` 或 `AVAudioSession` 请求
- 状态: 已授权 / 被拒绝 / 未确定

### 辅助功能权限

- 使用 `AXIsProcessTrustedWithOptions` 请求
- 路径: System Preferences → Security & Privacy → Privacy → Accessibility

### Post Event 权限

- 使用 `CGRequestPostEventAccess` 请求
- 用于模拟键盘事件

---

## 完整数据流

```
用户点击开始
    │
    ▼
DictationViewModel.startCapture()
    │
    ├─▶ DictationRuntimeProbe.markCaptureStartRequested()
    │
    ▼
SpeechService.startRecording()
    │
    ├─▶ 请求麦克风权限
    │
    ├─▶ MacAudioFileRecorder.startRecording()
    │   │
    │   ├─▶ AudioInputDeviceManager.defaultInputDevice()
    │   │
    │   ├─▶ AVAudioEngine.installTap()
    │   │
    │   └─▶ 写入 16kHz mono PCM WAV
    │
    ├─▶ AudioLevelBridge.emit(level) → UI 显示
    │
    └─▶ DictationStartupProbe.record(.firstBufferWritten)

用户点击停止
    │
    ▼
SpeechService.stopRecording()
    │
    ├─▶ MacAudioFileRecorder.stopRecording()
    │
    ├─▶ DefaultAudioPostProcessor.processAudioFile()
    │   │
    │   └─▶ AudioSignalAnalyzer.analyze()
    │       │
    │       └─▶ VadManager.segmentSpeech()
    │
    ├─▶ 如果 shouldDiscardAsNoSpeech → 返回错误
    │
    └─▶ DictationPipelineFactory.makePipeline()
        │
        ├─▶ DictationExecutionRouteResolver.resolve()
        │   │
        │   └─▶ 决定使用 Direct 还是 Relay
        │
        └─▶ 构建 DictationPipeline
            │
            ▼
        AudioFileTranscriptionService.transcribe()
            │
            ├─▶ OpenAITranscriptionService
            │   └─▶ OpenAI Whisper API
            │
            └─▶ RelayDictationTranscriptionService
                └─▶ Relay 服务 → OpenAI/Groq
            │
            ▼
        如果启用重写:
            │
            ▼
        TextRewriteService.rewrite()
            │
            ▼
        DictationViewModel 接收结果
            │
            ▼
        MacDictationCaptureCoordinator.handleCompletedCapture()
            │
            ├─▶ 如果 shouldCopyToClipboard
            │   └─▶ ClipboardService.copy(text)
            │
            ├─▶ 如果 shouldAutoPaste
            │   └─▶ TextInjectionService.replaceSelectedText()
            │
            └─▶ 恢复剪贴板（如需要）
```