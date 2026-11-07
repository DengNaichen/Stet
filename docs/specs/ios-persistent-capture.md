# 功能规格：iOS 常驻麦克风与 Live Activity

**创建**：2026-11-07
**状态**：Draft（待产品确认）
**输入**：定义 Stet iOS 主 App 怎样在后台保持麦克风随时可用，以便键盘发起听写时立即开始；包括采集的准备、帧门、单消费者、内置麦克风优先、路由变化与中断后的恢复，以及常驻期间的 Live Activity。替代 010 iOS 常驻采集中仍适用的部分。

**范围**：iOS（主 App 与 Live Activity 扩展）。macOS 的输入设备选择与录音行为不受本 spec 影响。
**边界**：本 spec 拥有主 App 内音频采集资源的生命周期、输入路由策略、恢复规则、音频送往转写服务前的缓冲规则，以及表示“麦克风常驻”的 Live Activity。键盘与主 App 之间的交接、插入文本、返回引导、主 App 内的听写入口，以及 iOS 麦克风权限和“完全访问”见[iOS 键盘听写](ios-keyboard-dictation.md) spec；转写服务的选择、凭据与模型准备见[转写引擎与模型准备](transcription-engines.md) spec；转写后的改写见[改写执行](rewrite-execution.md) spec。

## 术语

- **常驻采集**：主 App 保持音频会话和音频引擎持续运行（“暖机”），即使没有听写也不关闭。
- **帧门**：常驻采集产生的音频帧只有在门打开时才交给消费者；门关闭时帧直接丢弃。
- **消费者**：当前正在接收音频帧的一次听写。
- **内置麦克风优先**：生产环境使用的输入策略，请求使用 iPhone 内置麦克风，不启用蓝牙耳机的通话麦克风。
- **系统回退**：iOS 未接受内置麦克风请求时，继续使用系统选定的输入。
- **就绪**：权限、服务配置和常驻采集都已准备好，可以立即开始听写。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 不把 AirPods 从其他设备抢回来（优先级：P1）

作为同时用 iPhone 和 Mac / iPad 的用户，我希望 Stet 在后台常驻时使用 iPhone 内置麦克风，让 AirPods 继续留在另一台设备上。

**为什么是这个优先级**：常驻采集如果启用蓝牙输入，会让 AirPods 不断切回 iPhone，严重干扰用户在其他设备上的通话和播放（待产品确认是否为硬性要求）。

**独立测试**：AirPods 连接到 Mac 并在播放；iPhone 上 Stet 已就绪并退到后台；等待两分钟并用键盘听写一次，观察 AirPods 是否仍在 Mac 上、听写是否经内置麦克风完成。

**验收场景**：

1. **Given** Stet 在后台常驻，**When** AirPods 切换到另一台设备，**Then** Stet 不启用会把 AirPods 拉回 iPhone 的蓝牙输入路由。
2. **Given** AirPods 正被其他设备使用，**When** 键盘发起听写，**Then** iOS 接受请求时使用内置麦克风录音。
3. **Given** iOS 不接受内置麦克风请求，**When** 准备采集或路由变化，**Then** 听写使用系统选定的输入继续进行，并记录为系统回退。

---

### 用户故事 2 - 路由变化不丢掉正在进行的听写（优先级：P1）

作为用户，我希望在听写过程中连接或断开耳机时，这次听写不会被丢弃。

**为什么是这个优先级**：路由变化在通勤等场景很常见，丢失一段口述的代价高。

**独立测试**：听写进行中连接或断开 AirPods，并在短时间内制造多次路由通知；确认听写继续出字且最终插入完整文本。

**验收场景**：

1. **Given** 听写进行中，**When** 输入路由发生实际变化，**Then** 重新建立采集，当前消费者保持接入，音频继续送出。
2. **Given** 多个路由通知几乎同时到达，**When** 一次恢复已在进行，**Then** 后续通知合并为最多再执行一次恢复，不形成通知循环。
3. **Given** 恢复无法建立任何可用输入，**When** 听写进行中，**Then** 本次听写以失败结束，不静默挂起。

---

### 用户故事 3 - 后台常驻并让我知道麦克风在待命（优先级：P1）

