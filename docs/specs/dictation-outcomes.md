# 功能规格：听写结果与失败处理

**创建**：2026-11-07
**状态**：Draft（待产品确认）
**输入**：用一张结果矩阵统一定义一次听写在各种结束方式下，用户看到什么、文本和音频保留还是清理、是否记入历史。
**替代**：旧 spec「004 音频后处理」中的无语音处理、「005 转写详情」中的失败处理、「006 文本输出」中失败结果的用户可见部分。

**范围**：macOS 为主；iOS 只在 FR-012 至 FR-014 单列平台独有的结果。
**边界**：本 spec 拥有“一次听写以什么结果结束、用户看到什么、保留什么”。其他规则只引用：改写失败或缺 key 时回退原文的规则由[改写执行](rewrite-execution.md) spec 拥有，本 spec 只写该情况下用户看到的结果；粘贴、剪贴板兜底、“待复制”状态与乐观完成见[文本交付](text-delivery.md) spec；无语音的判定条件与各引擎的后处理见[转写引擎与模型准备](transcription-engines.md) spec；历史记录保存哪些字段见[听写历史与统计](dictation-history-and-stats.md) spec；录音、取消入口与会话状态机见[macOS 听写会话](macos-dictation-session.md) spec；权限缺失导致不能开始见 [权限与恢复](permissions-and-recovery.md)；iOS 键盘上的呈现见[iOS 键盘听写](ios-keyboard-dictation.md) spec。

## 术语

- **结果**：一次听写结束时的去向，分为：交付成功、待复制、静默结束、失败提示。
- **静默结束**：不显示错误，听写回到“就绪”，胶囊自动收起。
- **失败提示**：胶囊切换为错误面板，显示简短文案和“关闭”按钮，直到用户关闭或再次触发听写。
- **临时音频**：本次录音文件及后处理生成的中间文件。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 没说话时不打扰（优先级：P1）

作为用户，我误触快捷键或录音里没有说话时，希望 Stet 安静地结束，不粘贴任何内容，也不弹出错误。

**为什么是这个优先级**：误触和空录音很常见，把它们当错误处理会频繁打扰用户。

**独立测试**：分别做三次听写：立即停止（几乎无音频）、录一段静音、录一段引擎转不出文字的噪声；确认三次都静默回到就绪，没有粘贴、没有错误面板、没有历史记录。

**验收场景**：

1. **Given** 开始录音后立即停止，录音不足 0.1 秒或没有写入任何音频，**When** 录音结束，**Then** 静默结束。
2. **Given** 录音中没有有效语音，**When** 处理结束，**Then** 静默结束，不调用改写服务。
3. **Given** 引擎返回空文字，**When** 处理结束，**Then** 静默结束。

---

### 用户故事 2 - 转写失败时明确告知（优先级：P1）

作为用户，转写出错时我希望看到失败提示，而不是什么都没发生，也不希望错误文字被粘贴出去。

**为什么是这个优先级**：静默丢失一段真实的口述，用户无法察觉也无法补救。

**独立测试**：让引擎在转写时抛出错误，确认出现错误面板、目标应用未收到任何文本、历史中没有记录。

**验收场景**：

1. **Given** 录音中有语音，**When** 转写出错，**Then** 显示失败提示，不粘贴，不调用改写。
2. **Given** 所需模型未下载导致听写无法开始，**When** 我触发听写，**Then** 不录音并显示失败提示。
3. **Given** 错误面板正在显示，**When** 我再次触发听写，**Then** 开始新的听写。

---

### 用户故事 3 - 改写失败时仍拿到原文（优先级：P1）

作为用户，改写服务出错、超时或没有配置密钥时，我仍希望拿到转写原文，而不是整次听写失败。

**为什么是这个优先级**：转写已经成功，丢弃它会让用户重说一遍。

**独立测试**：开启改写但删除密钥，或让改写服务返回错误，确认原文被交付，且不显示错误。

**验收场景**：

1. **Given** 改写开启但服务失败，**When** 处理结束，**Then** 交付转写原文，界面与正常完成相同（待产品确认）。
2. **Given** 改写开启但未配置密钥，**When** 处理结束，**Then** 交付转写原文。

---

### 用户故事 4 - 取消后不留痕迹（优先级：P2）

作为用户，我在录音或处理中途取消，希望不交付任何文字、不留下录音和记录。

**独立测试**：分别在录音中和处理中点击胶囊取消，确认回到就绪、目标应用未收到文本、临时音频被删除、历史无新增。

**验收场景**：

1. **Given** 正在录音，**When** 我取消，**Then** 停止录音并静默结束。
2. **Given** 正在转写或改写，**When** 我取消，**Then** 处理被中止，已得到的中间文本被丢弃，静默结束。

### 边界情况

