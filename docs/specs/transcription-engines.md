# 功能规格：转写引擎与模型准备

**创建**：2026-11-07
**状态**：Draft（待产品确认）
**输入**：统一定义听写使用哪个转写引擎、引擎不可用时怎样回退、模型怎样下载 / 镜像 / 存储 / 预热，以及每个引擎各自的音频后处理与热词使用方式。
**替代**：旧 spec「009 FunASR Nano」「004 音频后处理」中仍适用的部分，以及「005 转写详情」中关于转写的部分。

**范围**：macOS 与 iOS。macOS 使用本机引擎；iOS 只单列平台独有的引擎与配置（FR-021 至 FR-023）。
**边界**：本 spec 拥有引擎选择与回退、模型下载 / 镜像 / 存储 / 预热、各引擎的音频后处理规则、各引擎如何使用热词。其他规则只引用：词典向转写提供哪些词见『个人词典』spec；无语音、转写失败时用户看到什么见『听写结果与失败处理』spec；录音与临时文件的产生见『macOS 听写会话』spec；会议转写与说话人模型的使用见『会议转写与说话人』spec（其模型的下载与镜像沿用本 spec FR-009）；iOS 采集生命周期见『iOS 常驻麦克风与 Live Activity』spec；权限见 [权限与恢复](permissions-and-recovery.md)。macOS 远程转写（OpenAI / Groq）、Whisper、SenseVoice 已移除，不在范围内。

## 术语

- **引擎**：把一段录音转成文字的组件。macOS 有 Fun-ASR Nano、Parakeet V3、Apple Speech 三种；iOS 有 FunASR Realtime 一种。
- **模型资产**：引擎运行所需、安装后下载到本机的模型文件；不随应用打包。
- **回退**：用户选定的引擎在本次听写不可用时，临时改用 Fun-ASR Nano，不改动用户的选择。
- **预热**：在录音期间提前把模型载入内存，缩短停止录音后的等待。
- **后处理**：录音结束后、转写之前对音频做的无语音判定、增益和静音裁切。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 用选定的本机引擎完成转写（优先级：P1）

作为 Mac 用户，我在设置中选择一个本机引擎，之后每次听写都用它转写，录音不离开本机。

**为什么是这个优先级**：转写是听写的核心；引擎选择不生效，其他能力都无从谈起。

**独立测试**：分别选择三种引擎并准备好模型，各完成一次听写，确认转写由所选引擎完成，且无网络连接时同样成功。

**验收场景**：

1. **Given** Fun-ASR Nano 的模型已下载，**When** 我选择它并完成一次听写，**Then** 得到本机转写的文字。
2. **Given** 我在录音进行中修改了引擎，**When** 本次听写结束，**Then** 本次仍用开始时的引擎，新选择从下一次听写起生效。
3. **Given** 首次安装、尚未选择过引擎，**When** 我打开转写设置，**Then** 默认选中 Fun-ASR Nano。

---

### 用户故事 2 - 下载模型并看到就绪状态（优先级：P1）

作为 Mac 用户，我可以在设置里下载引擎模型，看到下载中、已下载或失败，并能在 Finder 中找到模型位置。

**为什么是这个优先级**：模型不随应用打包，没有下载入口就无法听写。

**独立测试**：在缺少模型的状态下点击下载，确认状态从“下载中”变为“已下载”；模拟服务器返回错误，确认显示错误且不留下损坏文件。

**验收场景**：

1. **Given** Fun-ASR Nano 的三个模型文件都缺失，**When** 我点击下载，**Then** 三个文件依次下载到本机模型目录，完成后显示“已下载”。
2. **Given** 其中一个文件已存在，**When** 我再次下载，**Then** 已存在的文件不重新下载。
3. **Given** 下载返回非成功状态码，**When** 下载结束，**Then** 该文件不被安装，设置中显示错误，可以重试。
4. **Given** 当前地区判定为中国大陆，**When** 下载模型，**Then** 优先使用国内可访问的镜像，失败时依次尝试其他来源（FR-009）。

---

### 用户故事 3 - 选定引擎不可用时仍能听写（优先级：P2）

作为 Mac 用户，当我选的 Parakeet 或 Apple Speech 暂时不可用时，我希望听写自动改用 Fun-ASR Nano，而不是直接失败。

**为什么是这个优先级**：可选引擎依赖额外下载或系统版本，回退保证主流程可用。