作为用户，我希望打开过一次 Stet 后，它在后台持续就绪，并通过 Live Activity 让我知道麦克风在待命。

**为什么是这个优先级**：键盘扩展本身不能录音，只能依赖主 App 在后台就绪；用户也需要明确知道麦克风处于常驻状态。

**独立测试**：启动 Stet 并授权，切到其他应用；确认锁屏和灵动岛出现 Stet 标志；从键盘发起听写，无需打开 Stet 即可开始。

**验收场景**：

1. **Given** 首次启动，**When** 权限和服务配置都满足，**Then** 常驻采集开始，Stet 进入就绪，并显示一个 Live Activity。
2. **Given** 已有 Stet 的 Live Activity，**When** Stet 再次进入就绪，**Then** 复用现有的那一个，多余的立即结束。
3. **Given** 进入失败状态，**When** 失败发生，**Then** 结束所有 Stet 的 Live Activity。
4. **Given** 用户在系统中关闭了 Stet 的实时活动，**When** Stet 进入就绪，**Then** 不显示 Live Activity，听写不受影响。

---

### 用户故事 4 - 中断后自动恢复（优先级：P2）

作为用户，我希望来电、其他应用占用音频或系统音频服务重置之后，Stet 能自己恢复就绪，而不需要我强制退出重开。

**独立测试**：在空闲和听写中分别制造音频中断与媒体服务重置，然后回到 Stet，确认能再次就绪。

**验收场景**：

1. **Given** Stet 空闲，**When** 音频中断结束或媒体服务重置，**Then** Stet 重新准备采集并回到就绪。
2. **Given** 听写进行中，**When** 音频中断结束或媒体服务重置，**Then** 本次听写以失败结束（提示请重试），Stet 进入失败状态并结束 Live Activity；回到前台后按场景 3 重新准备并再次就绪。
3. **Given** Stet 处于失败状态，**When** 我把 Stet 切回前台，**Then** 从权限检查开始重新准备。

### 边界情况

- 开始听写时，与转写服务的连接建立之前的音频不会被录入；帧门在连接建立后才打开。
- 网络慢导致待发送音频积压超过 5 秒：本次听写以失败结束，不悄悄丢弃中间音频。
- 停止后 15 秒内没有收到转写服务的结束确认：本次听写以失败结束。
- 开始听写的连接过程中 App 被系统挂起：连接在后台任务时限到达时关闭，本次听写失败。
- 第二个消费者试图在已有消费者时打开帧门：被拒绝。
- 服务凭据缺失或无效：不开始常驻采集，进入失败状态。
- 只有类别变化、覆盖设置、路由配置变化这三类路由通知不触发恢复。

## 需求 *(必填)*

### 生命周期

- **FR-001**：主 App 启动后必须依次完成：麦克风权限（规则见[iOS 键盘听写](ios-keyboard-dictation.md) spec）、转写服务配置校验（见[转写引擎与模型准备](transcription-engines.md) spec）、常驻采集准备；全部成功才进入就绪。任一步失败进入失败状态。
- **FR-002**：就绪后音频引擎持续运行，不因没有听写而停止。开始和停止听写只开关帧门，不重建音频引擎。
- **FR-003**：主 App 必须声明后台音频能力，使常驻采集在 App 退到后台后继续运行。
- **FR-004**：主 App 回到前台时：处于失败状态则从 FR-001 第一步重新准备；处于空闲则重新准备采集并回到就绪；有听写进行中则不做处理。
- **FR-005**：关闭常驻采集时必须停止音频引擎、移除采集、关闭帧门，并以“通知其他应用可以恢复播放”的方式释放音频会话。

### 帧门与单消费者

- **FR-006**：常驻采集输出 16 kHz 单声道浮点音频帧，每帧附带归一化到 0–1 的音量。
- **FR-007**：同一时刻最多只有一个消费者；已有消费者时再次打开帧门必须失败。
- **FR-008**：帧门关闭时不得把任何音频帧交给转写服务。
- **FR-009**：开始听写时先与转写服务建立会话，成功后才打开帧门；建立会话期间申请后台执行时间，时限到达即放弃本次连接。
- **FR-010**：送往转写服务前音频转为 16 位 PCM 并分包排队；排队上限为约 5 秒音频，超出即判定本次听写失败。
- **FR-011**：停止听写时关闭帧门，送出剩余音频并请求结束；15 秒内未收到结束确认即判定失败。
- **FR-012**：听写进行中的实时音量必须提供给键盘扩展用于显示；规则的使用方见[iOS 键盘听写](ios-keyboard-dictation.md) spec。