- 改写后的文本经整理后为空：按“引擎返回空文字”静默结束。
- 交付阶段收到空文本：本应在前面的阶段被拦截；如果发生，显示失败提示（见已知差异）。
- 转写成功、交付失败：历史已经记录，交付结果按[文本交付](text-delivery.md) spec 处理。
- 处理中再次按快捷键或点击主按钮：忽略，不中断处理（入口规则见[macOS 听写会话](macos-dictation-session.md) spec）。
- 不带热词的对照转写（见[转写引擎与模型准备](transcription-engines.md) spec FR-020）失败：不影响本次结果，不提示。

## 需求 *(必填)*

### 功能需求

- **FR-001**：macOS 每次听写必须以下表中的一种结果结束：

  | 情况 | 用户看到的结果 | 文本 | 临时音频 | 听写历史 |
  | --- | --- | --- | --- | --- |
  | 必需权限缺失、无法开始 | 见 [权限与恢复](permissions-and-recovery.md) | — | 未产生 | 不记录 |
  | 无法开始（模型未就绪、引擎或麦克风启动失败） | 失败提示 | — | 未产生或立即删除 | 不记录 |
  | 未写入音频（无音频帧、时长不足 0.1 秒或文件过小） | 静默结束 | — | 删除 | 不记录 |
  | 无语音（后处理判定，仅适用的引擎） | 静默结束 | — | 删除 | 不记录 |
  | 引擎返回空文字 | 静默结束 | — | 删除 | 不记录 |
  | 转写失败（引擎错误、模型加载失败、语音检测出错） | 失败提示 | 无 | 删除（待产品确认） | 不记录 |
  | 改写失败、超时或缺少密钥 | 与交付成功相同，不提示（待产品确认） | 转写原文，规则见[改写执行](rewrite-execution.md) spec | 删除 | 记录原文，标为未改写 |
  | 改写或整理后文本为空 | 静默结束 | — | 删除 | 不记录 |
  | 交付成功 | 胶囊收起，可选完成提示音 | 已送入目标应用 | 删除 | 记录 |
  | 交付未确认或缺输入控制 | “待复制”，见[文本交付](text-delivery.md) spec | 保留在剪贴板 | 删除 | 记录 |
  | 剪贴板写入失败 | 失败提示 | 未送达，仅存于历史 | 删除 | 记录 |
  | 录音或处理中取消 | 静默结束 | 丢弃 | 删除 | 不记录 |

- **FR-002**：无语音、未写入音频、空文字三种情况对用户的表现必须一致：不显示错误，不粘贴，不写剪贴板，不调用改写服务。
- **FR-003**：失败提示只显示简短的通用文案“Something went wrong.”，不显示技术细节；服务返回额度不足（HTTP 402）时显示“Monthly quota reached.”（待产品确认）。失败提示不自动消失，用户点击“关闭”或再次触发听写时结束。
- **FR-004**：转写失败时不得调用改写，也不得交付任何文本。
- **FR-005**：改写阶段的任何失败都不得让整次听写失败；回退规则见[改写执行](rewrite-execution.md) spec。改写回退时不向用户提示（待产品确认）。
- **FR-006**：听写历史只在转写成功、得到非空最终文本后记录，且在交付之前记录；之后交付成功与否不改变是否记录（字段含义见[听写历史与统计](dictation-history-and-stats.md) spec）。
- **FR-007**：临时音频在本次听写的每一种结束方式下都必须删除；唯一例外是交给不带热词对照转写的那份音频，在对照转写结束或被取消后删除。
- **FR-008**：取消在录音和处理阶段都必须生效：停止录音或中止转写 / 改写，丢弃中间文本，不交付、不记录。取消不是失败，不显示失败提示。
- **FR-009**：已进入交付阶段后，结果由[文本交付](text-delivery.md) spec 决定；本 spec 只要求剪贴板写入失败时显示失败提示。
- **FR-010**：一次听写结束后，下一次听写可以从任何结果状态直接开始（包括失败提示和“待复制”）；“待复制”状态下开始新听写前，先按[文本交付](text-delivery.md) spec 处理待复制文本。
- **FR-011**：引擎回退到 Fun-ASR Nano 不算失败，结果按实际转写结果判定。

### iOS 结果

- **FR-012**：iOS 云端转写在开始、传输或结束阶段失败时，本次听写以失败结束，记录失败原因，不插入文本；具体文案来自转写服务的错误（配置不完整、鉴权失败、网络断开、启动或结束超时、音频积压等），呈现方式见[iOS 键盘听写](ios-keyboard-dictation.md) spec。
- **FR-013**：iOS 转写结果为空时，本次以“完成”结束，最终文本为空，不调用改写（待产品确认）。
- **FR-014**：iOS 改写失败时交付原文（规则见[改写执行](rewrite-execution.md) spec）；改写进行中取消，丢弃改写结果。

