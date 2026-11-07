# 软件需求（Specs）

旧 spec 状态：**待整理，需求内容未更新，仅规范引用格式，已知存在过时内容**。核对日期：2026-11-07；代码基线：`a75b569`。

本次先原样恢复主 checkout 留存的 11 份 `spec.md`；配套 plan、tasks、research、checklist 和 contract 不纳入本次恢复，历史仍可从 Git 追溯。文件名保留编号与功能名，以区分两份 `009`。旧文档曾在 `c6a72b9`（2026-09-04）退出 Git 跟踪；本次恢复的是本地归档副本，来源不是根据当前代码重写的 spec。

## 已有 Specs

- [watercolor-orb](watercolor-orb.md) — 水彩圆球的视觉与交互行为。
- [app-compatibility](app-compatibility.md) — 粘贴兼容清单的分发与更新。
- [correction-learning](correction-learning.md) — 用户修正学习与词条来源。
- [rewrite-model-catalog](rewrite-model-catalog.md) — 改写模型目录与配置。

## 旧 Specs 阅读说明

- 11 份原始 spec 的需求内容暂不修改；文件引用统一为 Markdown 链接。所有现状差异、过时点和待确认项集中记录在本 INDEX。
- 文档恢复不代表恢复功能；旧 MUST、Draft、Implemented、任务勾选和验收数字均为历史内容，不自动成为当前约束或本次验证结果。
- “已替代 / 已移除”描述当前代码状态，不是最终处置决定，也不表示未来不能恢复该产品能力。
- 仅凭代码不符不能认定需求无效。未确认的产品目标、可达入口和真机行为保留待决，不作为已验收或应删除的结论。
- 原文中指向未恢复的 plan、tasks 或 contract 的引用保留并纳入链接 lint；旧源码路径、其他链接、工具指令和机器环境也可能失效；按历史上下文阅读，不直接执行旧计划。所有 spec 统一放在本目录，状态与差异在本索引登记。
- 本轮证据来自源码、测试源码和 Git 历史；未运行 App、测试或真机验收。

## 目录与差异摘要

| 原始 Spec | 现状标注 | 仍有价值的内容 | 过时点 / 待确认项 |
| --- | --- | --- | --- |
| [001 音频设备管理](001-audio-device-management.md) | 核心仍适用，待整理 | 设备选择、外置 UID 偏好、回退不覆盖偏好、麦克风测试 | “立即切换”是否要求录音中热切换，仍需确认；历史 Draft 和计划不作为当前状态 |
| [002 权限管理](002-permission-management.md) | 核心仍适用，范围需更新 | onboarding 权限门、运行时恢复、防重复窗口 | macOS 26+ 假设已过时，当前最低 15.0；未覆盖会议系统音频权限 |
| [003 音频采集管线](003-audio-capture-pipeline.md) | 主动听写仍适用 | 权限、重复启动保护、临时文件、取消、电平、启动缓冲 | 不能覆盖会议多轨持久录音；未写入音频和无语音应区分层次 |
| [004 音频后处理](004-audio-post-processing.md) | 实现范围已变化 | 无语音处理、条件增强、失败保留原音频、清理 | Nano 绕过后处理；新增裁切并改变时长，与 FR-001 / FR-006 不符；分析异常不一定透传 |
| [005 转写详情](005-transcribe-details.md) | 核心方案已被替代 | 转写与改写解耦 | 远程转写、强制改写、缺 key 阻断、改写失败不得输出原文，均与当前策略不符 |
| [006 文本输出](006-text-output-handling.md) | 核心仍适用，部分策略变化 | 粘贴、失败保留文本、剪贴板恢复、保护外部修改 | optimistic 不再只限显式 profile；空文本输出为 no-op；选区改写入口未确认 |
| [007 App Branch](007-app-branch.md) | 核心仍适用 | 目标应用上下文、排除自身、最近外部应用、audience | 旧 `.kiro` / Constitution / branch-plan 流程引用过时；API 细节是否保留待整理 |
| [008 MCP 转写](008-mcp-transcription.md) | 旧能力已被替代，原文保留 | 本机 MCP、默认关闭等边界可供追溯 | 当前是会议 / 预期会议 / 日历工具；旧 ASR tool、audio_path、SenseVoice、无设置 UI 等不再成立 |
| [009 FunASR Nano](009-fun-asr-nano.md) | 核心仍适用，回退策略过时 | 本地推理、模型下载、预热复用、热词 | Whisper fallback 已退役；模型 lease / 延迟清理需后续核对；历史 Implemented 不等于本轮验收 |
| [010 iOS 常驻采集](010-mobile-persistent-audio-capture.md) | 核心仍适用，产品组合变化 | 暖机帧门、单消费者、内置麦克风优先、路由恢复 | SenseVoice + FunASR 双引擎前提已失效；旧机器平台缺失说明过时；AirPods / 不抢麦等真机目标仍待验证 |
| [009 被动监听 / 声纹门控](009-passive-speech-gate.md) | 核心运行链路已移除，原文保留 | 说话人身份、旧记录兼容的需求可供追溯 | 默认全天监听、pending buffer、主人参与开门、热键后恢复被动监听均不再存在；当前会议识别不完全沿用旧 unresolved 语义 |