### 输入路由

- **FR-013**：生产环境只使用“内置麦克风优先”策略：录音与播放类别、默认模式、允许与其他音频混合、允许蓝牙高品质播放输出，不启用任何蓝牙输入（待产品确认是否为硬性要求）。
- **FR-014**：激活音频会话后请求内置麦克风作为输入，并读取实际路由判定结果为“首选输入生效”或“系统回退”。
- **FR-015**：系统回退不得阻止采集或听写。
- **FR-016**：保留“AirPods 高品质录音”策略（启用蓝牙通话输入，iOS 26 及以上同时启用高品质录音）供将来显式选用；当前生产组合不得使用它，也不提供切换界面。
- **FR-017**：收到实际路由变化通知时，必须重新应用策略并重建采集，保持当前消费者接入；恢复进行中再到达的通知合并为最多一次补充恢复。
- **FR-018**：恢复失败时向当前消费者报告“音频不可用”，使本次听写失败。
- **FR-019**：每次准备、重建和恢复都必须记录：策略、请求的输入、实际输入、判定结果（首选生效 / 系统回退）和恢复结果；日志不得包含音频或转写内容。

### 中断

- **FR-020**：音频中断结束或媒体服务重置时：有听写进行中则以失败结束本次听写；没有则重新准备采集。媒体服务重置后必须重建音频引擎而不是复用旧引擎。

### Live Activity

- **FR-021**：每次进入就绪时确保恰好存在一个 Stet 的 Live Activity：已有则复用并结束多余的，没有则新建。
- **FR-022**：Live Activity 只显示 Stet 标志，表示“麦克风常驻待命”；锁屏与灵动岛（紧凑、最小、展开）均显示同一标志，不显示转写内容或听写进度。
- **FR-023**：进入失败状态时立即结束所有 Stet 的 Live Activity；听写成功完成不结束它。
- **FR-024**：用户关闭实时活动或创建失败时，只记录日志，不影响就绪状态和听写。

### 关键实体

- **常驻采集**：输入策略、运行状态、当前消费者、恢复状态。
- **输入路由判定**：首选输入生效，或系统回退（附实际输入类型）。
- **音频帧**：16 kHz 单声道样本与音量。
- **麦克风 Live Activity**：是否处于常驻状态。

## 成功标准 *(必填)*

- **SC-001**：Stet 在后台常驻时，正被其他设备使用的 AirPods 至少两分钟内保持在那台设备上（待产品确认）。
- **SC-002**：AirPods 被其他设备占用时，键盘听写能经 iPhone 内置麦克风完成。
- **SC-003**：听写进行中连接或断开 AirPods，听写继续产生文本并最终完整插入。
- **SC-004**：从键盘发起听写到开始录音，不需要用户打开主 App（主 App 已就绪时）。
- **SC-005**：日志可以区分每次准备 / 恢复的策略、请求输入、实际输入、判定结果和恢复结果。
- **SC-006**：任一时刻 Stet 的 Live Activity 最多一个。

## 假设

- 请求内置麦克风只是向 iOS 提出偏好，不保证物理设备绑定。
- 不把采集迁移到相机采集接口；物理输入仍由音频路由决定。
- 不提供麦克风选择设置或其他额外界面。
- SenseVoice、Whisper 等旧的本地识别器已移除，不在本 spec 范围；旧 010 中“两个识别器共享采集”的前提不再成立。

## 待产品确认

