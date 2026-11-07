# 功能规格：MCP 对外契约

**创建**：2026-11-07
**状态**：Draft
**输入**：定义 Stet 在本机提供的 MCP 服务：何时开启、怎样连接、暴露哪些工具、出错时返回什么，以及 agent 能接触到的数据范围。吸收 旧 spec「008 MCP 转写」 中仍适用的边界（仅本机、默认关闭、监听失败不影响应用）。

**范围**：macOS。iOS 不提供 MCP 服务。
**边界**：本 spec 负责服务开关、传输、工具清单与输入输出、错误语义和数据边界。会议文件与会话状态的来源见[会议录制与保存](meeting-recording.md) spec；转写文档内容见[会议转写与说话人](meeting-transcription-and-speakers.md) spec；预期会议的生成与状态、所选日历见[日历与预期会议](calendar-and-expected-meetings.md) spec；MCP 日历工具需要的系统权限见 [权限与恢复](permissions-and-recovery.md)。
**替代**：替代 008。旧的按需转写工具（传入音频路径、用 SenseVoice 转写）已移除，不在范围内。

## 术语

- **会议 ID**：会议会话目录名（开始时间 `yyyy-MM-dd HH-mm-ss`，冲突时带后缀）。
- **工具错误**：工具调用成功送达，但结果标记为错误（`isError: true`），内容为一句可读的英文说明。
- **所选日历**：用户在会议设置页勾选的日历。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 让本机 coding agent 读取会议转写（优先级：P1）

作为用户，我在设置中打开 MCP 服务并把配置交给我的 coding agent，希望它能列出我的会议并读取转写，用来整理会议纪要。

**为什么是这个优先级**：会议转写是 MCP 的主要数据来源，也是现有工具的核心用途。

**独立测试**：打开 MCP，录完一场会议，用 MCP 客户端初始化、列工具、调用会议列表和获取转写，确认返回内容与会话目录中的转写文档一致。

**验收场景**：

1. **Given** MCP 已关闭，**When** 客户端连接 `127.0.0.1:49321`，**Then** 连接失败。
2. **Given** 我在设置中打开 MCP，**When** 服务启动成功，**Then** 状态显示“运行中”，“复制配置提示”按钮可用。
3. **Given** 服务运行中且已有会议，**When** agent 调用会议列表，**Then** 按开始时间倒序返回会议元数据，不含音频。
4. **Given** agent 调用获取转写且不传会议 ID，**When** 存在状态为“可读取”的会议，**Then** 返回最近一场的转写全文。

---

### 用户故事 2 - agent 帮我准备即将开始的会议（优先级：P2）

作为用户，我希望 agent 能读取预期会议和所选日历的事件、空闲时间，并在我要求时创建、修改或删除所选日历中的事件。

**为什么是这个优先级**：会前准备是会议工作流的延伸，但依赖日历开关和权限。

**独立测试**：勾选一个日历，用 MCP 依次列日历、查询事件、查空闲、创建一个事件、再删除它，确认只能操作所选日历。

**验收场景**：

1. **Given** 只勾选了“工作”日历，**When** agent 查询或修改“家庭”日历，**Then** 返回工具错误（按 ID 指定时说明该日历未在 Stet 中选择；按名称指定时说明找不到该日历）。
2. **Given** 日历完全访问权限未授予，**When** agent 调用任一日历工具，**Then** 返回工具错误说明需要完全访问权限，Stet 不弹出授权请求。
3. **Given** agent 删除事件，**When** 未传 `confirm: true`，**Then** 返回工具错误，事件不被删除。

---

### 用户故事 3 - 服务失败不影响 Stet（优先级：P3）

**独立测试**：先让其他进程占用 49321 端口，再打开 MCP，确认状态显示“启动失败”，听写和会议录制照常可用。

**验收场景**：

1. **Given** 端口被占用，**When** 打开 MCP，**Then** 状态为“启动失败”，Stet 其他功能不受影响。
2. **Given** MCP 已开启，**When** 重启 Stet，**Then** 服务自动启动。

### 边界情况

- 请求路径不是 `/mcp`：返回 HTTP 404。
- 客户端重复发送初始化：每次都成功（便于重连）；请求的协议版本受支持时沿用，否则返回服务端最新版本。
- 调用不存在的工具（包括已移除的 `stet_transcribe_audio`）：返回工具错误“Unknown tool”。
- `limit` 超过 100：按 100 处理；小于 1 或不是数字：工具错误（带小数的数字会被截断取整）。
- 请求的会议正在录制或处理：返回元数据，转写为空。

## 需求 *(必填)*

### 功能需求

**开启与传输**

