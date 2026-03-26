# 需求文档：文本输出处理

## 概述

本文档定义了 Stet 在 macOS 上完成语音识别后的文本输出处理功能需求。

当用户完成语音输入并获得识别结果后，Stet 需要将识别出的文本传递给用户。该功能提供两种输出方式：

1. 将文本拷贝到系统剪切板
2. 将文本直接注入到用户当前活动的输入框

系统根据输出时的当前焦点自动选择合适的输出方式。这是 Stet 语音输入工作流的最后一个关键环节。

---

## 术语表

- **文本输出处理系统**（Text_Output_Handler）：负责将识别文本传递给用户的系统组件
- **剪切板输出**（Clipboard_Output）：将识别文本拷贝到 macOS 系统剪切板的输出方式
- **文本注入输出**（Text_Injection_Output）：将识别文本直接插入到用户当前输入框的输出方式
- **识别文本**（Recognized_Text）：语音识别服务返回的最终文本结果
- **活跃输入框**（Active_Input_Field）：用户当前正在使用的文本输入区域，通常表现为光标闪烁

---

## 核心原则

- 文本输出是语音输入工作流的最后一步，必须可靠执行
- 系统应该基于输出时的当前焦点自动选择输出方式，无需用户干预
- 有活跃输入框时优先使用文本注入，提供最流畅的输入体验
- 无活跃输入框时使用剪切板输出，保证文本不丢失
- 文本注入失败时应该自动降级到剪切板输出，保证文本不丢失
- 输出操作应该静默执行，成功时不打断用户
- 输出失败时应该提供清晰的错误信息和恢复路径

---

## 假设与依赖

本模块的设计基于以下假设：

1. **上游超时控制**：语音识别服务或管道编排层已经处理了请求超时、取消和重试逻辑。当识别结果传递到文本输出处理模块时，该结果是有效的且应该被处理的。

2. **识别结果有效性**：传递给文本输出处理模块的识别文本已经过验证，是最终确认的结果。

3. **输出路由决策**：上游管道编排层已经完成了输出路由决策。如果用户触发了特殊热键（如 Agent 模式热键），识别结果会被路由到其他处理流程（如转发给 Agent），不会进入文本输出处理模块。本模块只处理需要输出给用户的识别结果。

4. **权限管理**：辅助功能权限（用于文本注入和输入框检测）的申请和管理由权限管理模块负责，本模块只负责检查权限状态。

5. **系统辅助功能 API**：macOS 系统提供可靠的辅助功能 API 用于检测活跃输入框和执行文本注入。

---

## 需求

### 需求 1：自动输出模式检测

**用户故事：** 作为用户，我希望系统能够自动判断当前场景并选择合适的输出方式，无需手动配置，让输入过程更流畅。

**验收标准：**

1. WHEN 语音识别完成，THE Text_Output_Handler SHALL 自动检测当前是否存在活跃的输入框
2. WHEN 检测到活跃的输入框（光标闪烁），THE Text_Output_Handler SHALL 使用文本注入输出模式
3. WHEN 未检测到活跃的输入框，THE Text_Output_Handler SHALL 使用剪切板输出模式
4. THE Text_Output_Handler SHALL 在每次输出前重新检测输入框状态，不依赖缓存的状态
5. THE 活跃输入框检测 SHALL 基于系统辅助功能 API 提供的焦点信息

---

### 需求 2：剪切板输出

**用户故事：** 作为用户，当没有活跃输入框时，我希望能够将识别文本拷贝到剪切板，以便我可以手动粘贴到任何应用中。

**验收标准：**

1. WHEN 未检测到活跃输入框，THE Text_Output_Handler SHALL 将 Recognized_Text 拷贝到系统剪切板
2. WHEN 文本成功拷贝到剪切板，THE Text_Output_Handler SHALL 不主动清空或再次覆盖该剪切板内容，直到用户或其他应用执行新的剪切板写入操作
3. THE Text_Output_Handler SHALL 支持拷贝包含多行文本的 Recognized_Text
4. THE Text_Output_Handler SHALL 支持拷贝包含特殊字符和 Unicode 字符的 Recognized_Text

---

### 需求 3：文本注入输出

**用户故事：** 作为用户，当检测到活跃输入框时，我希望能够将识别文本直接注入到当前输入框，以便快速完成输入而无需手动粘贴。

**验收标准：**

1. WHEN 检测到活跃输入框，THE Text_Output_Handler SHALL 将 Recognized_Text 注入到 Active_Input_Field
2. THE Text_Output_Handler SHALL 在注入文本前验证文本注入权限是否可用
3. THE Text_Output_Handler SHALL 支持注入包含多行文本的 Recognized_Text
4. THE Text_Output_Handler SHALL 支持注入包含特殊字符和 Unicode 字符的 Recognized_Text
5. THE Text_Output_Handler SHALL 在注入完成后将 Active_Input_Field 的插入点保留在已注入文本之后

