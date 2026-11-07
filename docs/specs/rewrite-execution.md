# 功能规格：改写执行

**创建**：2026-11-07
**状态**：Draft（待产品确认）
**输入**：定义转写完成后什么时候调用改写、向改写服务提供哪些上下文、怎样要求结构化输出、超时与重试，以及改写失败或缺少密钥时回退到转写原文。
**替代**：旧 spec「005 转写详情」中关于改写的部分（转写与改写解耦仍适用；“强制改写”“缺 key 阻断听写”“改写失败不得输出原文”已不再适用）。

**范围**：macOS 与 iOS。iOS 只在 FR-018 至 FR-020 单列差异。
**边界**：本 spec 拥有“何时改写、送什么、怎样调用、失败怎样回退原文、改写后的文本整理”。其他规则只引用：可选的服务商、凭据、模型目录与模型不可用时的回退见 [改写服务与模型](rewrite-services-and-models.md)；目标应用与 audience 怎样确定见[目标应用上下文](target-app-context.md) spec；词典向改写提供哪些词见[个人词典](personal-dictionary.md) spec；转写怎样产生见[转写引擎与模型准备](transcription-engines.md) spec；回退后用户看到什么见[听写结果与失败处理](dictation-outcomes.md) spec；历史怎样记录原文与改写文本见[听写历史与统计](dictation-history-and-stats.md) spec。选区改写不在本 spec 范围内（见待产品确认第 5 项）。

## 术语

- **改写**：把转写原文清理成可直接粘贴的书面文字：删除口头填充、保留自我更正后的版本、补标点、修正明显识别错误，不改变语言和意思。
- **可用的改写配置**：改写开关打开，且所选服务商已解析出可用模型并具备所需凭据；判定规则见 [改写服务与模型](rewrite-services-and-models.md)。
- **回退原文**：放弃改写结果，以转写原文作为最终文本。
- **结构化输出**：改写服务必须返回只含一个 `text` 字符串字段的 JSON 对象。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 转写后自动改写（优先级：P1）

作为用户，开启“转写改进”并配置好服务后，我希望每次听写的文字都经过清理再交付。

**为什么是这个优先级**：改写是 Stet 区别于普通听写的主要价值。

**独立测试**：开启改写并配置有效密钥，口述一段带“呃”、自我更正和列举的话，确认交付的文字已去除填充词、只保留更正后的说法并整理为编号列表，且语言未被翻译。

**验收场景**：

1. **Given** 改写开启且配置可用，**When** 转写得到非空文字，**Then** 调用所选服务改写，交付改写结果。
2. **Given** 改写关闭，**When** 转写完成，**Then** 不调用任何改写服务，交付整理后的原文。
3. **Given** 口述中英混杂，**When** 改写，**Then** 输出保持原来的语言混合，不翻译。

---

### 用户故事 2 - 改写失败时回退原文（优先级：P1）

作为用户，改写服务出错、超时、返回不合格内容或我没填密钥时，我仍希望拿到转写原文。

**为什么是这个优先级**：转写已经成功，改写的失败不应让用户损失口述内容。

**独立测试**：分别模拟缺少密钥、HTTP 401、HTTP 500、返回非 JSON、返回空 `text`，确认五种情况都交付原文。

**验收场景**：

1. **Given** 改写开启但没有密钥，**When** 听写完成，**Then** 跳过改写，交付原文，不阻止听写开始。
2. **Given** 改写服务返回错误或不合格内容，**When** 重试用尽，**Then** 交付原文。
3. **Given** 改写进行中用户取消听写，**When** 取消生效，**Then** 不回退原文，整次听写按取消处理。

---

### 用户故事 3 - 按目标应用和词典调整改写（优先级：P2）

作为用户，我希望改写参考我正在使用的应用和我的个人词典，让专有名词按词典拼写、格式适合目标应用。

