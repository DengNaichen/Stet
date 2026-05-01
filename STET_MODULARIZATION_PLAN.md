# Stet 核心逻辑模块化与 Kit 化计划 (Modularization Plan)

## 1. 目标 (Objective)
为了支持后续 iOS 应用的开发并实现代码最大化复用，我们需要将 `Stet` 项目中的核心业务逻辑（尤其是 AI 网络请求和文本重写逻辑）从主 App 目标中剥离，封装成独立的、平台无关的 Swift Package 模块。

## 2. 核心架构设计 (Architecture)

我们建议引入一个名为 `StetEngine` (或类似名称) 的本地 Swift Package，包含以下几个核心模块 (Targets)：

### A. StetCore (基础定义模块)
*   **定位**：项目的最底层基座，100% 平台无关（Foundation only）。
*   **内容清单**：
    *   **通用 Model**：`AppAudience` (Enum), `StoredTranscriptionEngine` (Enum) 等纯数据定义。
    *   **基础协议**：`ModelStorageConfiguration` (存储配置契约) 等跨模块依赖的接口。
    *   **错误定义**：`StetError` (新增)，统一全项目的错误码标准。
    *   **静态常量**：`StetLinks` (官网及社交链接)。
*   **迁移要点**：
    1.  **零 UI 依赖**：严禁引入 `SwiftUI` 或 `AppKit`/`UIKit`。
    2.  **访问控制**：所有暴露给外部的类型和初始化方法必须标记为 `public`。
    3.  **逻辑剥离**：例如 `AppAudienceResolver` 这种涉及 Bundle 识别的平台逻辑应留在主工程，模块内仅保留 `AppAudience` 枚举。
*   **复用价值**：极高。所有平台必须共享同一套数据模型和接口契约。

### B. StetAI (AI 能力模块)
*   **定位**：负责「与 AI 厂商通讯」的物理链路层，纯逻辑封装。
*   **内容清单**：
    *   **核心枚举**：`AIProvider` (原 `DictationProvider` 改名，明确其 AI 属性而非听写属性)。
    *   **模型定义**：`RewriteModel` (各厂商支持的 Model ID 及默认配置)。
    *   **具体实现**：`Stet/Core/AIProviders/` 下的所有具体实现（OpenAI, Anthropic, Google, DeepSeek 等）。
    *   **网络基础**：统一的 `URLSession` 封装、流式响应 (SSE) 解析器。
    *   **验证逻辑**：API Key 状态验证、Provider 连通性测试。
*   **迁移要点**：
    1.  **配置注入**：模块不持有状态。API Key、Base URL 等必须在初始化时通过 `Configuration` 对象从 App 层注入。
    2.  **依赖剥离**：将第三方 SDK（如 OpenAI SDK）的依赖从主工程移动到此模块的 `Package.swift`。
    3.  **错误映射**：建立统一的 `StetAIError` 体系，屏蔽各厂商 API 报错的差异。
*   **复用价值**：极高。iOS 和 macOS 共享完全一致的 API 调用逻辑及网络层优化。

### C. StetRewrite (重写逻辑模块)
*   **定位**：负责「重写策略与 Prompt 调度」的业务逻辑层。
*   **内容清单**：
    *   **服务协议**：`TextRewriteService` (定义重写、预热等标准接口)。
    *   **请求模型**：`TextRewriteRequest` (封装文本、受众、拼写偏好、环境上下文等)。
    *   **Prompt 引擎**：`CloudRewritePromptBuilder` 及各场景（纠错、润色、翻译）的 Prompt 模板管理。
    *   **逻辑封装**：`PreparedCloudRewritePayload` (负责将业务请求转化为 AI 可理解的 Payload)。
    *   **厂商抽象**：作为 `StetAI` 的上层，协调不同 AI Provider 或系统原生（Apple Intelligence）能力的调用。
*   **迁移要点**：
    1.  **策略与执行分离**：此模块负责生成系统提示词（System Prompt），而具体的网络发送交由 `StetAI` 执行。
    2.  **纯逻辑化**：严格禁止引入 `AppKit`/`UIKit`，确保 Prompt 生成逻辑在所有 Apple 平台表现一致。
    3.  **平台兼容层**：针对 `AppleIntelligence` 等平台强相关功能，在此模块定义抽象接口，由主工程提供注入实现。
*   **复用价值**：高。核心 Prompt 策略、业务流程以及多场景适配逻辑在不同客户端完全保持一致。

## 3. 迁移策略 (Migration Strategy)

### 阶段一：建立基础设施 (Infrastructure)
1.  创建本地 Swift Package 仓库。
2.  配置 `Package.swift`，引入必要的第三方依赖（如 `KeyboardShortcuts` 仅限 macOS，而网络请求库可通用）。
3.  将 `Stet/Shared/Models` 下的基础类型迁移至 `StetCore`。

### 阶段二：剥离 AI Providers
1.  将 `Stet/Core/AIProviders/` 下的文件夹整体搬迁至 `StetAI` 模块。
2.  **解耦关键点**：使用我们在上一步中完成的协议注入模式。`StetAI` 模块不直接读取 `UserDefaults`，而是由 App 层在初始化时注入密钥。
3.  在主项目中通过 `import StetAI` 重新连接。

### 阶段三：剥离重写服务
1.  迁移 `Stet/Core/Rewrite/` 下的代码。
2.  针对 `AppleIntelligence` 等平台强相关的 API，在模块内部使用接口抽象，主项目提供具体的驱动实现。

## 4. 接口设计原则 (Design Principles)

1.  **协议优先**：Kit 对外暴露的是接口 (Protocols)，主 App 负责注入实现。
2.  **无状态化**：Kit 内部不持有全局单例状态，所有配置项（API Key, Base URL）在构造时传入。
3.  **零 UI 依赖**：Kit 严禁引入 `SwiftUI` 或 `AppKit`/`UIKit` 的视图组件。

## 5. 待讨论问题 (To Be Discussed)
1.  **第三方依赖处理**：目前项目中使用的 `OpenAI` 库是否支持直接作为子模块依赖？
2.  **密钥安全**：Kit 是否需要内置基础的加密逻辑，还是完全交给宿主 App 提供的 `CredentialStore`？

## 6. 任务清单 (Action Items)
- [ ] 创建 `StetEngine` Swift Package 框架。
- [ ] 迁移 `DictationProvider` 和 `StoredTranscriptionEngine` 等基础类型。
- [ ] 迁移并测试第一个 AI Provider (建议从 OpenAI 开始)。
- [ ] 完成 `StetAI` 的整体迁移。
- [ ] 迁移 `StetRewrite`。