### 关键实体

- **听写结果**：交付成功、待复制、静默结束、失败提示之一。
- **失败原因**：内部分类（权限、配置、鉴权、网络、无语音、输出、服务、状态、未知），用于日志和诊断，不直接展示给用户。
- **临时音频**：本次听写拥有的录音与中间文件，随结果统一清理。

## 成功标准 *(必填)*

### 可衡量结果

- **SC-001**：空录音、静音录音和空转写三类情况，100% 静默结束且无粘贴。
- **SC-002**：转写失败时 100% 出现失败提示，且目标应用不收到任何文本。
- **SC-003**：改写服务不可用时，有语音的听写 100% 交付转写原文。
- **SC-004**：任何结果结束后，系统临时目录中不残留本次听写的音频（对照转写的音频在其结束后清理）。
- **SC-005**：取消后历史记录数不变。

## 假设

- “静默结束”的判定条件（0.1 秒、无语音阈值等）由各自的负责 spec 定义，本 spec 只规定表现。
- 失败提示的视觉样式归[听写指示器与外观](dictation-indicator.md) spec。
- 被动监听已移除，不产生任何听写结果，不在范围内。

## 待产品确认

1. **转写失败时丢弃录音**：当前转写失败后录音立即删除，用户只能重说。可选：维持；保留最近一次失败的录音并提供“重试”；保留到下一次听写开始。
2. **失败文案过于笼统**：当前所有失败都只显示“Something went wrong.”。可选：维持；按分类显示（模型未下载、引擎错误等）并给出处理入口（如“去下载模型”）。
3. **改写回退是否提示**：当前改写失败或缺 key 时完全无提示，用户可能以为改写生效。可选：维持；胶囊中短暂标注“未改写”；在设置或历史中标注。
4. **无语音是否提示**：当前完全静默。可选：维持；短暂显示“未检测到语音”（失败分类中已有该文案）。
5. **iOS 空结果**：当前以空文本“完成”结束。可选：与 macOS 一致的静默结束；显示“未检测到语音”。

## 与当前实现的已知差异（非规范，核对基线 `b327f54`）

- 额度不足的专用文案只对服务商 HTTP 402 生效，而服务商错误目前只可能来自改写阶段，改写错误又总是回退原文，因此该文案在当前流程中无法出现（[DictationFailure](../../StetMac/Core/Dictation/DictationFailure.swift) 的 `isInsufficientFunds`；回退见 [ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 的 `stopRecording`）。
- 交付阶段收到空文本时，工作流返回“无语音”失败并显示失败提示，而前面阶段的“无语音”是静默结束，两处表现不一致（[MacDictationWorkflowController](../../StetMac/App/Workflows/MacDictationWorkflowController.swift) 的 `handleCompletedResult`；静默处理见 [DictationViewModel](../../StetMac/Features/Dictation/DictationViewModel.swift) 的 `stopCapture`）。正常流程中空文本已被拦截。
- 失败分类中仍保留“缺少服务商配置”“不支持的转写 / 改写组合”等旧远程转写时代的失败类型，以及“正在用 X 转写并改写”的处理文案；当前流程不会产生前两者，处理文案按已废弃的转写服务商取名（[DictationFailure](../../StetMac/Core/Dictation/DictationFailure.swift)、[MacDictationWorkflowController](../../StetMac/App/Workflows/MacDictationWorkflowController.swift) 的 `processingStatusText`、[DictationExecutionRoute](../../StetMac/Core/DictationPipeline/DictationExecutionRoute.swift)）。
- 错误面板只显示通用文案，详细原因只出现在其他界面的状态文字中（[MacDictationErrorSurface](../../StetMac/Features/MacShell/DictationPanel/MacDictationErrorSurface.swift)、[MacDictationPanelView](../../StetMac/Features/MacShell/DictationPanel/MacDictationPanelView.swift)）。
- 未写入音频与时长不足的判定见 [MacAudioCaptureService](../../StetMac/Core/Speech/MacAudioCaptureService.swift) 的 `stopRecording`；临时音频统一清理见 [DictationProcessingLifetime](../../StetMac/Core/Speech/DictationProcessingLifetime.swift)；历史在交付前记录见 [DictationViewModel](../../StetMac/Features/Dictation/DictationViewModel.swift) 的 `stopCapture`；结果到界面的映射见 [MacAppSessionController+Dictation](../../StetMac/App/Workflows/MacAppSessionController+Dictation.swift) 的 `handleResultLifecycle`；以上与本 spec 一致。
- iOS 的失败与空结果处理见 [DictationSessionCoordinator](../../StetMobile/StetMobile/Core/Dictation/DictationSessionCoordinator.swift) 的 `finalize` 与 `fail`，与 FR-012 至 FR-014 一致。
