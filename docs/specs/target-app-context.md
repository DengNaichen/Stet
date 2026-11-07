# 功能规格：目标应用上下文

**创建**：2026-11-07
**状态**：Draft（待产品确认）
**输入**：定义听写期间 Stet 怎样确定“用户正在为哪个应用输入”，以及这个上下文交给哪些功能使用。吸收 旧 spec「007 App Branch」 中仍适用的意图；旧文档中的 `.kiro`、Constitution、branch plan 流程和 API 细节不再作为约束。

**范围**：macOS。iOS 不识别目标应用：主 App 改写固定按“面向人”处理，也不提供应用名称；键盘内插入由 iOS 键盘听写 spec 负责。
**边界**：本 spec 拥有“目标应用是谁、怎样排除 Stet 自身、怎样记住最近的外部应用、audience 怎样分类、哪些功能消费这个上下文”。粘贴、激活目标应用和完成判定见[文本交付](text-delivery.md) spec；改写提示词怎样使用 audience 和应用名称见[改写执行](rewrite-execution.md) spec；历史记录怎样保存目标应用见[听写历史与统计](dictation-history-and-stats.md) spec。

## 术语

- **目标应用**：一次听写的文本最终要交付到的外部应用。
- **外部应用**：除 Stet 自身之外、带有 Bundle ID 的应用。
- **最近外部应用**：在 Stet 成为前台之前，用户最后一次停留的外部应用。
- **audience**：对目标应用的粗分类，只有两个取值：“面向 AI / 编程工具”和“面向人”。
- **改写上下文**：交给改写的 audience 和应用名称。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 文本送回我开始听写时所在的应用（优先级：P1）

作为用户，我在某个应用里按下快捷键开始听写，之后即使焦点发生变化，我也希望文字回到我开始听写时所在的应用。

**为什么是这个优先级**：目标应用错了，文字就会送错地方，这是听写最直接的失败。

**独立测试**：在文本编辑器里开始听写，录音中切到另一个应用，结束后确认 Stet 先把编辑器带回前台再交付文本。

**验收场景**：

1. **Given** 前台是外部应用 A，**When** 我开始听写，**Then** A 被记为本次听写的目标应用。
2. **Given** 本次目标应用是 A，**When** 我在录音或处理期间切到应用 B，**Then** 交付仍以 A 为目标。
3. **Given** 本次目标应用是 A，**When** 听写完成，**Then** 历史记录与统计中的目标应用为 A。

---

### 用户故事 2 - 从 Stet 自己的界面开始听写时不把 Stet 当目标（优先级：P1）

作为用户，我从 Stet 的主窗口或菜单开始听写时，希望文字不被送进 Stet 自身。

**为什么是这个优先级**：Stet 自身不是输入目的地；把它当目标会让交付和学习都落空。

**独立测试**：先在外部应用 A 中完成一次听写，再切到 Stet 主窗口开始听写，确认目标仍是外部应用。

**验收场景**：

1. **Given** 前台是 Stet，且之前已有一次听写的目标应用 A，**When** 我开始听写，**Then** 目标应用仍为 A（待产品确认，见 FR-004）。
2. **Given** 前台是 Stet，且本次运行中从未记录过目标应用，**When** 我开始听写，**Then** 本次没有目标应用，交付按[文本交付](text-delivery.md) spec 对“无目标应用”的规则处理。
3. **Given** 首次引导停在“首次成功”步骤，**When** 我在 Stet 的引导窗口中开始听写，**Then** Stet 允许以自身为目标，使引导内的输入框能收到文字。

---

### 用户故事 3 - 改写风格跟随目标应用的类型（优先级：P2）

作为用户，我在 AI 或编程工具里听写时，希望改写结果适合粘贴给这些工具；在普通聊天或文档应用里，希望结果适合给人阅读。

**为什么是这个优先级**：只影响改写风格，不影响文本能否送达。

**独立测试**：分别在名单内的编程工具和名单外的普通应用中开启改写并听写，确认改写收到的 audience 不同，且应用名称被一并提供。

**验收场景**：

1. **Given** 当前外部应用的 Bundle ID 或名称包含 FR-008 名单中的片段，**When** 改写执行，**Then** audience 为“面向 AI / 编程工具”。
2. **Given** 当前外部应用不匹配名单，**When** 改写执行，**Then** audience 为“面向人”。
3. **Given** 无法确定任何外部应用，**When** 改写执行，**Then** audience 为“面向 AI / 编程工具”，且不提供应用名称（待产品确认）。