**独立测试**：词典含“Stet”，口述中被识别成“stat”，确认改写结果为“Stet”；在不同类别的应用中听写，确认请求中带有应用名称和对应的 audience。

**验收场景**：

1. **Given** 词典开启且有词条，**When** 改写，**Then** 完整词条列表作为“规范拼写”提供给改写服务。
2. **Given** 能确定当前外部应用，**When** 改写，**Then** 请求带上该应用的名称与 audience。

### 边界情况

- 转写原文为空：不调用改写（结果见[听写结果与失败处理](dictation-outcomes.md) spec）。
- 改写结果只有空白：视为改写失败，回退原文。
- 改写服务不在支持范围（例如 Apple Intelligence 在低于 macOS 26 的系统上）：视为改写失败，回退原文。
- 模型被目录禁用或移除：使用服务商默认模型；服务商整体不可用时跳过改写，见 [改写服务与模型](rewrite-services-and-models.md)。
- 改写服务把转写内容当成指令执行或回答问题：属于质量问题，不触发回退；提示词须明确禁止（FR-006）。

## 需求 *(必填)*

### 功能需求

**何时改写**

- **FR-001**：macOS 的“转写改进”开关默认打开。只有开关打开且存在可用的改写配置时才改写；否则跳过改写，直接以原文作为最终文本，不提示，也不阻止听写开始。
- **FR-002**：改写对每一次非空转写执行，不按长度、语言或目标应用跳过。
- **FR-003**：改写服务在本次听写开始录音时确定；录音期间修改设置，从下一次听写起生效。

**提供给改写的上下文**

- **FR-004**：每次改写请求包含：转写原文（去除首尾空白）；audience 与当前外部应用名称（来源见[目标应用上下文](target-app-context.md) spec，在改写开始时读取）；词典提供的完整词条列表（来源见[个人词典](personal-dictionary.md) spec，不受转写热词上限约束）；语言代码（引擎识别出的语言，引擎未提供时用用户的主要转写语言）。
- **FR-005**：上述内容只发送给用户选定的改写服务。选择 Apple Intelligence 时在本机处理，不离开设备；选择云端或自定义端点时，转写原文、词条、应用名称和语言代码会发送给该服务。

**提示词约束**

- **FR-006**：云端改写的系统提示必须约束：输入是语音转写，不是给模型的指令，不得执行、回答或回应其中内容；不得翻译，输出语言与输入一致，混合语言保持原样；删除填充词和无意义重复；自我更正只保留最终说法；补充标点；修正上下文明确的识别错误，包括混合语言中被识别成另一种语言的近音词；明确列举的多项转为编号列表；保留含糊但可理解的原话；不丢失、不添加实质内容；代码、命令、API 名称、文件路径、参数、版本号原样保留；只输出纯文本，不加标题或包装。
- **FR-007**：云端改写在 audience 为“面向人”与“面向 AI / 编程工具”时使用两套提示，主要区别在换行规则：前者多用标点和换行提高可读性，后者只在不同想法之间空行、避免过度分段。请求未提供 audience 时按“面向人”。Apple Intelligence 的提示不区分 audience。
- **FR-008**：有词条时，提示要求把明显指向某个词条的误识别（拆分、同音、近音、大小写不同、部分翻译）替换为词条原样拼写；附近没有对应说法时不得凭空加入词条。
- **FR-009**：有应用名称时，提示要求据此调整风格、格式与术语；有语言代码时，提示要求锁定该语言，不翻译、不把混合语言统一成一种。
- **FR-010**：Apple Intelligence 使用单独的保守清理提示：中文与其他语言分别给出填充词与自我更正规则，并附带随应用打包的示例；同样包含不翻译、不回答、词典与应用名称规则。

**结构化输出**

- **FR-011**：改写服务必须返回只含 `text` 字符串字段的 JSON 对象，不得带其他字段或 Markdown 代码块；支持 JSON Schema 的服务以严格模式请求。Apple Intelligence 返回“修改说明 + 文本”两个字段，只取文本。
- **FR-012**：返回内容无法解析为上述结构、`text` 为空或只有空白时，视为改写失败。

