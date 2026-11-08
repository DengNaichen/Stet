# MacPaw SDK 0.6.0 复用调查

关联 [issue #220](https://github.com/DengNaichen/Stet/issues/220)。本记录为 2026-11-08 的静态调查与改动范围评估，尚未实施迁移；下列验收项均为待完成工作。

当前 OpenAI 路径使用 MacPaw Responses API，其他兼容服务仍手写 Chat Completions 请求、响应、HTTP 执行和错误解析。本 issue 复用已引入的 SDK 通用能力，同时保持现有供应商行为。

优先级：高。2026-11-08 重新调查：Stet 基线 `1126cb0432a80af06a837b1480e4f09e74077df3`（相关 AI 代码与本地 `a1cffba` 一致）。**SDK 已经升级到 0.6.0**（#222 / #226）；原正文的 0.4.7 基线已过时。本次不升级依赖。

## 已核实的当前状态

- [Package.swift](https://github.com/DengNaichen/Stet/blob/1126cb0432a80af06a837b1480e4f09e74077df3/Packages/StetEngine/Package.swift) 精确依赖 0.6.0；[Package.resolved](https://github.com/DengNaichen/Stet/blob/1126cb0432a80af06a837b1480e4f09e74077df3/Packages/StetEngine/Package.resolved) 锁定 SDK commit `0e1a00cee0b59e37729b96ebd116bb827aab86f2`。根 Xcode 项目最低版本也是 0.6.0。
- [OpenAIRewriteService](https://github.com/DengNaichen/Stet/blob/1126cb0432a80af06a837b1480e4f09e74077df3/Packages/StetEngine/Sources/StetAI/OpenAIRewriteService.swift) 仍包含手写 ChatCompletionRequest / ChatCompletionResponse、session.data(for:) 与错误 envelope。
- [OpenAISDKClientFactory](https://github.com/DengNaichen/Stet/blob/1126cb0432a80af06a837b1480e4f09e74077df3/Packages/StetEngine/Sources/StetAI/OpenAISDKClientFactory.swift) 已支持注入 URLSession、额外 middleware 和 timeout，并记录原始响应及状态码，优先复用。

## SDK 0.6.0 调查结论

1. [ChatQuery](https://github.com/MacPaw/OpenAI/blob/0e1a00cee0b59e37729b96ebd116bb827aab86f2/Sources/OpenAI/Public/Models/ChatQuery.swift) 已覆盖 jsonObject、jsonSchema / strict、reasoningEffort.customValue；DeepSeek 顶层 thinking 仍需小型请求 middleware。
2. [Configuration](https://github.com/MacPaw/OpenAI/blob/0e1a00cee0b59e37729b96ebd116bb827aab86f2/Sources/OpenAI/OpenAI.swift) 支持可选 token 和自定义 host/port/scheme/basePath。[JSONRequest](https://github.com/MacPaw/OpenAI/blob/0e1a00cee0b59e37729b96ebd116bb827aab86f2/Sources/OpenAI/Private/JSONRequest.swift) 在 token 为 nil 时不发送 Authorization；Stet sdkConfiguration 仍统一拒绝空 key，需要仅为 custom 放开。
3. **relaxed parsing 不足以兼容现有 fixture。** [ChatResult](https://github.com/MacPaw/OpenAI/blob/0e1a00cee0b59e37729b96ebd116bb827aab86f2/Sources/OpenAI/Public/Models/ChatResult.swift) 仅对部分顶层字段放宽；created、choice.index / finish_reason、message.role 等仍有要求。现有 choices/message/content-only 响应必须继续可用；不可通过补全 fixture 掩盖回归。
4. **必须保留 HTTP 状态及宽容错误解析。** [URLResponseHandler](https://github.com/MacPaw/OpenAI/blob/0e1a00cee0b59e37729b96ebd116bb827aab86f2/Sources/OpenAI/Private/URLResponseHandler.swift) 的 typed 路径只拦截并解码；[JSONResponseDecoder](https://github.com/MacPaw/OpenAI/blob/0e1a00cee0b59e37729b96ebd116bb827aab86f2/Sources/OpenAI/Private/JSONResponseDecoder.swift) 先尝试成功类型。非 2xx 携带成功形状也不能被接受。SDK 错误模型要求 error.type，不能直接替代当前 message-only 错误解析。
5. SDK async transport 在当前平台使用 URLSession.data(for:)，未发现内建重试循环。迁移保持单次请求、60 秒请求 timeout；取消与超时仍需运行时 fixture 验证。

补充源码依据：[SDK 错误模型](https://github.com/MacPaw/OpenAI/blob/0e1a00cee0b59e37729b96ebd116bb827aab86f2/Sources/OpenAI/Public/Errors/APIError.swift)要求 error.type，code 仅接受可选字符串，因此验收还应覆盖 numeric code 错误；[async transport](https://github.com/MacPaw/OpenAI/blob/0e1a00cee0b59e37729b96ebd116bb827aab86f2/Sources/OpenAI/Private/Client/AsyncClient.swift)提供上述传输及无重试循环的源码依据。

以上为固定版本源码及现有测试的静态核查，**未运行迁移编译、fixture 或真实 provider 请求**。

## 实现范围与建议边界

- **OpenAIRewriteService.swift**：用 SDK ChatQuery / chats 承担通用请求编码、响应解码和 HTTP 执行；删除通用手写类型。保留 TextRewriteService、prompt 和 StructuredRewriteOutputDecoder 契约。
- **OpenAICompatibleProviderConfiguration.swift**：custom 空白 key 转 nil，其余 provider 继续报 missingAPIKey；验证自定义 URL、端口与路径拼接。
- **小型 Chat Completions 兼容适配层（可新增 1 个文件）**：DeepSeek thinking 注入；只在成功 HTTP 响应且 SDK 解码失败时，从已记录的原始响应恢复现有支持的 choices/message/content 形状。不得另发请求，不扩张为第二套通用协议实现。
- **OpenAIError+Mapping.swift / request context**：保留所有非 2xx 拒绝、原始 error.message 的 trim / 空值 fallback，以及 invalidResponse / missingRewriteText 的语义。优先局限于 Chat 路径；修改公共 mapper 必须保护 Responses 行为。
- **OpenAISDKClientFactory.swift / OpenAIMiddlewareSupport.swift**：已有扩展点原则上可直接复用；仅在确有必要时调整。
- **测试**：主要扩展共享包 CloudStructuredRewriteTests 和 macOS OpenAITests；必要时拆出专门兼容 fixture 文件。

预计核心生产改动约 **3–5 个文件**，测试约 **2–3 个文件**；factory / middleware support 若需调整另计。属于共享服务层的中等范围重构，兼容测试工作量高于 API 替换本身。两端使用共享服务，因此需要双平台编译；预计无需修改两端 UI 或调用接口。

## 验收条件

- [ ] 常规兼容路径不再手写通用请求/响应类型和 HTTP 执行；剩余兼容代码逐项说明依据。
- [ ] 参数化 fixture 覆盖 Groq、DeepSeek、Qwen、GLM、Doubao、custom 的实际路径、鉴权、模型与正文；不改变模型目录启用状态。
- [ ] DeepSeek thinking enabled/disabled，low/high/max，以及 nil/default 行为保持；off 不发送 reasoning_effort。
- [ ] Groq GPT-OSS strict json_schema 与其他路径 json_object 选择保持；schema 内容、system/user 消息语义保持。
- [ ] custom 无 key/空白 key 不发送 Authorization；带 key 正确发送；其他 provider 缺 key 仍在请求前失败。覆盖尾斜杠、嵌套 basePath、HTTP 本地端点和显式端口。
- [ ] 完整标准响应和现有精简响应均通过；缺失必要业务结构、无效 JSON、空 choices、空 content、空 text 和无效结构化输出按原契约报错。
- [ ] 覆盖 401/429/500/503、非 JSON 错误、message-only 错误、空白 message，以及非 2xx 携带成功形状；保留 provider、statusCode 与错误消息语义。
- [ ] 保留 OpenAI Responses 未知 output 类型恢复测试和原始响应补救；不因共享配置/错误映射调整回归。
- [ ] 超时和主动取消保持；fixture 记录请求次数和取消事件，确认没有新增重试、后台请求或等待。
- [ ] 运行受影响共享包/macOS 测试，完成 macOS 与 iOS 编译；本地 fixture 与真实 provider 验证分别报告，未运行项明确标注。

测试起点：[CloudStructuredRewriteTests](https://github.com/DengNaichen/Stet/blob/1126cb0432a80af06a837b1480e4f09e74077df3/Packages/StetEngine/Tests/StetAITests/CloudStructuredRewriteTests.swift)、[OpenAITests](https://github.com/DengNaichen/Stet/blob/1126cb0432a80af06a837b1480e4f09e74077df3/StetMacTests/Core/AIProviders/OpenAICompatible/OpenAITests.swift)。

不在范围内：SDK 再升级、prompt、个人词典、语言保持、模型默认值或启用状态、Apple Intelligence、Google/Anthropic 的重试策略、UI 改动。

## 同日实现与验证记录

上述调查之后，用户授权实现，并追加将 iOS 构建默认工具链切换到正式版 Xcode。

- 生产代码实际涉及 3 个文件：[OpenAIRewriteService](../../Packages/StetEngine/Sources/StetAI/OpenAIRewriteService.swift)、[端点配置](../../Packages/StetEngine/Sources/StetAI/OpenAICompatibleProviderConfiguration.swift)和新增的 [ChatCompletionsCompatibility](../../Packages/StetEngine/Sources/StetAI/ChatCompletionsCompatibility.swift)。公共错误 mapper、factory、Responses 补救逻辑保持原样。
- [共享 fixture](../../Packages/StetEngine/Tests/StetAITests/CloudStructuredRewriteTests.swift)增加供应商路径、无 key、自定义端点、thinking、标准与精简响应、错误及取消覆盖。实际失败测试还发现 SDK 重复转义路径并丢失 query；兼容层保留完整端点 URL，也维持兼容路径不发送 OpenAI scoping headers 的行为。
- [Makefile](../../Makefile)将默认工具链设为正式版 Xcode，并使用未锁版本的 `iphonesimulator` SDK。保留 `IOS_DEVELOPER_DIR` 覆盖，不改变全局 Xcode selection 或最低 iOS 版本。

实际验证：

| 命令 / 范围 | 结果 |
| --- | --- |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StetEngine` | passed，退出码 0，87 tests / 12 suites |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` | passed，退出码 0，636 tests / 99 suites；在最后的 URL 修正之前运行 |
| 最后 URL 修正后，`xcodebuild ... -only-testing:StetTests/OpenAITests test` | passed，退出码 0；保护 Responses 恢复和兼容 Chat 路径 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build` | passed，退出码 0；最后 URL 修正后的 macOS 编译亦由上述定向测试完成 |
| `make lint DOCS_PYTHON=/Users/nd/Developer/stet-project/Stet/linter/.venv/bin/python`，另对修改的共享 Swift 文件运行 `swift-format lint --strict` | passed，退出码 0 |
| `make -n ios-build` 及覆盖 `IOS_DEVELOPER_DIR` 的 dry run | passed，默认调用正式版，覆盖值生效，SDK 未锁版本 |
| 修改后的 `make ios-build` | failed，Make 退出码 2 / xcodebuild 70：正式版 Xcode 报 iOS 26.5 平台未安装，无可用 generic simulator destination；尚未进入应用编译 |
| 真实 provider 请求 | not_run，仅验证本地 fixture |

iOS 环境备注：初次 runtime 下载返回 HTTP 504，已从本机已有相同版本复制独立 runtime 到任务 worktree；未共享可写框架。初始 Beta 路径不存在，正式版切换后仍受平台组件缺失阻塞。模拟器列表只有 iOS 27.0 runtime；这不构成正式版 iOS 编译通过的证据。