### 边界情况

- 系统没有前台应用：目标应用沿用上一次的记录或为空；最近外部应用跟踪不产生新的上下文。
- 前台应用没有 Bundle ID：最近外部应用跟踪视同无法识别、不产生新的上下文；开始听写时的目标应用读取不检查 Bundle ID（见“与当前实现的已知差异”）。
- 前台应用没有本地化名称：最近外部应用跟踪用 Bundle ID 作为显示名称；目标应用的名称则为空。
- 只经过 Stet、没有其他外部应用的情况下启动：最近外部应用为空。
- 目标应用在处理期间退出：目标应用记录不变，交付时的处理见[文本交付](text-delivery.md) spec。
- 快速连续切换应用：以每次切换后实际的前台应用为准，不要求保留中间状态。
- 目标应用上下文只保存在内存中，退出 Stet 后不保留。

## 需求 *(必填)*

### 功能需求

**目标应用的确定**

- **FR-001**：每次开始听写时，Stet 必须读取当时的前台应用；它是外部应用时，记为本次听写的目标应用。
- **FR-002**：本次听写的目标应用一经确定，在录音、处理和交付期间不得因用户切换应用而改变。
- **FR-003**：Stet 自身（以当前运行版本的 Bundle ID 判断）不得成为目标应用；唯一例外是首次引导的“首次成功”步骤，此时允许以 Stet 自身为目标。
- **FR-004**：开始听写时前台是 Stet，目标应用沿用上一次听写记录的目标应用；本次运行中尚无记录时，本次没有目标应用。（待产品确认：沿用的是“上一次听写的目标”，而不是“最近外部应用”。）
- **FR-005**：前台应用没有 Bundle ID 时，视同无法识别，不更新目标应用。（当前实现只在最近外部应用跟踪中如此，目标应用的读取不检查 Bundle ID，见“与当前实现的已知差异”。）

**最近外部应用**

- **FR-006**：Stet 运行期间必须持续跟踪前台应用的切换，记住最近外部应用；Stet 自身成为前台时，当前上下文回退为最近外部应用，没有时为空。
- **FR-007**：最近外部应用与目标应用都不得跨 Stet 重启持久化。

**audience 分类**

- **FR-008**：audience 按 Bundle ID 与应用名称做不区分大小写、去除首尾空白的子串匹配。任一字段包含以下片段之一即为“面向 AI / 编程工具”，否则为“面向人”：android studio、androidstudio、android.studio、aider、antigravity、augment、bolt、chatgpt、claude、claude code、cline、clion、codex、codeium、continue、gemini、copilot、cursor、fleet、goland、intellij、kiro、perplexity、phpstorm、poe、pycharm、replit、roo code、roocode、rider、trae、vscode、vscode insiders、visual studio code、warp、webstorm、windsurf、xcode、zed。（名单为当前值，待产品确认维护方式。）
- **FR-009**：audience 只用于改写风格，不得影响目标应用的确定、交付方式或完成判定。

**消费方**

- **FR-010**：目标应用上下文的消费方和各自取用的值如下；新增消费方必须先在本表登记。

  | 消费方 | 取用的值 | 取值时机 |
  | --- | --- | --- |
  | 文本交付（激活目标、兼容名单匹配） | 本次听写的目标应用 | 开始听写时确定（FR-001～FR-004） |
  | 修正学习 | 本次听写的目标应用 | 同上 |
  | 听写历史与统计 | 目标应用的 Bundle ID 与名称 | 同上 |
  | 改写执行 | audience 与应用名称 | 改写开始时的当前上下文（FR-006）（待产品确认） |

- **FR-011**：改写开启时，应用名称会随改写请求发送给用户选定的改写服务；这是本 spec 唯一的对外数据去向。改写关闭时不发送。
- **FR-012**：无法确定任何外部应用时，改写收到的 audience 为“面向 AI / 编程工具”，不附应用名称。（待产品确认）

### 关键实体

- **应用快照**：Bundle ID、显示名称、进程标识，以及是否为 Stet 自身；只存在于内存。
- **本次目标应用**：开始听写时确定、供交付、学习、历史使用的应用快照。
- **最近外部应用**：前台跟踪得到的最后一个非 Stet 外部应用。
- **audience**：“面向 AI / 编程工具”或“面向人”。
- **audience 名单**：FR-008 中的名称片段集合，随应用版本发布。