**独立测试**：选择 Parakeet 但不下载其模型，完成一次听写，确认由 Fun-ASR Nano 转写，且设置中的选择仍是 Parakeet。

**验收场景**：

1. **Given** 选择了 Parakeet 且其模型未下载，**When** 我听写，**Then** 本次用 Fun-ASR Nano 转写；设置中提示“下载前会回退到 Fun-ASR Nano”。
2. **Given** 选择了 Apple Speech 但系统低于 macOS 26 或系统语音转写不可用，**When** 我听写，**Then** 本次用 Fun-ASR Nano 转写，设置中的选择保持不变。
3. **Given** 需要回退但 Fun-ASR Nano 的模型也未下载，**When** 我触发听写，**Then** 听写不开始，结果见『听写结果与失败处理』spec。

---

### 用户故事 4 - 按引擎处理音频（优先级：P2）

作为听写流程，我希望对需要的引擎先剔除无语音录音、调整音量并裁掉长静音，对自带语音检测的 Fun-ASR Nano 则直接交给引擎。

**为什么是这个优先级**：无语音录音不应产生文字；音量与静音处理影响识别质量。

**独立测试**：用 Parakeet 分别处理纯静音、音量很低的语音和含长停顿的语音；再用 Fun-ASR Nano 处理同样的录音，确认后者不经过后处理。

**验收场景**：

1. **Given** 引擎为 Parakeet 或 Apple Speech，录音中没有持续 0.4 秒以上的语音，**When** 录音结束，**Then** 不进行转写，按“无语音”处理。
2. **Given** 录音中语音音量明显偏低且噪声余量足够，**When** 后处理，**Then** 生成增益后的音频用于转写，原文件不变。
3. **Given** 录音中有超过阈值的长静音，**When** 后处理，**Then** 静音被裁短，用于转写的音频时长随之变短（待产品确认）。
4. **Given** 引擎为 Fun-ASR Nano，**When** 录音结束，**Then** 原始录音直接交给引擎（待产品确认）。

---

### 用户故事 5 - 用个人词典引导识别（优先级：P2）

作为 Mac 用户，我希望 Fun-ASR Nano 在识别时参考我的个人词典，让专有名词识别得更准。

**独立测试**：词典开启并含若干词条，用 Fun-ASR Nano 听写包含这些词的内容；再清空词典重复，确认前者带热词、后者不带。

**验收场景**：

1. **Given** 词典开启且有词条，**When** Fun-ASR Nano 转写，**Then** 词条按 FR-016 的上限作为热词传给引擎。
2. **Given** 词典为空或关闭，**When** 转写，**Then** 不传热词。

### 边界情况

- 下载中途网络中断：当前文件不安装，之前已完成的文件保留；再次下载只补缺失文件。
- 模型文件被用户在 Finder 中删除：下次听写创建引擎时判定为缺失，按 FR-004 / FR-005 处理。
- Apple Speech 的语言资源未安装：首次转写时由系统自动下载安装，转写等待下载完成；所选语言不受支持时转写失败，不回退（待产品确认）。
- 后处理时音频不是 WAV 或无法读取：跳过后处理，原文件交给引擎。
- 增益或裁切写文件失败：跳过该步，继续用上一步的音频转写。
- 无语音判定本身出错（语音检测模型无法加载等）：本次按转写失败处理（待产品确认）。
- 会议正在使用 Fun-ASR Nano 时听写结束：模型等会议释放后才卸载。

## 需求 *(必填)*

### 功能需求

**引擎选择与回退（macOS）**

- **FR-001**：macOS 提供三种本机引擎供选择：Fun-ASR Nano（默认，支持中文、英文、日文）、Parakeet V3（多语言）、Apple Speech（标注“实验性”，需要 macOS 26 及以上）。转写全程在本机进行，录音不上传。
- **FR-002**：引擎选择保存在本机偏好中。已退役的旧取值（Whisper、SenseVoice）在读取时改为默认引擎。
- **FR-003**：每次听写在开始录音时按当时的选择创建引擎；录音期间修改选择，从下一次听写起生效。
- **FR-004**：所选引擎在本次听写不可用时临时回退到 Fun-ASR Nano，不改写保存的选择：Parakeet 模型未下载或无法创建时回退；Apple Speech 因系统版本或系统能力不可用时回退。回退在听写过程中不提示；设置页对 Parakeet 未下载显示回退说明，对 Apple Speech 显示资源状态（待产品确认）。
- **FR-005**：最终要使用的 Fun-ASR Nano 缺少任一模型文件时，听写不得开始录音；设置页在选中 Fun-ASR Nano 且未下载时提示“听写前先下载”。用户可见结果见『听写结果与失败处理』spec。
- **FR-006**：Apple Speech 按用户的主要转写语言选择系统语言区域；Fun-ASR Nano 与 Parakeet 自行识别语言，Stet 不强制指定语言。主要转写语言目前只在首次引导中设置，默认英文（待产品确认）。

