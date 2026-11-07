# 功能规格：改写服务与模型

**创建**：2026-11-07
**状态**：Draft（待产品确认）
**输入**：定义用户可以选择哪些改写服务与模型、凭据怎样保存与校验、改写模型目录怎样远程分发，以及模型或服务不可用时的回退与提示。原地改写原“Remote rewrite model catalog”文档，其中已批准的分发参数、安全边界、回退规则与维护流程完整保留（FR-010 至 FR-018、附录 A）。
**替代**：本文件原有的“Remote rewrite model catalog”说明。

**范围**：macOS 与 iOS。远程模型目录只在 macOS 生效；iOS 差异见 FR-022 至 FR-024。
**边界**：本 spec 拥有服务商列表、凭据与 Keychain、凭据校验、自定义端点、模型目录的格式与分发、思考级别、模型或服务商不可用时选用哪个模型。其他规则只引用：什么时候改写、送什么、超时重试、失败或缺 key 时回退原文见『改写执行』spec；远程配置分发的通用约定（内置基线、定期检查、revision 只增不减）见 INDEX，本 spec 写出本目录的具体参数与差异；“通用”设置页与偏好存储见『应用偏好与更新』spec。远程转写服务商（OpenAI / Groq 转写）已移除，不在范围内。

## 术语

- **服务商**：提供改写的服务，例如 OpenAI、Google、DeepSeek、Apple Intelligence、自定义端点。
- **模型目录**：列出各云端服务商可用模型、默认模型和思考级别的 JSON 文件，即 [rewrite-models.json](../../StetMac/Resources/rewrite-models.json)。
- **保存的选择**：用户为某服务商选过的模型与思考级别。
- **临时回退模型**：保存的模型被禁用或移除时，本次实际使用的服务商默认模型。
- **思考级别**：模型推理强度档位（off、minimal、low、medium、high、max 中由目录声明的子集）。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 选择服务商并保存密钥（优先级：P1）

作为用户，我选择一个改写服务商，填入我的 API Key，Stet 安全保存它并用于之后的改写。

**为什么是这个优先级**：没有可用的服务商与凭据，改写无法进行。

**独立测试**：选择 OpenAI，填入密钥并保存；重启 Stet，确认设置显示密钥已保存（只显示前几位），改写正常进行。

**验收场景**：

1. **Given** 改写开启，**When** 我选择需要密钥的服务商并保存密钥，**Then** 密钥存入钥匙串，界面显示“已安全保存”与脱敏预览。
2. **Given** 已保存密钥，**When** 我点击“移除”，**Then** 钥匙串中的条目被删除，界面显示“未配置”。
3. **Given** 改写开启但所选服务商缺少密钥，**When** 我查看设置，**Then** 显示需要补充密钥的提示。

---

### 用户故事 2 - 校验密钥（优先级：P2）

作为用户，我希望保存前可以确认密钥是否被服务商接受。

**独立测试**：输入有效与无效密钥分别点击“校验”，确认显示接受或无法校验的提示；不校验也能保存。

**验收场景**：

1. **Given** 输入了密钥，**When** 我点击“校验”，**Then** Stet 向该服务商查询模型列表，成功时提示“密钥已被接受，模型访问权限取决于你的账户”。
2. **Given** 校验失败，**When** 结果返回，**Then** 提示检查密钥、网络与服务商权限；已保存的密钥不受影响。

---

### 用户故事 3 - 连接自定义端点（优先级：P2）

作为用户，我可以连接任何兼容 OpenAI API 的服务，加载其模型列表并选择一个模型。

**独立测试**：填入本地或自建服务的地址，点击“校验并加载模型”，选择模型后保存，完成一次改写。

**验收场景**：

1. **Given** 我填入不带协议的地址，**When** 保存，**Then** 默认按 https 处理；地址没有路径时补 `/v1`。
2. **Given** 服务器不需要鉴权，**When** 我不填密钥，**Then** 仍可加载模型并保存。
3. **Given** 未选择模型，**When** 我尝试保存，**Then** 保存按钮不可用。

---

### 用户故事 4 - 模型目录更新后自动使用新模型（优先级：P1）

作为用户，当 Stet 维护者上线、下线某个模型时，我不需要升级应用就能看到变化，且我保存的选择不会被悄悄覆盖。

**为什么是这个优先级**：服务商频繁更换模型，靠发版跟进会让用户长期用不了新模型或卡在已下线的模型上。