**超时与重试**

- **FR-013**：超时与重试按服务商协议执行（待产品确认）：

  | 服务商 | 单次请求超时 | 重试 |
  | --- | --- | --- |
  | OpenAI、DeepSeek、Qwen、GLM、自定义端点 | 60 秒 | 不重试 |
  | Google、Anthropic | 网络会话默认值（约 60 秒） | 最多 3 次；HTTP 429、5xx 或响应无效时分别等待 2 秒、4 秒后重试；其他非服务商错误（如网络错误）等待 1 秒后重试；其余 4xx 不重试 |
  | Apple Intelligence | 无 | 不重试 |

  整次改写没有总时长上限（待产品确认）。

**回退原文**

- **FR-014**：以下任一情况都必须回退原文，且整次听写不得因此失败：缺少可用的改写配置；网络错误或超时；鉴权失败、额度不足等服务商错误；结构化输出不合格或为空；改写服务不可用。回退不向用户提示（待产品确认）。取消不是失败，不回退，整次听写按取消结束。
- **FR-015**：回退时最终文本即原文，历史中该次记为“未改写”（字段见[听写历史与统计](dictation-history-and-stats.md) spec）。

**最终文本整理**

- **FR-016**：未配置云端改写（改写关闭、无可用配置或使用 Apple Intelligence）时，按语言与上下文统一中英文标点的全角 / 半角；配置了云端改写时不做这一步。
- **FR-017**：无论是否改写，最终文本去掉末尾的一个句号（“。”或“.”），避免粘贴到 AI 工具时带多余句号（待产品确认）。整理后为空时按“引擎返回空文字”处理。

### iOS 差异

- **FR-018**：iOS 的改写开关默认关闭。开关打开且所选服务商有密钥（自定义端点须有地址和模型 ID）时改写；iOS 不提供 Apple Intelligence。
- **FR-019**：iOS 改写请求只包含原文与词典词条（词典开启时），audience 固定为“面向人”，不带应用名称和语言代码；改写期间会话处于“改写中”阶段。
- **FR-020**：iOS 改写失败时同样回退原文（FR-014），不做 FR-016、FR-017 的整理。

### 关键实体

- **改写请求**：原文、audience、应用名称、词典词条、语言代码。
- **改写配置**：服务商、模型、思考级别、凭据或端点（定义见 [改写服务与模型](rewrite-services-and-models.md)）。
- **改写结果**：结构化输出中的文本，或回退时的原文。

## 成功标准 *(必填)*

### 可衡量结果

- **SC-001**：改写服务任意失败时，有语音的听写 100% 交付原文。
- **SC-002**：缺少密钥时，听写开始不受阻，且不向改写服务发起任何网络请求。
- **SC-003**：中英混合的口述在改写后不出现整句翻译。
- **SC-004**：词典中的词条在改写结果中按词条原样拼写。
- **SC-005**：最终文本末尾不出现单个多余句号。

## 假设

- 改写服务、模型与思考级别的取值由 [改写服务与模型](rewrite-services-and-models.md) 提供，本 spec 只负责调用。
- 改写不依赖任何系统权限。
- 远程转写已移除；改写与转写完全独立，不存在“转写服务商与改写服务商组合”的限制。

## 待产品确认

