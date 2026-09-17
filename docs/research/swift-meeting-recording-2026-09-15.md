# Swift 开源会议录制方案调研

调查日期：2026-09-15。3 个 Terra 代理并行调查 Apple 采集 API、开源采集实现和完整会议应用；主代理核验 Stet 现状并补充转写组件。范围以 **macOS 15+、Swift、录制麦克风与会议系统音频**为主，兼顾未来录屏。依据为官方文档、仓库源码、许可证和模型卡；未安装候选应用、下载模型或进行录音实测。

本文保留实现前的调研快照；后续实现与验收结果见[会议录音验证记录](../meeting-recording-validation-2026-09-15.md)。

## 结论

对 Stet，优先复用现有麦克风采集与中文转写，新增 **Core Audio process tap 系统音频采集、两路分别保存、统一时间轴、分段恢复**。这是结合现有代码的工程判断，采集依据见下文 Apple 文档与 AudioCap 源码。若需要同时录制窗口或屏幕，再比较 ScreenCaptureKit 的音视频统一方案。

最需要避免的三个误判：

- **双路音频不等于多人分离。** 麦克风与系统输出只能确定音源；远端多人仍可能混在同一路，扬声器声音也可能再次进入麦克风。
- **有多语言 ASR 不代表支持中文。** Parakeet TDT v3 的官方语言列表是 25 种欧洲语言，不含中文。[模型卡](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- **Sortformer 的 4 个槽位不能覆盖任意规模会议。** 多于 4 位说话人的场景应另测离线聚类方案；不能因为流式模型能接受长音频就推断它能识别更多人。[FluidAudio Sortformer 文档](https://docs.fluidinference.com/diarization/sortformer)

## 1. 采集底座：最值得阅读的实现

| 项目 | 已核验能力 | 主要边界 | 对 Stet 的价值 |
|---|---|---|---|
| [insidegui/AudioCap](https://github.com/insidegui/AudioCap/tree/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3) | SwiftUI 示例；按音频进程创建 tap，经私有 aggregate device 录制；不需要虚拟驱动 | 项目最低 macOS 14.4；没有麦克风双路、完整设备切换恢复；权限辅助代码含可选私有 TCC API | **纯音频首读**：process → tap → aggregate → I/O callback 的小型参考；产品使用公开授权流程 |
| [jftuga/mac-audio-recorder](https://github.com/jftuga/mac-audio-recorder/tree/06c38d0c3d5279fad2c86202521d4ae60a74480a) | Swift；macOS 15+；一个 SCStream 分别输出 system/mic；应用过滤、麦克风选择、首个 PTS 对齐 | 项目较小；首点对齐不能证明长会议无漂移；中断自动恢复未实现；bleed reduction 是 ducking，不是声学回声消除 | **双轨结构首读**：录音会话、轨道时间信息和后处理 |
| [makeusabrew/audiotee](https://github.com/makeusabrew/audiotee/tree/56ac954369a09318e46b88a6eec33c2d2b0d32a3) | Swift CLI/Core Audio tap；系统音频、PID 包含/排除、重采样 | 公开版仅默认输出设备，未含麦克风双路；README 声明 MIT，但核验版本没有独立 LICENSE 文件 | 适合参考 CLI 与 PCM 输出接口；复制代码前核实许可文件 |
| [ExistentialAudio/BlackHole](https://github.com/ExistentialAudio/BlackHole/tree/ffcb74433fbcf8c8ca5c736677c1a4864384dc09) | macOS 虚拟回环驱动；把输出路由为录音输入 | 非 Swift 会议组件；需要安装驱动和设置音频路由；本身不提供按进程录制、ASR 或 AEC | Stet 已要求 macOS 15，默认路线没有必要增加这层部署成本 |

对应源码与许可：

- AudioCap：[ProcessTap.swift](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/AudioCap/ProcessTap/ProcessTap.swift)、[BSD-2-Clause LICENSE](https://github.com/insidegui/AudioCap/blob/6f609e8ad1b1e11fa0e8edbe91864cb099f00de3/LICENSE)。aggregate 的 drift compensation 只覆盖其内部组成，不能据此保证另一条独立麦克风链路同步。
- mac-audio-recorder：[RecordingSession.swift](https://github.com/jftuga/mac-audio-recorder/blob/06c38d0c3d5279fad2c86202521d4ae60a74480a/Sources/audiorec/Capture/RecordingSession.swift)、[ContentFilterFactory.swift](https://github.com/jftuga/mac-audio-recorder/blob/06c38d0c3d5279fad2c86202521d4ae60a74480a/Sources/audiorec/Capture/ContentFilterFactory.swift)、[README](https://github.com/jftuga/mac-audio-recorder/blob/06c38d0c3d5279fad2c86202521d4ae60a74480a/README.md)、[MIT LICENSE](https://github.com/jftuga/mac-audio-recorder/blob/06c38d0c3d5279fad2c86202521d4ae60a74480a/LICENSE)。
- AudioTee：[AudioTapManager.swift](https://github.com/makeusabrew/audiotee/blob/56ac954369a09318e46b88a6eec33c2d2b0d32a3/Sources/AudioTeeCore/Core/AudioTapManager.swift)、[README](https://github.com/makeusabrew/audiotee/blob/56ac954369a09318e46b88a6eec33c2d2b0d32a3/README.md)。
- BlackHole：[路由与开发者说明](https://github.com/ExistentialAudio/BlackHole/blob/ffcb74433fbcf8c8ca5c736677c1a4864384dc09/README.md)、[GPL-3.0 LICENSE](https://github.com/ExistentialAudio/BlackHole/blob/ffcb74433fbcf8c8ca5c736677c1a4864384dc09/LICENSE)。项目另提供商业许可渠道；用户安装驱动与把驱动打包进产品应分别评估。

### 两条 Apple API 路线

| 路线 | API 与版本 | 如何取得两路音频 | 选择依据 |
|---|---|---|---|
| Core Audio process tap | `CATapDescription`、`AudioHardwareCreateProcessTap`；安装 SDK 标注 tap 创建 API 为 macOS 14.2+，AudioCap 项目设为 14.4 | tap 捕获系统/选定进程输出，现有 AVFoundation 链路继续采麦克风 | 纯音频；最容易接到 Stet 当前结构 |
| ScreenCaptureKit | 系统音频 `capturesAudio` 为 macOS 13+；`captureMicrophone`、`.microphone` 为 macOS 15+ | 同一 SCStream 注册 `.audio` 与 `.microphone`，仍是不同格式的独立输出 | 同时需要屏幕/窗口视频，或决定统一采集后端 |

来源：[Apple Core Audio taps 示例](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)、[CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription)、[Apple ScreenCaptureKit 示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)、[SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)、[SCStreamOutputType](https://developer.apple.com/documentation/screencapturekit/scstreamoutputtype)。Stet 的 app 下限已是 15，14.2 与 14.4 的差异不影响当前选择。

ScreenCaptureKit 可通过 content filter 选择应用；`excludesCurrentProcessAudio` 专门排除当前进程，不能把它当作任意 PID 过滤开关。其麦克风输出采用设备原生格式，系统音频可配置采样率/声道；不能假设两路 buffer 长度、格式或回调时间相同。[Apple 示例](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)、[microphoneCaptureDeviceID](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/microphonecapturedeviceid)

授权也应按来源处理：tap 需要系统音频录制授权及 `NSAudioCaptureUsageDescription`；麦克风需要麦克风授权及 `NSMicrophoneUsageDescription`；ScreenCaptureKit 遵循对应屏幕捕获授权流程。AudioCap 的私有 TCC 辅助路径不应作为产品依赖。[Apple 媒体授权文档](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)、[tap 示例](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)

## 2. 完整会议应用

优先阅读 **Meeting Transcriber → Muesli → OpenOats**。排序依据是与 Stet 的输入、会话及转写链路相近程度，属于源码适配判断，不是实测质量排名。

| 项目 | 技术栈与会议能力 | 最值得借鉴 | 限制 |
|---|---|---|---|
| [pasrom/meeting-transcriber](https://github.com/pasrom/meeting-transcriber/tree/f17ae33f0d1c1a1b5c871de7f5fd0d8c86f4033a) | Swift/SwiftUI；macOS 14.2+；Core Audio tap + mic 双轨；WhisperKit/Parakeet 本地转写；FluidAudio 说话人分离、声纹匹配 | **最贴近 Stet**：双源 recorder、录后队列、每轨处理及 speaker enrollment | 实时与会后路径、总结服务要分别配置；其 Parakeet 分支不能代表中文能力 |
| [Muesli-HQ/muesli](https://github.com/Muesli-HQ/muesli/tree/05eb305db67d4b39beabf70388dc790d4d6c5a12) | 原生 Swift/SwiftUI；最低 macOS 14.2；Core Audio tap 为主，ScreenCaptureKit fallback；双轨、实时/最终转写、FluidAudio diarization、会议历史/导出 | 会议生命周期、捕获回退、转写修订与恢复、远端多人标签 | 功能很多，按模块阅读；不同 ASR 的语言/系统下限不同，不宜整体搬入 |
| [yazinsai/OpenOats](https://github.com/yazinsai/OpenOats/tree/b79fe07d60d326c6bc57fd1a7bc0aa2f5ab6b8e7) | macOS 15+，Swift 6.2；AVAudioEngine mic + Core Audio tap 双流；本地流式转写、可选 LS-EEND 远端多人区分、会话保存、笔记检索 | 实时 segment queue、会话状态、watchdog/restart、可选本地或云端文本处理 | 多人区分有独立设置；关闭时远端是来源标签，启用后的准确率未实测 |
| [bitwize-ai/Logue](https://github.com/bitwize-ai/Logue/tree/009a6095963acd95fc72d01d27564565880e5cf3) | Swift/SwiftUI；macOS 26+；ScreenCaptureKit 双源；Apple SpeechTranscriber、FluidAudio Sortformer 与 batch fallback | 说话人时间轴对齐既有 transcript、合并重复 speaker | 是更大的文档/任务工作区；部署下限高于 Stet，只作专项参考 |

### 直接读这些模块

**Meeting Transcriber**

- [DualSourceRecorder.swift](https://github.com/pasrom/meeting-transcriber/blob/f17ae33f0d1c1a1b5c871de7f5fd0d8c86f4033a/app/MeetingTranscriber/Sources/DualSourceRecorder.swift)：两路录制组织。
- [AudioMixer.swift](https://github.com/pasrom/meeting-transcriber/blob/f17ae33f0d1c1a1b5c871de7f5fd0d8c86f4033a/app/MeetingTranscriber/Sources/AudioMixer.swift)：轨道合成边界；复制前核验时间对齐策略。
- [FluidDiarizer.swift](https://github.com/pasrom/meeting-transcriber/blob/f17ae33f0d1c1a1b5c871de7f5fd0d8c86f4033a/app/MeetingTranscriber/Sources/FluidDiarizer.swift)、[LiveSpeakerMatcher.swift](https://github.com/pasrom/meeting-transcriber/blob/f17ae33f0d1c1a1b5c871de7f5fd0d8c86f4033a/app/MeetingTranscriber/Sources/LiveSpeakerMatcher.swift)：说话人分离与匹配。
- [README](https://github.com/pasrom/meeting-transcriber/blob/f17ae33f0d1c1a1b5c871de7f5fd0d8c86f4033a/README.md)、[MIT LICENSE](https://github.com/pasrom/meeting-transcriber/blob/f17ae33f0d1c1a1b5c871de7f5fd0d8c86f4033a/LICENSE)。模型本地运行与总结是否调用外部服务要分别判断。

**Muesli**

- [CoreAudioSystemRecorder.swift](https://github.com/Muesli-HQ/muesli/blob/05eb305db67d4b39beabf70388dc790d4d6c5a12/native/MuesliNative/Sources/MuesliNativeApp/CoreAudioSystemRecorder.swift)、[MeetingMicRecording.swift](https://github.com/Muesli-HQ/muesli/blob/05eb305db67d4b39beabf70388dc790d4d6c5a12/native/MuesliNative/Sources/MuesliNativeApp/MeetingMicRecording.swift)：系统/麦克风采集模块。
- [DiarizerRuntimePolicy.swift](https://github.com/Muesli-HQ/muesli/blob/05eb305db67d4b39beabf70388dc790d4d6c5a12/native/MuesliNative/Sources/MuesliNativeApp/DiarizerRuntimePolicy.swift)：diarization 运行策略。远端的 Speaker 1/2 是匿名分组，不能当作跨会话真实身份。
- [Package.swift](https://github.com/Muesli-HQ/muesli/blob/05eb305db67d4b39beabf70388dc790d4d6c5a12/native/MuesliNative/Package.swift)、[README](https://github.com/Muesli-HQ/muesli/blob/05eb305db67d4b39beabf70388dc790d4d6c5a12/README.md)、[MIT LICENSE](https://github.com/Muesli-HQ/muesli/blob/05eb305db67d4b39beabf70388dc790d4d6c5a12/LICENSE)。

**OpenOats / Logue**

- OpenOats：[MicCapture.swift](https://github.com/yazinsai/OpenOats/blob/b79fe07d60d326c6bc57fd1a7bc0aa2f5ab6b8e7/OpenOats/Sources/OpenOats/Audio/MicCapture.swift)、[SystemAudioCapture.swift](https://github.com/yazinsai/OpenOats/blob/b79fe07d60d326c6bc57fd1a7bc0aa2f5ab6b8e7/OpenOats/Sources/OpenOats/Audio/SystemAudioCapture.swift)、[Package.swift](https://github.com/yazinsai/OpenOats/blob/b79fe07d60d326c6bc57fd1a7bc0aa2f5ab6b8e7/OpenOats/Package.swift)、[MIT LICENSE](https://github.com/yazinsai/OpenOats/blob/b79fe07d60d326c6bc57fd1a7bc0aa2f5ab6b8e7/LICENSE)。
- OpenOats 多人分离已核验实际接线：[DiarizationManager.swift](https://github.com/yazinsai/OpenOats/blob/b79fe07d60d326c6bc57fd1a7bc0aa2f5ab6b8e7/OpenOats/Sources/OpenOats/Transcription/DiarizationManager.swift) 包装 FluidAudio `LSEENDDiarizer`；[TranscriptionEngine.swift](https://github.com/yazinsai/OpenOats/blob/b79fe07d60d326c6bc57fd1a7bc0aa2f5ab6b8e7/OpenOats/Sources/OpenOats/Transcription/TranscriptionEngine.swift) 按 `enableDiarization` 初始化、把系统音频送入模型，再按 segment 时间取得远端 speaker。未实测识别质量，也未确认 Stet 的旧 FluidAudio pin 是否提供该接口。
- Logue：[RecordingSessionManager+Diarization.swift](https://github.com/bitwize-ai/Logue/blob/009a6095963acd95fc72d01d27564565880e5cf3/Logue/Services/RecordingSessionManager%2BDiarization.swift)、[README](https://github.com/bitwize-ai/Logue/blob/009a6095963acd95fc72d01d27564565880e5cf3/README.md)、[MIT LICENSE](https://github.com/bitwize-ai/Logue/blob/009a6095963acd95fc72d01d27564565880e5cf3/LICENSE)。适合看迟到的说话人结果如何对齐文本。

### 跨平台对照：可看产品，不能当作 Swift 组件

| 项目 | 核验结果 | 用途 |
|---|---|---|
| [Meetily](https://github.com/Zackriya-Solutions/meetily/tree/a2cb62e827da7ef59f65064c97233efb2313878e) | Rust/Tauri + Next.js，MIT；本地 mic/system 转写及可选 Ollama 总结。README 将 Community speaker identification 标为 Coming Soon，diarization 的 Pro 规划不能算开源已实现 | 录制→转写→总结的产品编排参考 |
| [Vibe](https://github.com/thewh1teagle/vibe/tree/4d1db65fd07d7927d7b4ef3a3d949539010147dc) | Rust/Tauri + TypeScript，MIT；README 声明本地转写、系统音频/mic 与 diarization；后者此次仅核验声明，未做实现或质量审计 | 跨平台能力对照、多引擎选择和导出体验 |

来源：[Meetily README](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/README.md)、[Meetily LICENSE](https://github.com/Zackriya-Solutions/meetily/blob/a2cb62e827da7ef59f65064c97233efb2313878e/LICENSE.md)、[Vibe README](https://github.com/thewh1teagle/vibe/blob/4d1db65fd07d7927d7b4ef3a3d949539010147dc/README.md)、[Vibe LICENSE](https://github.com/thewh1teagle/vibe/blob/4d1db65fd07d7927d7b4ef3a3d949539010147dc/LICENSE)。

## 3. 转写与说话人组件

| 方案 | 核验结论 | 对 Stet 的判断 |
|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Swift/CoreML，VAD、ASR、embedding、流式/离线说话人处理；代码 Apache-2.0。Stet pin 的 manifest 要求 Swift tools 6.0、macOS 14/iOS 17 | 已接入，可继续用 VAD/diarization；不要把当前主分支新增能力自动视为 Stet 已有能力 |
| [WhisperKit + SpeakerKit](https://github.com/argmaxinc/argmax-oss-swift) | 原 WhisperKit 仓库已扩展为 Argmax OSS Swift；WhisperKit 转写，SpeakerKit 提供本地 pyannote 聚类与转写归属；框架 MIT，SpeakerKit 模型 CC-BY-4.0 | Swift 原生的多语言 ASR/离线多人识别对照组；不等于买到完整会议采集与恢复链路 |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | C/C++ ASR，MIT；支持 Apple Silicon、Metal/Core ML、Swift 示例及 XCFramework | 需要跨平台引擎时有价值；对当前已有 Nano 的 Stet 会增加另一套 runtime，优先级低于采集改造 |
| [Fun-ASR-Nano](https://github.com/QwenAudio/Fun-ASR) / Stet 现有 runtime | 官方区分基础 Nano 的中英日能力与 MLT 的 31 语言能力；源码 Apache-2.0，模型按具体模型卡 | 中文会议先保留现有适配，用同一录音与 Whisper 多语言模型比较，再决定是否替换 |

FluidAudio 固定依赖依据：[Stet Package.resolved](../../Stet.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)、[pin 的 Package.swift](https://github.com/FluidInference/FluidAudio/blob/0346057d8245b5e7ace6965d499f85d93e803ef1/Package.swift)、[pin 的 README](https://github.com/FluidInference/FluidAudio/blob/0346057d8245b5e7ace6965d499f85d93e803ef1/README.md)、[Apache-2.0 LICENSE](https://github.com/FluidInference/FluidAudio/blob/b68f484789d81fda21efbf81e2ca9fcfd9dc22aa/LICENSE)。该 pin 的 Parakeet EOU 是英语模型，TDT v3 为 25 种欧洲语言；这是 ASR 限制，与能否对中文录音计算 speaker embedding 是不同问题。

WhisperKit 开源代码确有 `AudioStreamTranscriber`：反复处理缓冲并区分 confirmed/unconfirmed segments。因此不能说“开源版完全不支持实时”。不过官方列出的 Pro “实时转写并带说话人”服务，也不能直接算作 OSS 已提供的端到端能力。[AudioStreamTranscriber 源码](https://github.com/argmaxinc/argmax-oss-swift/blob/ea872ffd35705aa757f33033500b9b0d40bd38df/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift)、[OSS/Pro 与 SpeakerKit 说明](https://github.com/argmaxinc/argmax-oss-swift/blob/ea872ffd35705aa757f33033500b9b0d40bd38df/README.md)、[框架 LICENSE](https://github.com/argmaxinc/argmax-oss-swift/blob/ea872ffd35705aa757f33033500b9b0d40bd38df/LICENSE)、[SpeakerKit 模型卡](https://huggingface.co/argmaxinc/speakerkit-coreml)

Whisper 长音频需要窗口推进或分块拼接；实时 UI、分段文字时间戳、说话人归属及音频保存应分别验证。[Whisper large-v3 模型卡](https://huggingface.co/openai/whisper-large-v3)、[WhisperKit 转写实现](https://github.com/argmaxinc/argmax-oss-swift/blob/ea872ffd35705aa757f33033500b9b0d40bd38df/Sources/WhisperKit/Core/WhisperKit.swift)

## 4. Stet 当前已有能力与缺口

本地检查基准：`5163643603651b4ffffb48b3ef81fdedebaa8305`，检查开始时工作区干净。以下是源码事实，不是运行测试结果。

| 当前行为 | 本地证据 | 对会议录制的含义 |
|---|---|---|
| app 部署目标 macOS 15 | [project.pbxproj](../../Stet.xcodeproj/project.pbxproj) | 两条现代采集 API 都可评估，无需为当前产品引入旧系统驱动路径 |
| 会话订阅 MacAudioCaptureService，其生产者使用 AVCaptureSession / AVCaptureDeviceInput | [Meeting runtime](../../StetMac/Core/Speech/MacMeetingRecordingRuntime.swift)、[SessionFactory](../../StetMac/Core/Audio/Capture/MacCaptureAudioSessionFactory.swift) | 已有麦克风录制；没有系统音频独立轨道。外部扬声器被麦克风收进来不等于系统音频捕获 |
| 帧为 16 kHz、单声道，身份是 epoch 与累计 sample index | [AudioCaptureFrame](../../StetMac/Core/Speech/AudioCaptureEvent.swift)、[EventBridge](../../StetMac/Core/Speech/AudioCaptureEventBridge.swift) | 现有类型没有音源标签或原始 host time/PTS；不能直接拿两条独立回调按顺序拼起来 |
| 录中写 PCM16 WAV，同时把全部 Float samples 累积在内存 | [MeetingAudioWriter](../../StetMac/Core/Speech/MeetingAudioWriter.swift)、[runtime append](../../StetMac/Core/Speech/MacMeetingRecordingRuntime.swift) | 16k Float32 一路每小时约 230.4 MB（约 220 MiB），不含副本、模型与其他对象；双路会进一步增加 |
| 停止后才跑 Sortformer，再规划最长 20 秒的 Nano 转写窗 | [MeetingSessionProcessor](../../StetMac/Core/Speech/MeetingSessionProcessor.swift)、[FluidAudio adapter](../../StetMac/Core/FluidAudio/FluidAudioPassiveSpeechAnalyzer.swift)、[live wiring](../../StetMac/Core/Speech/MacMeetingRecordingRuntime.swift) | 已有会后转写，不是实时会议转写；“20 秒分块”也没有消除采集期全量内存占用 |
| 保存音频、Markdown 与 session JSON，处理失败时尽量保留音频和失败记录 | [MeetingRecordingStore](../../StetMac/Core/Speech/MeetingRecordingStore.swift)、[runtime](../../StetMac/Core/Speech/MacMeetingRecordingRuntime.swift) | 可继续复用持久化入口，增加分轨索引和可恢复处理状态 |

### 建议接入次序（工程判断，尚未实施）

1. **先保证两路音频完整。** 保留现有麦克风采集，新增 process tap；每块记录 source、原始时间信息、采样率、声道和 discontinuity。系统音频排除 Stet 自身输出，并实测会议客户端/浏览器子进程选择。
2. **先分别持久化，再生成分析流。** 统一 session 时间轴，显式记录静音、丢帧和设备切换；从录音分段读取到 16 kHz 分析窗口，用有界队列替代全会 samples 累积。重采样保留时间映射，不能按回调抵达时刻决定两路偏移。[Core Media PTS 定义](https://developer.apple.com/documentation/coremedia/cmsamplebuffer/presentationtimestamp)
3. **让转写失败可以重跑。** 复用 Nano 和现有会话输出，每个已完成窗口记录进度；采集写盘错误与模型处理错误分别进入可见状态，保留已完成片段。
4. **多人能力单独比较。** 流式 Sortformer 用于其人数范围内的预览；5 人及以上会议，比较 FluidAudio 离线 pipeline 或 SpeakerKit。说话人轨道编号只表示聚类，不等于真实姓名；身份确认继续沿用已有 enrollment/embedding 层。[Sortformer 边界](https://docs.fluidinference.com/diarization/sortformer)、[SpeakerKit](https://github.com/argmaxinc/argmax-oss-swift#speakerkit)
5. **回声另做验证。** 麦克风收到的远端声音含声学延迟与房间响应，不能直接减掉系统轨；音量压低（ducking）与 AEC 是不同操作。耳机/外放两类输入分别评估后，再决定何处引入回声处理。

这是一条复用 Stet 的增量路线，不要求同时换采集、ASR 和 UI。若产品目标改成带画面的会议录像，再用同一测试素材比较 ScreenCaptureKit 后端。

## 5. 下一步验证范围

这些是用于作出实现决定的测试建议，本次未执行：

- Zoom、Teams、浏览器 Meet；耳机与外放各测，两路单独试听确认谁被录下。
- 60–120 分钟录制；开始/结束放置同步标记，检查长期偏移、内存增长和文件完整性。
- 内置/USB/蓝牙麦克风、44.1/48 kHz 切换；中途改变默认输出、拔设备、休眠与恢复，确认没有静默丢掉整场录音。
- 中英混说、专有名词、2/4/6 人、重叠说话；分别记录文字错误、说话人错误和处理时间，不能仅以“模型快”判断会议质量。
- 在签名后的 Stet 中核验系统音频与麦克风授权、拒绝后的恢复路径。

iOS 需要单独调查。这里的 process tap 方案是 macOS 路径；不能把 Swift 库能在 iOS 编译，推导为它能录下其他会议应用的全部音频。[Apple Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)

## 6. 核验快照与局限

| 仓库 | 本次核验 revision | 可见维护事实 |
|---|---|---|
| AudioCap | `6f609e8ad1b1e11fa0e8edbe91864cb099f00de3` | 可见最后提交 2025-08-07；应按小型示例评估 |
| AudioTee | `56ac954369a09318e46b88a6eec33c2d2b0d32a3` | 可见最后提交 2026-03-31 |
| mac-audio-recorder | `06c38d0c3d5279fad2c86202521d4ae60a74480a` | 可见最后提交 2026-07-27；小型新项目 |
| BlackHole | `ffcb74433fbcf8c8ca5c736677c1a4864384dc09` | 可见最后提交 2026-08-11；存在 [v0.7.1 release](https://github.com/ExistentialAudio/BlackHole/releases/tag/v0.7.1) |
| Meeting Transcriber | `f17ae33f0d1c1a1b5c871de7f5fd0d8c86f4033a` | 可见 HEAD 提交日期 2026-09-11 |
| Muesli | `05eb305db67d4b39beabf70388dc790d4d6c5a12` | 可见 HEAD 提交日期 2026-09-14 |
| OpenOats | `b79fe07d60d326c6bc57fd1a7bc0aa2f5ab6b8e7` | 可见 HEAD 提交日期 2026-09-13 |
| Logue | `009a6095963acd95fc72d01d27564565880e5cf3` | 可见 HEAD 提交日期 2026-08-29 |
| Meetily | `a2cb62e827da7ef59f65064c97233efb2313878e` | 可见 HEAD 提交日期 2026-09-10 |
| Vibe | `4d1db65fd07d7927d7b4ef3a3d949539010147dc` | 可见 HEAD 提交日期 2026-09-05 |
| FluidAudio | `b68f484789d81fda21efbf81e2ca9fcfd9dc22aa` | 本次 `git ls-remote HEAD`；Stet 仍固定 `0346057…`，两者未做完整 API 差异审计 |
| Argmax OSS Swift | `ea872ffd35705aa757f33033500b9b0d40bd38df` | 本次 `git ls-remote HEAD`；[v1.0.0](https://github.com/argmaxinc/argmax-oss-swift/releases/tag/v1.0.0) 说明项目更名与扩展 |

维护日期只说明公开活动，不证明稳定性或维护响应。本文没有把 README 的准确率、延迟、离线宣传当作 Stet 实测结果；许可证按具体代码与模型分别记录。调研阶段只新增了这份研究文档，未修改产品代码、依赖或模型。
