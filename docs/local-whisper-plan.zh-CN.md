# 本地单模型 Whisper 方案

这份文档定义一个收敛版方案：

- 目标只覆盖 `transcription`
- 使用单一本地 Whisper 模型
- 不做模型管理平台
- 不让用户切模型、导入模型、删除模型
- 首次使用时自动下载
- `rewrite` 暂时保持现状，不和这次方案绑定

这不是“参考 VoiceInk 全套实现”的计划。
这是“借用 VoiceInk 的本地 Whisper 接法，但把产品形态收窄到 Stet 需要的最小版本”的计划。

## 目标

1. 将 Stet 的转写能力直接固定为本地 Whisper。
2. 保留当前录音、后处理、rewrite、文本注入链路。
3. 避免引入新的模型管理 UI 和额外产品复杂度。
4. 让用户只感知到一件事：
   首次使用时需要下载本地模型，之后直接使用。

## 不做的事

这一版明确不做：

- 多模型切换
- 自定义模型导入
- 模型删除 / 模型管理页面
- 本地与云端自动回退混合调度
- 流式 Whisper 转写
- 把 rewrite 一起改成本地

## 为什么选这条线

当前 Stet 的架构已经具备几个关键前提：

- 录音结果已经以文件 URL 形式进入转写层
  - [ConfigurableSpeechService.swift](/Users/nd/Developer/stet-project/Stet/Stet/Core/Speech/ConfigurableSpeechService.swift)
- 转写入口已经抽象成 `AudioFileTranscriptionService`
  - [DictationPipelineFactory.swift](/Users/nd/Developer/stet-project/Stet/Stet/Core/DictationPipeline/DictationPipelineFactory.swift)
- 音频预处理已经是本地链路
  - `FluidAudio` 已用于本地音频处理

所以这次不是重写整条 dictation pipeline。
核心是把当前产品实际使用的 transcription 路径直接切到本地 Whisper，并补上模型下载与状态管理。

## 从 VoiceInk 借什么

参考仓库 `VoiceInk` 已经证明了几件事：

1. `whisper.cpp` 可以在 macOS App 内稳定跑通
   - [WhisperTranscriptionService.swift](/Users/nd/Developer/stet-project/Stet/VoiceInk/VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift)
2. 模型可以直接从 Hugging Face 的 `ggerganov/whisper.cpp` 下载
   - [TranscriptionModel.swift](/Users/nd/Developer/stet-project/Stet/VoiceInk/VoiceInk/Models/TranscriptionModel.swift)
3. `whisper.cpp` 的 XCFramework 构建和接入可以自动化
   - [BUILDING.md](/Users/nd/Developer/stet-project/Stet/VoiceInk/BUILDING.md)
   - [Makefile](/Users/nd/Developer/stet-project/Stet/VoiceInk/Makefile)

这次建议借用的只有三层：

- `whisper.cpp` framework 接入方式
- 本地文件转写服务的实现思路
- 固定模型下载与本地目录管理思路

不建议照搬的部分：

- `VoiceInk` 的模型平台
- 模型管理 UI
- 多 provider service registry
- 自定义模型导入

## 推荐产品形态

### 用户体验

用户只看到下面几个状态：

1. 还未下载模型
2. 模型下载中
3. 模型可用
4. 下载失败

用户不会看到：

- 模型列表
- 量化版本选择
- 多模型对比
- 模型删除按钮
- 导入本地模型入口

### 模型策略

建议直接固定为：

- **最小的可用多语言量化 Whisper 模型**

约束：

- 不要用 English-only 变体
- 不对用户暴露模型选择
- 首版优先选择下载体积最小、能覆盖中文和中英混输的量化版本

产品原则是：

- 先把本地优先形态跑通
- 先把首次下载成本和冷启动成本压低
- 如果后续质量不足，再升级固定模型

也就是说，首版默认不是追求“最强模型”，而是追求：

- 最低下载成本
- 最低磁盘占用
- 最低启动负担
- 足够可用的多语言能力

## 推荐架构

### 一、引入本地模型管理器

新增一个收敛版的本地模型管理器，例如：

- `Stet/Core/LocalWhisper/LocalWhisperModelManager.swift`

职责只包括：

- 固定模型文件名
- 固定下载 URL
- 固定本地存储目录
- 检查模型是否存在
- 下载模型
- 暴露下载状态

不包括：

- 多模型元数据
- 当前模型切换
- 模型删除
- 自定义导入

建议状态：

- `notDownloaded`
- `downloading(progress: Double)`
- `ready(localURL: URL)`
- `failed(message: String)`

### 二、引入本地转写服务

新增一个本地 Whisper 转写服务，例如：

- `Stet/Core/LocalWhisper/LocalWhisperTranscriptionService.swift`

它实现现有协议：

- `AudioFileTranscriptionService`

输入保持不变：