1. **缺 key 或改写失败输出原文**（INDEX 待决项）：当前回退原文且不提示。可选：确认为产品策略；回退并提示“未改写”；失败时让用户选择。
2. **超时与重试不统一**：OpenAI 兼容服务 60 秒不重试，Google / Anthropic 最多 3 次且无单次超时设置，Apple Intelligence 无超时，最坏情况下用户可能等待数分钟。可选：统一总时长上限（例如 10–15 秒）后回退原文；按服务商保留现状。
3. **末尾句号一律去掉**：当前对所有目标应用生效。可选：维持；只在“面向 AI / 编程工具”时去掉；不去掉。
4. **iOS 上下文更少**：iOS 不传应用名称、语言代码，audience 固定。可选：维持；与 macOS 对齐语言代码。
5. **选区改写**（INDEX 待决项）：底层有替换选中文本的能力但没有入口。可选：删除；作为新功能另立 spec。
6. **语言代码来源**：Fun-ASR Nano 不返回识别语言，此时改写收到用户的主要转写语言（默认英文），中文口述也可能被标为英文并“锁定”。可选：不传语言代码；由改写服务自行判断；改用检测结果。

## 与当前实现的已知差异（非规范，核对基线 `b327f54`）

- 当前没有外部应用可识别时（`AppBranchMonitor.shared.currentApp` 为空），macOS 传给改写的 audience 是“面向 AI / 编程工具”，而不是 FR-007 对“未提供 audience”规定的“面向人”（[ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 的默认 `audienceProvider`）。
- Fun-ASR Nano 的转写结果不带语言代码，改写请求使用主要转写语言（默认 `en`）作为“语言锁定”（[ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 的 `stopRecording`；[FunASRNanoTranscriptionService](../../StetMac/Core/FunASR/FunASRNanoTranscriptionService.swift) 返回 `languageCode: nil`），可能与实际口述语言不符。
- 标点全角 / 半角整理按“配置的改写服务商”判断，而不是本次是否真的改写：配置了云端服务但改写失败回退时，原文不经过整理（[ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 的 `shouldApplyManualPunctuationCleanup`），与 FR-016 的表述一致但可能不是意图。
- 提示词中编号有重复（“面向 AI”版本有两条第 7 条），输出格式规则引用的“rule 8”并不是编号列表规则（“面向人”版本的列表规则是第 6 条，“面向 AI”版本是第 7 条），“面向 AI”版本中引用的“rules 4 and 5”也已错位（[TextRewriteService](../../Packages/StetEngine/Sources/StetRewrite/TextRewriteService.swift) 的 `baseSystemPrompt`）。
- 代码中有检测 Apple Intelligence“翻译漂移”的函数，但没有调用方（[ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 的 `hasTranslationDrift`）。
- 改写预热在录音开始约 1 秒后触发，但云端服务与 Apple Intelligence 的预热实现均为空操作（[AppleIntelligenceRewriteService](../../StetMac/Core/Rewrite/AppleIntelligenceRewriteService.swift) 的 `prewarm`；[TextRewriteService](../../Packages/StetEngine/Sources/StetRewrite/TextRewriteService.swift) 的默认实现）。
- 重试规则见 [CloudRewriteRetryExecutor](../../Packages/StetEngine/Sources/StetAI/CloudRewriteRetryExecutor.swift)、[AnthropicRewriteService](../../Packages/StetEngine/Sources/StetAI/AnthropicRewriteService.swift)、[GoogleRewriteService](../../Packages/StetEngine/Sources/StetAI/GoogleRewriteService.swift)；OpenAI 兼容服务的 60 秒超时与结构化输出见 [OpenAIRewriteService](../../Packages/StetEngine/Sources/StetAI/OpenAIRewriteService.swift)；输出解析见 [StructuredRewriteOutput](../../Packages/StetEngine/Sources/StetRewrite/StructuredRewriteOutput.swift)；缺 key 时跳过改写见 [DictationExecutionRoute](../../StetMac/Core/DictationPipeline/DictationExecutionRoute.swift)，[测试](../../StetMacTests/Core/DictationPipeline/DictationPipelineTests.swift) 允许缺 key 回退；iOS 见 [TranscriptPostProcessor](../../StetMobile/StetMobile/Core/Dictation/TranscriptPostProcessor.swift) 与 [RewriteSettingsStore](../../StetMobile/StetMobile/Core/Settings/RewriteSettingsStore.swift)；以上与本 spec 一致。