**模型下载、镜像与存储**

- **FR-007**：Fun-ASR Nano 需要三个文件：编码器（f16）、Qwen3 0.6B 语言模型（Q4_K_M 量化）、FSMN 语音检测模型。它们下载到用户 Application Support 下的 `Stet/Models/Fun-ASR-Nano` 目录。已存在的文件跳过；每个文件下载成功（2xx）后才移动到目标位置，失败时删除临时文件并显示错误。
- **FR-008**：Parakeet V3 由其运行库下载到运行库的默认缓存目录；Apple Speech 的语言资源由系统下载和管理，Stet 只提供“下载 / 重试”入口并显示状态（需要 macOS 26、不可用、语言不受支持、可下载、下载中、已安装、下载失败）。
- **FR-009**：模型下载来源规则（所有从 Hugging Face 下载的模型通用，包括会议使用的说话人模型）：
  - 当地区为中国大陆，或系统时区为中国时区之一时，判定为“优先国内镜像”。
  - 优先国内镜像时，依次尝试 ModelScope（仅限已确认文件名一致的仓库）、hf-mirror、官方 Hugging Face；否则依次尝试官方、hf-mirror。
  - 同时有 GitHub 发布地址的文件：优先国内镜像时 GitHub 排在最后，否则排在最前。
  - 每次请求超时 30 秒；一个来源失败或返回非 2xx 时尝试下一个，全部失败时报告最后一个错误。
- **FR-010**：模型不随应用打包，不进入 Git。设置页为 Fun-ASR Nano 和 Parakeet 提供“在 Finder 中显示”入口；应用内不提供删除模型的入口（待产品确认）。
- **FR-011**：Stet 启动时清理已退役的本地 Whisper 模型文件；iOS 同样清理旧 Whisper 模型目录。

**预热与内存**

- **FR-012**：录音开始约 1 秒后，在后台预热所选引擎的模型；停止录音后，转写先等待预热结束再开始。预热失败不打断录音，转写时再按需加载。
- **FR-013**：已预热的模型在本次听写内复用；未预热时临时加载，转写完成后立即释放。
- **FR-014**：听写全部结束且没有后台转写进行时，释放 Fun-ASR Nano 与 Parakeet 占用的内存；下一次听写重新预热（待产品确认）。会议转写持有 Fun-ASR Nano 时，释放推迟到会议用完为止。对同一模型的推理串行执行。

**音频后处理**

- **FR-015**：后处理按最终使用的引擎区分：

  | 步骤 | Parakeet V3 / Apple Speech | Fun-ASR Nano |
  | --- | --- | --- |
  | 无语音判定 | 语音概率阈值 0.6；持续不少于 0.4 秒的语音段为有效语音；没有有效语音时按“无语音”处理，不转写 | 不做；由引擎内置的语音检测处理，结果为空时按“无语音”处理 |
  | 增益 | 以语音段 75 分位电平为准，目标 −20 dBFS；最多提升 10 dB，最多衰减 4 dB（仅在峰值超过 −1 dBFS 或语音电平高于 −14 dBFS 时衰减）；语音与噪声差小于 4 dB 时不提升，4–8 dB 之间按比例提升；峰值不超过 −1 dBFS；增益绝对值不足 0.5 dB 时不处理 | 不做 |
  | 静音裁切 | 合并语音检测与能量检测（高于噪声 10 dB）得到的不短于 0.2 秒的片段；间隔不超过 0.25 秒的片段合并；每段前后各保留 0.15 秒；段与段之间插入 0.12 秒静音；总共可去除不少于 0.35 秒时才裁切；裁切后的时长作为本次音频时长（待产品确认） | 不做 |