- **FR-001**：MCP 服务默认关闭；只能由用户在设置的 MCP 页面打开。开关状态跨启动保留，开启时随 Stet 启动，Stet 退出即停止。
- **FR-002**：开启无需额外条件，也不需要鉴权。（是否需要鉴权、开启需满足哪些条件，待产品确认）
- **FR-003**：服务只监听 `127.0.0.1` 的 49321 端口，端点为 `http://127.0.0.1:49321/mcp`，使用 MCP 无状态 HTTP 传输；带 Origin 头的请求只接受来自 localhost 的来源。不提供 TLS 或远程访问。
- **FR-004**：设置页显示服务状态：关闭、启动中、运行中、启动失败。启动失败（例如端口被占用）只记录日志并显示状态，不得影响 Stet 其他功能。
- **FR-005**：设置页提供“复制配置提示”，仅在服务开启时可用；提示内容包含服务名 `stet`、传输 HTTP 和上述 URL，并要求 agent 保留已有配置、验证连接。
- **FR-006**：服务标识为名称 `stet`、标题 “Stet Meetings”；工具列表固定，不发送变更通知。

**会议工具（只读）**

- **FR-007**：`stet_list_meetings`：可选 `limit`（默认 20，最大 100）。按开始时间倒序返回会议摘要：`id`、`started_at`、`ended_at`、`duration_seconds`、`status`、`speaker_count`、`failure_message`、`metadata`（关联预期会议时的预期会议 ID、来源、事件 ID、标题、计划起止、参会人、会议链接）。
- **FR-008**：`stet_list_unorganized_meetings`：参数同上，只返回状态为 `ready` 的会议。
- **FR-009**：`stet_get_meeting_transcript`：可选 `meeting_id`。传入时返回该会议；不传时返回最近一场 `ready` 会议；找不到时返回工具错误。返回摘要字段加 `transcript`（转写文档全文；尚无文档时为空）。该工具不触发转写。
- **FR-010**：会议状态的对外取值：
  - `recording`：当前正在录制的会话；
  - `processing`：正在处理，或会话记录尚未写出；
  - `failed`：会话记录为失败（录制失败或处理失败）；
  - `organized`：已被标记为整理过；
  - `ready`：其余情况，即处理完成、可读取。
  （`organized` 当前没有任何途径可以设置，见待确认项）

**预期会议工具（只读）**

- **FR-011**：`stet_list_expected_meetings`：必填 `from`、`to`，`to` 必须晚于 `from`；返回计划开始时间落在该区间内的全部预期会议（含所有状态）。
- **FR-012**：`stet_get_expected_meeting`：必填 `id`（Stet UUID）；不存在时返回工具错误。
- **FR-013**：预期会议输出字段：`id`、`source`、`external_id`、计划起止、`title`、`attendees`、`meeting_url`、`notes`、`source_modified_at`、`status`、`recorded_meeting_id`。

**日历工具**

- **FR-014**：读工具：`calendar_calendars_list`（日历及是否可编辑）、`calendar_events_fetch`（按时间范围、日历 ID 或名称、全天、状态、忙闲、是否有提醒、是否重复、文本搜索过滤）、`calendar_events_get`（按事件 ID，重复事件可指定某次）、`calendar_free_busy`（返回忙、闲和冲突时段）。
- **FR-015**：写工具：`calendar_events_create`、`calendar_events_update`（可只改本次或本次及以后；传 null 清除地点、链接或备注）、`calendar_events_delete`（必须传 `confirm: true`）。创建时未指定日历则使用系统默认日历，前提是它在所选日历中且可编辑，否则返回工具错误。
- **FR-016**：所有日历工具只作用于所选日历；涉及未选日历时返回工具错误。按名称指定日历时（不分大小写）只在所选日历中查找：名称不存在（包括未选的日历）或对应多个日历都返回工具错误。
- **FR-017**：日历工具需要日历完全访问权限；未授权时返回工具错误，不发起授权请求（[权限与恢复](permissions-and-recovery.md) FR-003）。
- **FR-018**：输入限制：查询区间不超过 4 年；空闲查询不超过 31 天、匹配事件不超过 250 个；提醒最多 20 个；日期接受 ISO 8601 日期时间，或本地时区的 `yyyy-MM-dd` / `yyyy-MM-ddTHH:mm:ss`。
- **FR-019**：日历工具的可用性不依赖“日历会议”开关，只依赖所选日历和权限。（是否应绑定该开关，待产品确认）

**错误语义**

- **FR-020**：参数错误、对象不存在、权限不足、功能不可用、未知工具，一律以工具错误返回，内容为可读说明；不得让服务崩溃或断开连接。
- **FR-021**：只有传输层问题（错误路径、错误请求头等）以 HTTP 或协议错误返回。

**数据边界**