**独立测试**：把一个更高 revision 的目录发布到 GitHub `main`，在设置中手动检查，确认模型列表更新；再禁用用户已选的模型，确认实际使用服务商默认模型，恢复后自动回到用户选择。

**验收场景**：

1. **Given** GitHub 上的目录 revision 更高且有效，**When** 启动、每 24 小时或手动检查，**Then** 新目录生效并缓存。
2. **Given** 远程目录无效或 revision 不高于当前，**When** 检查，**Then** 保留当前目录。
3. **Given** 用户选的模型被禁用，**When** 改写，**Then** 使用该服务商当前默认模型，保存的选择不变；模型恢复后自动使用用户的选择。

### 边界情况

- 手动检查期间再次点击：按钮在检查中不可用。
- 内置目录损坏：使用代码中最小的兜底目录（只含 OpenAI 默认模型）。
- 缓存目录的 revision 不高于内置目录（例如升级应用后）：使用内置目录。
- 保存的思考级别不在新目录支持的列表中：使用该模型的默认思考级别，保存值保留。
- 服务商整体在目录中被禁用：设置中标为“不可用”且不能选择；规则与差异见 FR-019 与已知差异。

## 需求 *(必填)*

### 功能需求

**服务商与凭据**

- **FR-001**：macOS 可选择的服务商为：OpenAI、Google、DeepSeek、Qwen、GLM（受模型目录控制）、Apple Intelligence（Beta，需要 macOS 26 及以上，在本机运行，无需密钥）、自定义端点（兼容 OpenAI API）。Anthropic、Groq、Doubao 当前不可选择（待产品确认）。内置目录（revision 3）目前只启用 OpenAI、Google、DeepSeek，Qwen 与 GLM 在目录中整体禁用，因此设置中显示为“不可用”。
- **FR-002**：各云端服务商的 API 地址、鉴权方式与请求协议固定在应用代码中，用户与模型目录都不能修改；只有自定义端点由用户填写地址。
- **FR-003**：每个服务商的密钥单独保存在钥匙串，保存前去除首尾空白；保存空值等于删除。密钥不得写入偏好设置或日志。新建的钥匙串条目允许通过 iCloud 钥匙串同步（待产品确认）。
- **FR-004**：设置只显示密钥的前几位加掩码；提供“设置 / 更改”“移除”操作，钥匙串写入或删除失败时提示重试。
- **FR-005**：凭据校验为可选操作，不是保存的前提。校验通过查询服务商的模型列表完成，单次超时 15 秒；Apple Intelligence 与自定义端点不走此校验。
- **FR-006**：改写开启且所选服务商缺少密钥时，设置显示“添加 X 的 API Key 后才能使用转写改进”；自定义端点缺少地址或模型 ID 时显示对应提示。听写本身不被阻止（回退见『改写执行』spec）。

**自定义端点**

- **FR-007**：地址规整规则：去除首尾空白；无协议时补 https；只接受 http 与 https（待产品确认）；路径为空时补 `/v1`。
- **FR-008**：密钥可选。“校验并加载模型”请求 `/models`，单次超时 15 秒，返回的模型 ID 去重排序后供选择；修改地址或密钥后清空已加载的模型与选择；必须选定模型才能保存。
- **FR-009**：自定义端点与 Apple Intelligence 不受模型目录管理。

**模型目录分发（macOS，保留原文规则）**

- **FR-010**：macOS 以随应用打包的 [rewrite-models.json](../../StetMac/Resources/rewrite-models.json) 作为离线基线，并在启动时和之后每 24 小时检查 GitHub `main` 上的同一文件。
- **FR-011**：设置可以手动请求刷新。手动控件在检查期间不可用，并显示固定高度的“已更新”或失败结果，与应用兼容名单的更新器一致。
- **FR-012**：更新的有效目录以原子方式缓存到 Application Support；无效、过期或不可达的响应保留最后一个有效目录。
- **FR-013**：目录只能引用应用中已编译的服务商，不能更改 API 主机、鉴权、钥匙串账户、请求格式或服务商协议。这些边界留在 Swift 代码中，目录更新无法重定向凭据或转写文本。
- **FR-014**：首个包含该加载器的应用版本仍需发版；目录格式变更与新的服务商协议也需要发版。目录内的模型增删、启用 / 禁用与默认值调整不需要发版。

**模型目录分发的具体参数**