- **FR-016**：后处理生成的中间音频文件归本次听写所有，本次听写在任何出口结束时删除。原始录音不被修改。
- **FR-017**：Parakeet 转写时，音频不超过 14 秒（补静音后总长不超过 15 秒的单段上限）则在末尾补 1 秒静音再识别。

**热词**

- **FR-018**：Fun-ASR Nano 把个人词典提供的热词串作为识别提示；选哪些词、顺序与数量上限见『个人词典』spec。没有提供热词时不传。改写阶段如何使用词典见『改写执行』spec。
- **FR-019**：Parakeet V3 与 Apple Speech 当前不使用热词（待产品确认）。
- **FR-020**：使用 Fun-ASR Nano 完成一次听写后，Stet 在后台用同一段音频再做一次不带热词的转写，结果交给听写历史作为对照（保存方式见『听写历史与统计』spec）。下一次听写开始时取消尚未完成的对照转写；对照转写失败时静默跳过；音频在对照结束后删除（待产品确认）。

**iOS**

- **FR-021**：iOS 只有一个引擎 FunASR Realtime，由阿里云百炼的实时语音识别服务在云端转写；录音以 16 kHz PCM 流式发送。使用前用户须填写地域（北京或新加坡）、Workspace ID（只允许字母、数字和连字符）与 API Key；设置页可校验连接。
- **FR-022**：iOS 的 FunASR API Key 保存在本机钥匙串，首次解锁后可读，不经 iCloud 同步。配置不完整时听写不开始，并提示补全配置。
- **FR-023**：iOS 云端转写：任务 10 秒内未开始或停止后 15 秒内未结束即判定失败；网络过慢导致音频积压时停止本次录音。iOS 不做后处理，也不传热词（待产品确认）。

### 关键实体

- **引擎选择**：用户保存的引擎（macOS 三选一，默认 Fun-ASR Nano）。
- **模型资产**：某引擎所需的模型文件集合、存放位置与下载状态。
- **下载来源列表**：按 FR-009 为一个官方地址生成的有序候选地址。
- **后处理结果**：用于转写的音频、音频时长、需要清理的中间文件、是否判定为无语音。
- **热词**：由『个人词典』spec 规定选出的词条串。

## 成功标准 *(必填)*

### 可衡量结果

- **SC-001**：三种 macOS 引擎在模型就绪时，断网状态下听写成功率 100%。
- **SC-002**：选择 Parakeet 或 Apple Speech 但其不可用时，只要 Fun-ASR Nano 已就绪，听写成功率 100%，且保存的选择不变。
- **SC-003**：中断后重新下载 Fun-ASR Nano，只下载缺失文件，且模型目录中不出现不完整文件。
- **SC-004**：纯静音录音在 Parakeet / Apple Speech 下 100% 不进入转写。
- **SC-005**：词典超过 50 条或 400 字符时，Fun-ASR Nano 收到的热词始终不超出上限，且手动词条优先。

## 假设

- Fun-ASR Nano 在进程内运行，不依赖 Python 或外部命令行程序；只在 macOS 上链接，支持 Apple 芯片与 Intel Mac。
- Fun-ASR Nano 自带语言识别，Stet 不强制语言标记。
- 本机 Apple Speech 不需要单独的语音识别授权（见 [权限与恢复](permissions-and-recovery.md) 假设）。
- 会议转写固定使用 Fun-ASR Nano，是否跟随听写引擎由『会议转写与说话人』spec 决定。

## 待产品确认

1. **VAD 裁切改变时长**：当前对 Parakeet / Apple Speech 裁短长静音并以裁切后的时长作为音频时长；旧 004 要求保持时长。可选：保留裁切；只裁首尾；不裁切。
2. **Nano 绕过后处理**：当前 Fun-ASR Nano 不做应用层无语音判定、增益和裁切。可选：维持（依赖内置语音检测）；至少做无语音判定；与其他引擎一致。
3. **回退时是否提示**：当前听写中回退不提示，只在设置页说明。可选：维持；在胶囊或通知中提示一次。
4. **Apple Speech 语言不受支持时**：当前直接失败，不回退。可选：回退到 Fun-ASR Nano；在设置中阻止选择。
5. **模型用完即释放**：当前每次听写结束就卸载模型，下一次重新加载。可选：维持（省内存）；空闲一段时间后再卸载；常驻。
6. **Parakeet / Apple Speech 不用热词**：可选：维持；为支持的引擎接入词典。
7. **不带热词的对照转写**：当前每次 Nano 听写都额外转写一次。可选：保留（服务修正学习或评估）；改为可关闭；移除。
8. **删除模型入口**：当前只能在 Finder 中手动删除。可选：维持；在设置中提供删除。
9. **主要转写语言只在引导中设置**：可选：在设置中开放；维持。
10. **iOS 使用云端转写**：iOS 当前把录音发送到用户自己的阿里云账号，与 macOS 全本机的隐私边界不同，且无热词、无后处理。需要确认这是长期方案还是过渡。