- **FR-022**：会议工具只返回会话元数据和转写文本，不返回音频、文件路径或声纹档案。
- **FR-023**：MCP 不提供开始或停止录制、触发转写、删除会议、修改预期会议的工具。
- **FR-024**：会改动数据的只有日历写工具，且限于所选日历；设置页必须明示“已连接的 agent 可以读取和修改所选日历”。

### 关键实体

- **MCP 服务状态**：关闭、启动中、运行中、启动失败（含原因）。
- **会议摘要**：见 FR-007。
- **预期会议输出**：见 FR-013。
- **工具错误**：带 `isError: true` 的工具结果和一句说明。

## 成功标准 *(必填)*

### 可衡量结果

- **SC-001**：MCP 关闭时，本机端口 49321 上 0 个由 Stet 打开的监听。
- **SC-002**：开启后，标准 MCP 客户端可以完成初始化、列出工具，并读取已完成会议的转写，内容与会话目录中的文档逐字一致。
- **SC-003**：对未选日历的任何读写请求 100% 返回工具错误。
- **SC-004**：端口被占用时，Stet 听写和会议录制可用率为 100%。

## 假设

- 只有本机进程能访问回环地址；当前不防范本机恶意进程。
- 不需要远程访问。
- 008 中的按需转写、`audio_path`、SenseVoice 和“没有设置界面”均已不成立。

## 待产品确认

1. **鉴权与开启条件**（index 待决项）：当前无鉴权，打开开关即可，日历写工具随之可用。可选：增加本机令牌；开启时二次确认；把日历写权限做成单独开关。
2. **`organized` 状态**：当前没有工具或界面能把会议标为已整理，因此“未整理会议”就是所有可读取的会议，永远不会减少。可选：增加“标记已整理”工具；删除该状态和“未整理”工具。
3. **日历工具与“日历会议”开关的关系**：当前开关关闭后，只要所选日历仍在，agent 仍能读写这些日历。可选：开关关闭时日历工具一律返回错误；维持现状。
4. **固定端口**：端口固定为 49321，被占用时只能失败。可选：允许修改端口；维持现状。

## 与当前实现的已知差异（非规范，供评审）

以下内容只记录 2026-11-07（`b327f54`）核对时的代码状态，不代表产品决定。

- 会议正在处理时，会话记录已写为“processing”，但对外状态被判为 `ready`；应用在录制或处理中退出后，遗留的会话也被判为 `ready`。因此不传 ID 获取转写时可能返回一场没有转写的会议，与 FR-010 不符。现有测试只覆盖“没有会话记录”的目录。证据：[MCPMeetingCatalog](../../StetMac/Core/MCP/MCPMeetingCatalog.swift) 的 `status`；[MCPMeetingCatalogTests](../../StetMacTests/Core/MCP/MCPMeetingCatalogTests.swift) 的 `overlaysLiveRecordingAndProcessing`。
- `organized` 状态只在读取时判断，代码中没有任何写入点。证据：同上、[MeetingRecordingStore](../../StetMac/Core/Speech/MeetingRecordingStore.swift) 的 `MeetingSessionRecord`。
- Origin 校验来自 MCP SDK 无状态传输的默认校验，Stet 未另行配置；未做真机验证。证据：[StetMCPProtocolServer](../../StetMac/Core/MCP/StetMCPProtocolServer.swift)。
- 端点、端口、默认关闭、启动失败状态与 FR-001 至 FR-004 一致。证据：[StetMCPHTTPServer](../../StetMac/Core/MCP/StetMCPHTTPServer.swift)、[StetMCPServerController](../../StetMac/Core/MCP/StetMCPServerController.swift)、[MacAppBootstrapper](../../StetMac/App/Lifecycle/MacAppBootstrapper.swift)（默认值 false）。
- 设置页与配置提示。证据：[MacMCPSettingsView](../../StetMac/Features/MacShell/Setting/MacMCPSettingsView.swift)。
- 工具清单与输入校验。证据：[MCPRecordingTools](../../StetMac/Core/MCP/Tools/MCPRecordingTools.swift)、[MCPExpectedMeetingTools](../../StetMac/Core/MCP/Tools/MCPExpectedMeetingTools.swift)、[MCPCalendarTools](../../StetMac/Core/MCP/Tools/MCPCalendarTools.swift)、[MCPToolSupport](../../StetMac/Core/MCP/Tools/MCPToolSupport.swift)。
- 日历范围限制。证据：[ScopedCalendarClient](../../StetMac/Core/Calendar/ScopedCalendarClient.swift)；测试 [StetMCPProtocolServerTests](../../StetMacTests/Core/MCP/StetMCPProtocolServerTests.swift)（同文件也验证旧工具名返回 unknown tool）。