- **FR-015**：远程地址为 `https://raw.githubusercontent.com/DengNaichen/Stet/main/StetMac/Resources/rewrite-models.json`；请求忽略本地缓存，超时 15 秒，只接受 HTTP 200。请求不携带转写内容、密钥或用户信息。
- **FR-016**：目录有效的条件（客户端与校验脚本一致）：不超过 256 KiB；`schemaVersion` 为 1；`revision` 为正整数；服务商不超过 32 个且 ID 唯一，ID 只能是已编译的云端服务商（不含 Apple Intelligence 与自定义端点）；每个服务商不超过 100 个模型且 ID 唯一、符合字符规则；显示名非空且不超过 100 字符；思考级别不重复，有思考级别时默认级别必须在列表中，没有时不得设默认；`defaultModelID` 必须指向已启用的模型。
- **FR-017**：只有 revision 严格大于当前目录的远程目录才会生效；启动时缓存目录的 revision 严格大于内置目录才使用缓存。

**不可用时的回退（保留原文规则）**

- **FR-018**：保存的模型只要仍启用就优先使用。被禁用或移除时，Stet 使用该服务商当前的默认模型，不覆盖保存的选择，并在设置中显示这一临时回退；模型恢复后自动恢复用户的选择。服务商没有有效配置时跳过转写改进，保留原始转写（回退原文的规则由『改写执行』spec 拥有）。
- **FR-019**：服务商在目录中整体禁用或没有启用的模型时，该服务商在设置中标为“不可用”且不能选择，改写按“没有有效配置”处理。是否改写保存的服务商选择（待产品确认，见已知差异）。

**思考级别**

- **FR-020**：模型声明了思考级别时，设置显示“思考级别”选项；用户的选择按“服务商 + 模型”保存。保存的级别不受当前模型支持时使用模型默认级别，但不删除保存值。未声明思考级别的模型不显示该选项。
- **FR-021**：思考级别只作用于支持它的服务商协议（例如 OpenAI 的推理强度、DeepSeek 的思考开关与强度、Google 的思考级别）；其他服务商忽略。

**iOS 差异**

- **FR-022**：iOS 可选择 OpenAI、Google、DeepSeek、Qwen、GLM 与自定义端点；不提供 Apple Intelligence、Anthropic、Groq、Doubao。
- **FR-023**：iOS 不使用远程模型目录，模型列表与默认模型固定在应用中；切换服务商时模型重置为该服务商的默认模型。维护者调整 macOS 模型时不修改 iOS 的模型列表（见附录 A）。
- **FR-024**：iOS 的密钥同样按服务商保存在钥匙串（首次解锁后可读，允许 iCloud 钥匙串同步）；校验成功时自动保存密钥；自定义端点校验成功且尚未选择模型时，自动选中返回列表中的第一个模型。

### 关键实体

- **服务商**：标识、显示名、是否需要密钥、是否受目录管理、可用状态。
- **凭据**：按服务商保存的密钥；自定义端点另有地址与模型 ID。
- **模型目录**：`schemaVersion`、`revision`、服务商列表；每个服务商有启用状态、默认模型 ID 与模型列表；每个模型有 ID、显示名、启用状态、可选的思考级别列表与默认级别。
- **保存的选择**：每个服务商的模型 ID，以及每个“服务商 + 模型”的思考级别。

## 成功标准 *(必填)*

### 可衡量结果

- **SC-001**：维护者合并新目录后，运行中的客户端最迟在下一次 24 小时检查时生效，无需发版。
- **SC-002**：远程目录无效或不可达时，100% 保留最后一个有效目录。
- **SC-003**：模型被禁用再恢复后，用户无需重新选择即回到原来的模型。
- **SC-004**：任何目录内容都不能让密钥或转写文本发送到代码之外的主机（自定义端点除外）。
- **SC-005**：未经校验的密钥也能保存；校验结果在 15 秒内返回。

## 假设

- 服务商的模型列表变化比应用发版频繁，由维护者通过目录跟进。
- GitHub 不可用或 CDN 缓存可能延迟更新；已有的内置或缓存目录始终可用。
- 本 spec 不管理 Apple Intelligence 的系统可用性，只在系统不满足时将其标为不可用。

## 待产品确认