## 与当前实现的已知差异（非规范，核对基线 `b327f54`）

- 后处理是否执行取决于“保存的引擎是否为 Fun-ASR Nano”，而不是最终使用的引擎：选择 Parakeet 但回退到 Nano 时仍会做后处理（[ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 的 `stopRecording`），与 FR-015“按最终使用的引擎区分”不一致。
- 热词同样按保存的引擎生成：选择 Parakeet 时生成的是逗号连接的全部词条且不受 FR-018 上限约束，回退到 Nano 时会把未截断的词条作为热词传入（[DictationPipelineFactory](../../StetMac/Core/DictationPipeline/DictationPipelineFactory.swift) 的 `makeTranscriptionPrompt`）。Parakeet 本身忽略热词参数（[FluidAudioTranscriptionService](../../StetMac/Core/FluidAudio/FluidAudioTranscriptionService.swift) 的 `transcribe`）。
- Parakeet 的下载在优先国内镜像时只把来源换成 hf-mirror，不回退到官方地址，与 FR-009 的多来源顺序不同（[FluidAudioModelManager](../../StetMac/Core/FluidAudio/FluidAudioModelManager.swift) 的 `configureDownloadRegistry`）。
- 无语音判定所用的语音检测出错时，异常直接抛出，本次听写按失败处理（[DefaultAudioPostProcessor](../../StetMac/Core/Audio/Processing/DefaultAudioPostProcessor.swift) 调用 [AudioSignalAnalyzer](../../StetMac/Core/Audio/Processing/AudioSignalAnalyzer.swift) 的 `analyzeForPostProcessing`）；旧 004 要求分析失败时放行原文件。
- 会议转写使用的 Fun-ASR Nano 实例在应用启动时创建一次；启动时模型未下载，之后再下载，会议转写在重启前仍不可用（[MacMeetingRecordingRuntime](../../StetMac/Core/Speech/MacMeetingRecordingRuntime.swift) 的 `live`）。
- 首次引导的引擎路由固定返回 Fun-ASR Nano，第二语言设置不影响引擎（[TranscriptionLanguageRouting](../../StetMac/Shared/Utilities/TranscriptionLanguageRouting.swift)）。
- 预热后的模型在每次听写结束即释放（[DictationProcessingLifetime](../../StetMac/Core/Speech/DictationProcessingLifetime.swift) 的 `scheduleCleanupIfIdle`），旧 009 描述的“重复听写复用已加载运行时”只在单次听写内成立。
- 不带热词的对照转写是否执行，同样取决于“保存的引擎是否为 Fun-ASR Nano”（[DictationPipelineFactory](../../StetMac/Core/DictationPipeline/DictationPipelineFactory.swift) 的 `recordsNoHotwordTranscript`）：选择 Parakeet 或 Apple Speech 但回退到 Nano 时不做对照转写，与 FR-020“使用 Fun-ASR Nano 完成一次听写后”的字面不一致。
- 引擎回退逻辑见 [LocalTranscriptionServiceFactory](../../StetMac/Core/DictationPipeline/LocalTranscriptionServiceFactory.swift)；Nano 下载与目录见 [FunASRNanoModelManager](../../StetMac/Core/FunASR/FunASRNanoModelManager.swift)；镜像规则见 [ModelDownloadMirror](../../Packages/StetEngine/Sources/StetCore/ModelDownloadMirror.swift)；热词上限见 [FunASRNanoHotwordPrompt](../../Packages/StetEngine/Sources/StetCore/FunASRNanoHotwordPrompt.swift)；iOS 云端引擎见 [FunASRRealtimeEngine](../../StetMobile/StetMobile/Core/Dictation/FunASRRealtimeEngine.swift) 与 [FunASRSettingsStore](../../StetMobile/StetMobile/Core/Settings/FunASRSettingsStore.swift)；以上与本 spec 一致。