## 成功标准 *(必填)*

### 可衡量结果

- **SC-001**：从外部应用开始的听写，100% 以该应用为目标应用，录音中切换应用不改变目标。
- **SC-002**：在引导“首次成功”步骤之外，Stet 自身被记为目标应用的次数为 0。
- **SC-003**：FR-008 名单中的每个片段都能被识别为“面向 AI / 编程工具”，名单外的应用均为“面向人”。
- **SC-004**：重启 Stet 后，不残留上一次运行的目标应用或最近外部应用。

## 假设

- 前台应用的切换可以通过系统的应用激活事件实时获得，不需要轮询。
- audience 是启发式分类，误判只影响改写风格，可以接受。
- 被动监听等已移除能力不在本 spec 范围内，不需要目标应用上下文。

## 待产品确认

1. **从 Stet 界面开始听写时的目标**：当前沿用上一次听写的目标（FR-004）。如果用户之后去过另一个外部应用但没有听写，文字仍回到更早的那个应用。可选方向：改为最近外部应用；保持现状；或此时不设目标、只复制到剪贴板。
2. **改写上下文的取值时机**：当前在改写开始时读取当前上下文（FR-010），与开始听写时确定的目标应用可能不是同一个应用。可选方向：改写也使用本次目标应用；保持现状。
3. **无外部应用时的默认 audience**：当前为“面向 AI / 编程工具”，而改写服务在完全没有 audience 时默认“面向人”。可选方向：统一为“面向人”；统一为“面向 AI / 编程工具”。
4. **audience 名单的范围和维护方式**：名单含 Xcode、JetBrains 系列、Warp 等 IDE 和终端，也含 poe、bolt、continue、rider 等容易与其他应用名称子串冲突的短片段；名单只能随应用版本更新。可选方向：保持；改为精确 Bundle ID；改为像应用兼容名单那样远程分发。

## 与当前实现的已知差异（非规范，供评审）

以下只记录核对基线 `b327f54` 的代码状态，不代表产品决定。

- 目标应用和改写上下文来自两套独立的状态：目标应用由 [MacDictationWorkflowController](../../StetMac/App/Workflows/MacDictationWorkflowController.swift) 的 `refreshTargetApplication` 在开始听写时直接读取前台应用；改写上下文由 [ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 在改写时读取 [AppBranchMonitor](../../StetMac/Core/AppBranch/AppBranchMonitor.swift) 的 `currentApp`。两者可能指向不同应用（待产品确认 2）。
- `refreshTargetApplication` 只检查前台应用是否存在、是否为 Stet 自身，不检查 Bundle ID：前台应用没有 Bundle ID 时，目标应用会被更新为 Bundle ID 为空的应用，名称取其本地化名称、不回退到 Bundle ID（与 FR-005 不符）。
- `refreshTargetApplication` 遇到前台是 Stet 时直接返回，保留上一次听写的目标；它不使用 AppBranchMonitor 记住的最近外部应用（待产品确认 1）。
- 无外部应用时 [ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 默认 audience 为 AI，而 [TextRewriteService](../../Packages/StetEngine/Sources/StetRewrite/TextRewriteService.swift) 的 `PreparedCloudRewritePayload` 在请求未带 audience 时默认 human（待产品确认 3）。
- Apple Intelligence 改写只使用应用名称，不读取 audience（[AppleIntelligenceRewriteService](../../StetMac/Core/Rewrite/AppleIntelligenceRewriteService.swift)）；audience 对该服务没有效果。
- 两种 audience 的云端改写提示词差别很小，都写有“适合粘贴到 AI 或编程工具”，主要区别在换行规则（[TextRewriteService](../../Packages/StetEngine/Sources/StetRewrite/TextRewriteService.swift) 的 `baseSystemPrompt`）。提示词内容归[改写执行](rewrite-execution.md) spec。
- 听写面板的视图模型会发布当前检测到的目标应用（[MacDictationPanelViewModel](../../StetMac/Features/MacShell/DictationPanel/MacDictationPanelViewModel.swift)），但没有任何视图显示它。
- audience 名单写死在 [AppAudienceResolver](../../StetMac/Core/AppBranch/AppAudience.swift)，与远程分发的应用兼容名单互不相关。
- iOS 主 App 改写固定传 human、不传应用名称（[TranscriptPostProcessor](../../StetMobile/StetMobile/Core/Dictation/TranscriptPostProcessor.swift)）。