1. **Anthropic、Groq、Doubao 是否彻底下线**：代码仍支持其请求与校验，校验脚本也接受这些 ID，但设置中不可选，已保存者被改回 OpenAI。可选：彻底移除；重新开放 Anthropic。
2. **密钥经 iCloud 钥匙串同步**：当前 macOS 与 iOS 新建的密钥条目都允许同步。可选：维持（多设备免重复输入）；改为仅本机。
3. **自定义端点允许 http**：转写文本可能以明文发送。可选：维持（支持本地服务）；只允许 https 与本机地址的 http；http 时提示风险。
4. **服务商整体禁用时**：当前打开设置会把保存的服务商改为 OpenAI，与 FR-018“不覆盖保存的选择”的精神不一致。可选：只临时回退不改写保存值；维持现状。
5. **iOS 不跟随远程目录**：iOS 模型列表与 macOS 已出现差异。可选：iOS 接入同一目录；维持固定列表。

## 与当前实现的已知差异（非规范，核对基线 `b327f54`）

- FR-018 要求“在设置中显示这一临时回退”，当前设置只是在模型选择器中直接显示默认模型，没有任何说明文字（[MacRewriteModelSettingsSection](../../StetMac/Features/MacShell/Openai/MacRewriteModelSettingsSection.swift)、[MacOpenAISettingsViewModel](../../StetMac/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift) 的 `effectiveModelID`）。
- 保存的服务商为 Anthropic、Groq、Doubao，在目录中被禁用，或为 Apple Intelligence 而系统低于 macOS 26 时，打开设置页即把服务商改为 OpenAI 并保存（[MacOpenAISettingsViewModel](../../StetMac/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift) 的 `load`）；服务商恢复后不会自动回到原选择。未打开设置时，听写按“没有有效配置”跳过改写（[DictationSettingsStore](../../StetMac/Core/Settings/DictationSettingsStore.swift) 的 `loadSnapshot`）。
- 服务商“不可用”的判断读取全局共享的目录实例，而不是设置页注入的目录（[MacOpenAISettingsViewModel](../../StetMac/Features/MacShell/Openai/MacOpenAISettingsViewModel.swift) 的 `UnifiedAIProvider.isDisabled`）。
- 校验脚本允许的服务商包括 anthropic、groq、doubao，但设置中不可选择（[validate-rewrite-models.py](../../scripts/validate-rewrite-models.py)）。
- 钥匙串条目新建时设为可同步（[KeychainSecretStore](../../StetMac/Core/Security/KeychainSecretStore.swift) 的 `saveString`；iOS 见 [RewriteSettingsStore](../../StetMobile/StetMobile/Core/Settings/RewriteSettingsStore.swift) 的 `saveAPIKey`）。
- iOS 的固定模型列表与 macOS 目录不同（例如 Google 与 DeepSeek 的默认模型），见 [RewriteModel](../../Packages/StetEngine/Sources/StetCore/RewriteModel.swift) 与 [rewrite-models.json](../../StetMac/Resources/rewrite-models.json)。
- 目录加载、校验、缓存与刷新见 [RewriteModelCatalogStore](../../StetMac/Core/AIProviders/RewriteModelCatalogStore.swift)；凭据校验见 [ProviderCredentialValidationService](../../Packages/StetEngine/Sources/StetAI/ProviderCredentialValidationService.swift)；自定义端点地址规整与模型探测见 [OpenAICompatibleEndpoint](../../Packages/StetEngine/Sources/StetAI/OpenAICompatibleEndpoint.swift)；密钥校验界面见 [MacAPIKeySheet](../../StetMac/Features/MacShell/Openai/MacAPIKeySheet.swift)；iOS 设置见 [RewriteSettingsViewModel](../../StetMobile/StetMobile/Features/Settings/ViewModels/RewriteSettingsViewModel.swift)；以上与本 spec 一致。

## 附录 A：维护模型目录（保留原文流程）

1. 在 [rewrite-models.json](../../StetMac/Resources/rewrite-models.json) 中，于已有服务商下新增、禁用或移除模型。
2. 为每个模型配置可选的 `thinkingLevels` 与 `defaultThinkingLevel`；默认级别必须出现在其支持列表中。
3. 确保每个服务商的 `defaultModelID` 指向一个已启用的模型。
4. 递增 `revision`；不得复用或减小。
5. 运行 `python3 scripts/validate-rewrite-models.py` 并开 PR。
6. CI 通过后合并。对已包含目录加载器的客户端，不需要打 tag、DMG 或发布应用。

撤销某次修改时，做一次新的编辑并再次递增 revision。客户端忽略更旧或相等的 revision。

补充：macOS 改写模型的增删、默认值或可用性调整只改上述 JSON；不要修改 [RewriteModel](../../Packages/StetEngine/Sources/StetCore/RewriteModel.swift)，它仍是 iOS 的兼容模型列表。