- `audioFileAt fileURL: URL`
- `languageCode`
- `prompt`
- `audioDurationSeconds`

输出保持不变：

- `String`

内部流程：

1. 从 `LocalWhisperModelManager` 取本地模型 URL
2. 加载或复用 `WhisperContext`
3. 读取 WAV/PCM 样本
4. 调用 `whisper.cpp` 完成转写
5. 返回原始 transcript

这一步对现有 pipeline 是最友好的，因为上层几乎不需要知道底下是远端还是本地。

### 三、引入最小 warmup

这一部分建议**完整参考 VoiceInk 的 warmup 思路**。

参考实现：

- [WhisperModelWarmupCoordinator.swift](/Users/nd/Developer/stet-project/Stet/VoiceInk/VoiceInk/Transcription/Whisper/WhisperModelWarmupCoordinator.swift)
- [ModelPrewarmService.swift](/Users/nd/Developer/stet-project/Stet/VoiceInk/VoiceInk/Services/ModelPrewarmService.swift)

新增：

- `Stet/Core/LocalWhisper/LocalWhisperWarmupCoordinator.swift`
- `Stet/Core/LocalWhisper/LocalWhisperPrewarmService.swift`

用途不再是“可有可无的小优化”，而是本方案的一部分。

具体做法：

- 模型下载完成后，立即做一次 warmup
- App 冷启动后，延迟几秒做一次 warmup
- Mac 从睡眠唤醒后，延迟几秒再做一次 warmup
- 预热时使用应用内置的一段极短音频样本
- warmup 本质上就是跑一次真实的本地转写，让底层模型加载、编译和缓存提前发生

建议直接沿用 `VoiceInk` 这套机制的核心原则：

1. 不等用户第一次正式说话时才冷启动模型
2. 不在 UI 主线程同步做 warmup
3. 不对用户暴露复杂的 warmup 状态
4. warmup 失败只记日志，不阻断正常使用

建议内置一个很短的音频文件，例如：

- `Resources/Sounds/esc.wav`

要求：

- 时长尽量短
- 文件尽量小
- 内容稳定
- 不需要有语义价值，只要能触发一次完整推理路径即可

### Warmup 触发时机

首版建议固定三种触发：

1. 模型下载完成后
2. App 启动完成后，延迟约 3 秒
3. 设备从睡眠唤醒后，延迟约 3 秒

这三种触发和 `VoiceInk` 的思路一致，能覆盖最常见的冷启动来源：

- 首次安装后第一次使用
- 用户长时间没用后重新打开应用
- 机器睡眠后恢复使用

### 为什么要完整参考这套思路

本地 Whisper 方案里，warmup 不是锦上添花，而是直接影响产品体感：

- 不做 warmup，第一次真实转写通常最慢
- 用户会把“第一次卡顿”理解成“这个产品本来就慢”
- 唤醒后不重新 warmup，恢复使用时也可能再次命中冷路径

所以这里不建议只做“下载后 warmup 一次”的最小版。
建议直接按 `VoiceInk` 的方式把 warmup 当成常规生命周期服务。

### 四、调整执行路由

当前 Stet 的 route 设计是围绕远端 provider 的：

- [DictationExecutionRoute.swift](/Users/nd/Developer/stet-project/Stet/Stet/Core/DictationPipeline/DictationExecutionRoute.swift)
- [DictationSettingsStore.swift](/Users/nd/Developer/stet-project/Stet/Stet/Shared/Utilities/DictationSettingsStore.swift)
- [OpenAICompatibleProviderConfiguration.swift](/Users/nd/Developer/stet-project/Stet/Stet/Core/AIProviders/OpenAICompatible/OpenAICompatibleProviderConfiguration.swift)

当前问题是：

- `transcriptionProvider` 只能是 `OpenAI` / `Groq`
- 路由解析默认按“需要 API key”处理 transcription

这次不建议继续做一个“transcription source 可切换”的新体系。

这次直接收敛成：

- transcription 主路径固定为本地 Whisper
- `rewriteProvider` 继续保持现有设计
- 现有 `OpenAI` / `Groq` transcription 代码先短路保留，不删代码

实现目标是：

- `DictationPipelineFactory` 默认返回 `LocalWhisperTranscriptionService`
- route / preflight 层不再对 transcription 要远端 API key
- 现有远端 transcription service 仍保留在代码库中，但不进入当前产品主路径

也就是说，这次是“固定主路径”，不是“增加第三个可选项”。

## 设置层建议

### 收敛版 UI

这次不提供 transcription source 选择。

设置层只需要体现两件事：

1. transcription 由本地 Whisper 提供
2. 当前本地模型是否已下载完成

用户不会看到：

- `OpenAI` transcription
- `Groq` transcription
- transcription source picker

用户只会看到：

- 模型未下载
- 下载中
- 已可用
- 下载失败

也就是说，设置页里关于 transcription 的 UI 只保留“模型状态”，不保留“来源选择”。