1. **AirPods 与“不抢麦”是否为硬性要求**（对应 index 同名事项）：当前用内置麦克风优先策略并以两分钟不回切为目标，但未在真机验收。可选：确认为硬性要求并纳入发布验收；降为尽力而为。
2. **iOS 转写在云端而非本机**：当前 iOS 唯一的转写服务是阿里云 FunASR 实时服务，音频实时上传；而麦克风用途说明写的是“私密的本机转写”。可选：改为本机模型；保留云端并修正用途说明与隐私说明。（服务选择归[转写引擎与模型准备](transcription-engines.md) spec，此处只确认常驻采集是否需要配合本机模型的准备流程。）
3. **常驻期间麦克风持续开启**：就绪后音频引擎一直运行，系统会持续显示麦克风使用指示。可选：保持；空闲一段时间后停止常驻并在下次听写时重新唤起。
4. **听写中断即失败**：音频中断结束或媒体服务重置时，进行中的听写直接失败，已录的部分丢弃。可选：保留已转写部分并插入；保持失败。
5. **配置补全后不自动重试**：服务凭据缺失导致失败后，用户在设置里填好凭据，要等 App 下次回到前台才重新准备。可选：保存凭据后立即重新准备；保持现状。

## 与当前实现的已知差异（非规范，供评审）

以下只记录 2026-11-07（基线 `b327f54`）核对时的代码状态，不代表产品决定。

- 生产组合只构造“内置麦克风优先”并注入唯一引擎 FunASR Realtime（[StetMobileApp](../../StetMobile/StetMobile/App/StetMobileApp.swift) 的 `StetMobileComposition`）；策略、帧门、恢复合并见 [ASRAudioCapture](../../Packages/StetEngine/Sources/StetASR/ASRAudioCapture.swift)。
- iOS 没有本地模型：转写通过 WebSocket 连到阿里云（[FunASRSettingsStore](../../StetMobile/StetMobile/Core/Settings/FunASRSettingsStore.swift) 的 `FunASRConfiguration.endpoint`），启动时还会删除旧的 Whisper 模型目录（[LocalDictationModelManager](../../StetMobile/StetMobile/Core/Settings/LocalDictationModelManager.swift) 的 `RetiredDictationModelCleanup`）。任务说明中的“本地模型准备”在 iOS 当前不存在。
- 麦克风用途说明为 “Record microphone audio for private, on-device transcription.”（[StetMobile project.pbxproj](../../StetMobile/StetMobile.xcodeproj/project.pbxproj) 的 `INFOPLIST_KEY_NSMicrophoneUsageDescription`），与实际上传云端不符；设置页脚注写明音频发送至阿里云。
- 启动顺序（权限 → 资源 → 引擎准备，引擎准备会先校验凭据）与中断处理在 [DictationSessionCoordinator](../../StetMobile/StetMobile/Core/Dictation/DictationSessionCoordinator.swift) 的 `bootstrap`、`registerAudioSessionObservers`、`handleAudioSessionInvalidation`；只监听中断“结束”，不处理中断“开始”。
- 连接先于帧门、5 秒排队上限与 15 秒结束超时见 [FunASRRealtimeEngine](../../StetMobile/StetMobile/Core/Dictation/FunASRRealtimeEngine.swift) 的 `start`、`startFinishTimeout` 与 [FunASRAudioCapture](../../StetMobile/StetMobile/Core/Dictation/FunASRAudioCapture.swift) 的 `FunASRAudioFrameQueue`。
- Live Activity 的复用、去重与结束见 [MicrophoneLiveActivityManager](../../StetMobile/StetMobile/Core/LiveActivity/MicrophoneLiveActivityManager.swift)，显示内容见 [StetMicrophoneLiveActivityWidget](../../StetMobile/StetLiveActivity/StetMicrophoneLiveActivityWidget.swift)；触发点在 [SenseVoiceViewModel](../../StetMobile/StetMobile/Features/Dictation/ViewModels/SenseVoiceViewModel.swift) 的 `.ready` 与 `.failed` 分支。`SenseVoice` 只是遗留类型名，不代表 SenseVoice 引擎仍在。
- 保存凭据后不会触发重新准备（[RewriteSettingsViewModel](../../StetMobile/StetMobile/Features/Settings/ViewModels/RewriteSettingsViewModel.swift) 的 `saveFunASRAPIKey` 未通知听写协调器），只能等 [StetMobileApp](../../StetMobile/StetMobile/App/StetMobileApp.swift) 在回到前台时调用 `ensureMicAlive`。
- 旧 010 的 AirPods 两分钟、真机路由变化等成功标准从未在真机验收，当前只有单元测试覆盖策略、帧门与恢复合并。