## 代码与历史证据

所有代码路径指向当前仓库，仅证明核对基线的实现，不是新的产品决策。

- **001**：[AudioDeviceSelectionResolver](../../StetMac/Core/Audio/Devices/AudioDeviceSelectionResolver.swift) 与 [AudioDeviceSelectionManager](../../StetMac/Core/Audio/Devices/AudioDeviceSelectionManager.swift) 保留缺失设备的原偏好并选择 fallback；设置中的麦克风测试仍在。
- **002**：[MacPermissionManager](../../StetMac/App/Lifecycle/MacPermissionManager.swift)、[MacPermissionGateController](../../StetMac/App/Windowing/MacPermissionGateController.swift) 和 [项目配置](../../Stet.xcodeproj/project.pbxproj) 支撑当前权限与系统版本判断。
- **003**：[MacAudioCaptureService](../../StetMac/Core/Speech/MacAudioCaptureService.swift) 与 [MacRecordingFileSupport](../../StetMac/Core/Audio/Recording/MacRecordingFileSupport.swift) 保留采集保护、临时文件和 pending buffer。
- **004**：[ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 对 Nano 使用 passthrough；[DefaultAudioPostProcessor](../../StetMac/Core/Audio/Processing/DefaultAudioPostProcessor.swift) 执行 VAD 裁切、更新 duration；[测试](../../StetMacTests/Core/Audio/Processing/DefaultAudioPostProcessorTests.swift) 包含长停顿裁切。
- **005**：[DictationPipelineFactory](../../StetMac/Core/DictationPipeline/DictationPipelineFactory.swift) 构造本地转写；[ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 在改写失败时回退原文；[测试](../../StetMacTests/Core/DictationPipeline/DictationPipelineTests.swift) 明确允许缺 key 回退并忽略 legacy transcription provider。
- **006**：[MacDictationCaptureCoordinator](../../StetMac/App/Workflows/MacDictationCaptureCoordinator.swift) 与 [测试](../../StetMacTests/App/Workflows/MacDictationCaptureCoordinatorTests.swift) 允许非 profile 的 likely text input 乐观完成；[TextInjectionService](../../StetMac/Core/TextInput/TextInjectionService.swift) 有 selectedText / replaceSelectedText，但未找到上层调用。名单维护已有 [app-compatibility spec](app-compatibility.md)。
- **007**：[AppBranchMonitor](../../StetMac/Core/AppBranch/AppBranchMonitor.swift) 和 [AppAudience](../../StetMac/Core/AppBranch/AppAudience.swift) 仍提供目标应用与 audience，改写链路仍消费它们。
- **008**：`dba6c2a` 明确以已保存会议转写替代按需 ASR；[协议服务器](../../StetMac/Core/MCP/StetMCPProtocolServer.swift) 提供现行工具，[测试](../../StetMacTests/Core/MCP/StetMCPProtocolServerTests.swift) 将 `stet_transcribe_audio` 判为 unknown tool；`e2e1293` 增加 MCP 设置引导。
- **009 Nano**：[模型管理](../../StetMac/Core/FunASR/FunASRNanoModelManager.swift)、[转写服务](../../StetMac/Core/FunASR/FunASRNanoTranscriptionService.swift) 仍在；[引擎工厂](../../StetMac/Core/DictationPipeline/LocalTranscriptionServiceFactory.swift) 以 Nano 作为其他本地引擎的 fallback。`bd0bbad` 退役 Whisper 产品路径，`202f778` 清除遗留 runtime。
- **010**：[ASRAudioCapture](../../Packages/StetEngine/Sources/StetASR/ASRAudioCapture.swift) 保留帧门、策略与恢复；[iOS composition](../../StetMobile/StetMobile/App/StetMobileApp.swift) 注入 builtInPreferred 给 FunASRRealtimeEngine；`5a475f9` 删除 SenseVoice 引擎实现。遗留 SenseVoiceView 名称不证明引擎仍在。
- **009 被动监听**：`7698c1c` 移除被动监听并保留会议处理；[HistoryEntry](../../Packages/StetEngine/Sources/StetCore/HistoryEntry.swift) 明确保留 passive 值用于旧记录兼容；[MeetingSessionProcessor](../../StetMac/Core/Speech/MeetingSessionProcessor.swift) 的非重叠身份识别会将 unresolved 映射为 other，不能原样套用旧 spec 的身份要求。

## 后续整理

由 [GitHub #182](https://github.com/DengNaichen/Stet/issues/182) 跟踪。逐项确认产品意图后再决定更新、迁入现行 specs 或保留历史；本 INDEX 中的现状分类不预先决定结果。