---

### 需求 4：剪切板保护

**用户故事：** 作为用户，当系统使用文本注入方式输出时，我希望我原有的剪切板内容不被覆盖，以便我可以继续使用之前复制的内容。

**验收标准：**

1. WHEN 使用文本注入输出模式，THE Text_Output_Handler SHALL 以 best effort 方式在注入前保存用户当前的剪切板内容
2. WHEN 文本注入完成后，THE Text_Output_Handler SHALL 以 best effort 方式恢复用户原有的剪切板内容
3. THE 剪切板保护机制 SHALL 至少支持文本类型的剪切板内容；对于其他类型内容，恢复行为为 best effort
4. WHEN 剪切板恢复失败，THE Text_Output_Handler SHALL 记录错误日志但不影响文本注入的执行
5. THE 剪切板保存和恢复操作 SHALL 作为文本注入流程的一部分执行，但不保证对系统剪切板的原子性

---

### 需求 5：输出失败处理

**用户故事：** 作为用户，当文本输出失败时，我希望收到清晰的错误提示和恢复建议，以便我能够解决问题并重试。

**验收标准：**

1. WHEN 剪切板拷贝失败，THE Text_Output_Handler SHALL 记录错误日志并向用户显示错误消息
2. WHEN 文本注入失败 AND 原因是缺少文本注入权限，THE Text_Output_Handler SHALL 向用户显示权限缺失提示
3. WHEN 文本注入失败 AND 原因是无法找到 Active_Input_Field，THE Text_Output_Handler SHALL 向用户显示相应的错误消息
4. WHEN 剪切板输出也失败时，THE Text_Output_Handler SHALL 提供重试选项或恢复建议
5. IF 文本注入失败，THEN THE Text_Output_Handler SHALL 自动降级到剪切板输出

---

### 需求 6：空文本处理

**用户故事：** 作为用户，当语音识别没有产生任何文本时，我希望系统能够合理处理，不执行无意义的输出操作。

**验收标准：**

1. WHEN Recognized_Text 为空字符串或仅包含空白字符，THE Text_Output_Handler SHALL 不执行输出操作
2. WHEN Recognized_Text 为空，THE Text_Output_Handler SHALL 向用户提供提示说明未识别到有效文本
3. THE Text_Output_Handler SHALL 将空白字符串和 null 值视为空文本
4. WHEN 识别结果为空，THE Text_Output_Handler SHALL 记录相应的日志信息

---

### 需求 7：文本格式保持

**用户故事：** 作为用户，我希望输出的文本能够保持识别结果的原始格式，包括换行、空格和标点符号。

**验收标准：**

1. THE Text_Output_Handler SHALL 保持 Recognized_Text 中的所有换行符
2. THE Text_Output_Handler SHALL 保持 Recognized_Text 中的所有空格和制表符
3. THE Text_Output_Handler SHALL 保持 Recognized_Text 中的所有标点符号
4. THE Text_Output_Handler SHALL 不对 Recognized_Text 进行额外的格式化或修改
5. WHEN 输出到剪切板或发起文本注入时，THE Text_Output_Handler SHALL 以原始文本内容进行输出；目标应用后续对文本的处理不属于本模块范围

---

## 非功能性需求

### 可用性

- 自动输出模式检测应该准确可靠，减少用户的认知负担
- 错误消息应该提供具体的问题描述和解决建议
- 输出操作应该支持键盘导航和辅助功能

### 可靠性

- 剪切板操作应该处理系统剪切板被其他应用占用的情况
- 文本注入应该处理目标应用不响应的情况
- 输出失败应该有明确的错误处理和恢复机制
- 系统应该记录所有输出操作的结果用于问题诊断

### 兼容性

- 该功能应该支持 macOS 26 及更高版本
- 文本注入应该与现有的辅助功能权限系统集成
- 剪切板操作应该与 macOS 通用剪切板（Universal Clipboard）兼容
- 该功能应该与应用程序现有的 SwiftUI 和 AppKit 集成点协同工作

---

## 不在范围内

以下内容明确不包含在本规范中：

- 文本输出前的自动格式化或美化
- 文本输出历史记录功能
- 多剪切板管理
- 文本输出的撤销/重做功能
- 输出文本的自动翻译
- 输出文本的自动纠错
- 富文本格式支持（如粗体、斜体、颜色）
- 输出文本的加密或安全保护
- 输出操作的遥测或分析数据收集
- 第三方剪切板管理工具的集成