## 建议的落地路径

### Phase 1. 接入本地 Whisper 基础设施

目标：

- 在仓库内成功链接 `whisper.cpp`
- 让 macOS target 可以访问 `WhisperContext`

工作：

- 参考 `VoiceInk` 的 `whisper.xcframework` 构建方式
- 确定 Stet 侧依赖接入方式
- 写入本地构建说明

### Phase 2. 做单模型管理器

目标：

- 让应用能检查、下载、定位本地模型文件

工作：

- 固定模型 URL
- 固定模型文件名
- 固定存储目录
- 实现下载和状态持久化

### Phase 3. 做本地转写服务

目标：

- 让 `AudioFileTranscriptionService` 能走本地 Whisper

工作：

- 实现 `LocalWhisperTranscriptionService`
- 音频文件读取与样本转换
- 返回 transcript

### Phase 4. 接到现有 pipeline

目标：

- `ConfigurableSpeechService` 的 transcription 主路径固定走本地 Whisper

工作：

- `DictationPipelineFactory` 默认构建 `LocalWhisperTranscriptionService`
- 调整 route / preflight 校验，不再对 transcription 要远端 API key
- 现有 `OpenAI` / `Groq` transcription 相关分支先短路保留，不进入默认路径

### Phase 5. 加最小 UI 状态

目标：

- 用户能看懂“未下载 / 下载中 / 可用 / 失败”

工作：

- 设置页或 onboarding 中加最小状态提示
- 不加模型管理页面

### Phase 6. 接入完整 warmup 生命周期

目标：

- 避免第一次正式转写时冷启动过慢

工作：

- 下载完成后 warmup
- App 启动延迟 warmup
- 系统唤醒延迟 warmup
- 内置短音频样本
- 日志化 warmup 成功 / 失败 / 耗时

## 代码落点建议

新增目录建议：

```text
Stet/Core/LocalWhisper/
├── LocalWhisperModelManager.swift
├── LocalWhisperModelState.swift
├── LocalWhisperTranscriptionService.swift
├── LocalWhisperWarmupCoordinator.swift
└── LocalWhisperPrewarmService.swift
```

需要改动的现有文件：

```text
Stet/Core/DictationPipeline/DictationPipelineFactory.swift
Stet/Core/DictationPipeline/DictationExecutionRoute.swift
Stet/Shared/Utilities/DictationSettingsStore.swift
Stet/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift
Stet/Features/MacShell/Openai/MacOpenAISettingsView.swift
Stet/App/Lifecycle/MacAppModel.swift
```

其中要特别注意：

- 不删除现有远端 transcription service
- 不删除现有 provider 配置类型
- 只把当前产品主路径短路到本地 Whisper
- `rewrite` 相关远端 provider 保持原样

测试建议新增：

```text
StetTests/Core/LocalWhisper/
├── LocalWhisperModelManagerTests.swift
├── LocalWhisperTranscriptionServiceTests.swift
└── DictationExecutionRouteLocalWhisperTests.swift
```

## 风险

### 1. 模型选型错误

如果模型过大：

- 首次下载慢
- 首轮启动慢
- 老机器体验差

如果模型过小：

- 中英混输质量差
- 专名识别差

所以首版虽然定成“最小量化多语言模型”，也要接受一个现实：

- 这是体验优先，不是质量优先

如果实测质量不够，再只升级这个固定模型，不引入模型管理能力。

### 2. 首轮冷启动

即使接入成功，首轮加载和底层编译仍可能明显变慢。

这个风险默认通过完整 warmup 生命周期来缓解，而不是交给用户第一次正式使用时承担。

### 4. 不同机型差异

本地推理对硬件更敏感。

所以要明确：

- 这是延迟更可控的方案
- 不是所有 Mac 都会同样快

### 5. 远端 transcription 分支会暂时保留但不走主路径

这是有意为之。

这次目标是先把产品执行路径收紧，而不是立刻做大规模代码删除或 provider 架构清理。

## 工作量评估

如果按这份“单模型、无管理 UI”的收敛版来做：

- `whisper.cpp` 接入：中等
- 单模型下载器：中等
- 本地 transcription service：中等
- route / settings 改造：中等
- UI 状态提示：小到中等

整体评估：

**中等偏大，但明显小于做一套完整的本地模型平台。**

它不是小改。
但它已经不属于“需要推倒重来”的级别。

## 结论

推荐路线是：

1. 借用 `VoiceInk` 的 `whisper.cpp` 接入和本地文件转写思路
2. 只支持一个固定 Whisper 模型
3. 用户不参与模型管理
4. 首次使用时自动下载
5. transcription 直接固定为本地 Whisper
6. 远端 transcription 代码先短路保留，不删
7. 继续复用 Stet 现有 dictation pipeline

这个方案比“直接参考 VoiceInk 做完整模型管理”更适合 Stet，也更符合当前的产品方向。
