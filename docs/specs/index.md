# 软件需求（Specs）

现行 spec 按“可以独立讨论、修改和验收的行为契约”划分，不按用户入口或代码模块划分。所有文件平铺在本目录，不建子目录。每份只负责一类规则，其他 spec 只引用、不重复定义。

所有 spec 当前均为 **Draft**：按代码基线 `b327f54` 撰写并逐条核对过事实；凡是需要产品决定、仅凭代码无法确定的地方，都以当前行为写成暂定规则，标注“待产品确认”，并在各 spec 的「待产品确认」小节列出。格式以 [权限与恢复](permissions-and-recovery.md) 为模板。

旧的编号 spec（001–010）已被下列 spec 吸收后删除，历史可从 Git 追溯。

## Specs

每份 spec 写明平台范围；iOS 只单列平台独有的行为。

1. [首次使用引导](onboarding.md)：onboarding 的步骤顺序与首次成功标准；权限状态本身不归它管。
2. [权限与恢复](permissions-and-recovery.md)：各功能需要哪些系统权限、缺失时阻止还是跳过、运行时恢复。
3. [macOS 听写会话](macos-dictation-session.md)：从触发到结束的状态机、热键、取消、听写与会议的互斥、录音期间的副作用（静音、暂停媒体、提示音、通知）。
4. [听写指示器与外观](dictation-indicator.md)：听写面板和圆球的视觉、动画与主题选择。
5. [音频输入设备](audio-input-devices.md)：听写和会议麦克风共用的设备选择、偏好保留、回退和麦克风测试。
6. [转写引擎与模型准备](transcription-engines.md)：引擎选择和回退、模型下载、镜像、存储和预热，以及每个引擎各自的音频后处理规则。
7. [听写结果与失败处理](dictation-outcomes.md)：无语音、转写失败、改写失败、交付失败等情况的完整结果矩阵。
8. [改写执行](rewrite-execution.md)：什么时候改写、提供哪些上下文、超时和重试，以及失败时回退到原文。
9. [改写服务与模型](rewrite-services-and-models.md)：服务商、凭据、模型目录分发和模型不可用时的回退。
10. [目标应用上下文](target-app-context.md)：识别目标应用、排除 Stet 自身、记住最近的外部应用、audience 分类。
11. [文本交付](text-delivery.md)：粘贴、只放剪贴板的兜底、剪贴板恢复，以及乐观完成的判定规则。
12. [应用兼容名单](app-compatibility.md)：只管名单的数据格式和远程分发。
13. [个人词典](personal-dictionary.md)：词条增删改、手动 / 自动来源及其存储、iCloud 同步，以及向转写和改写提供哪些词。
14. [修正学习](correction-learning.md)：观察窗口、差分提取和跳过条件。
15. [听写历史与统计](dictation-history-and-stats.md)：保存的字段、`finalText` 的含义、删除与保留期，以及统计口径。
16. [会议录制与保存](meeting-recording.md)：多轨录音、系统音频和文件生命周期。
17. [会议转写与说话人](meeting-transcription-and-speakers.md)：会议转写、说话人分离、本地声纹档案，以及无法识别的说话人如何归类。
18. [日历与预期会议](calendar-and-expected-meetings.md)：日历选择、会议映射和预期会议提醒。
19. [MCP 对外契约](mcp.md)：对外暴露的工具、默认关闭、开启条件和数据边界。
20. [iOS 常驻麦克风与 Live Activity](ios-persistent-capture.md)：采集生命周期、暖机帧门、单消费者、路由恢复和后台状态。
21. [iOS 键盘听写](ios-keyboard-dictation.md)：键盘与主 App 之间的交接、插入和返回引导。
22. [应用偏好与更新](app-preferences-and-updates.md)：通用设置和应用更新；不作为杂项收纳。

不建 spec 的部分：付费与试用目前只有占位代码；诊断和 shader 调试属于开发工具。以后如果 [macOS 听写会话](macos-dictation-session.md) 过大，可把热键拆为单独的「听写快捷键」；如果统计口径需要单独讨论，可把 [听写历史与统计](dictation-history-and-stats.md) 拆成两份。

## 跨 spec 规则归属

| 规则 | 负责的 spec | 引用方 |
| --- | --- | --- |
| 功能需要哪些系统权限、缺失时如何处理 | [权限与恢复](permissions-and-recovery.md) | 所有功能 spec |
| 默认快捷键与组合规则、听写与会议录制的互斥 | [macOS 听写会话](macos-dictation-session.md) | 首次使用引导、会议录制与保存 |
| 模型下载、镜像与存储 | [转写引擎与模型准备](transcription-engines.md) | 会议转写与说话人、iOS 相关 spec |
| 改写失败或缺 key 时回退原文 | [改写执行](rewrite-execution.md) | 听写结果与失败处理、改写服务与模型 |
| 乐观完成的判定 | [文本交付](text-delivery.md) | 应用兼容名单（只提供名单数据） |
| 词典向转写 prompt、Nano hotwords、改写 preferredSpellings 提供哪些词 | [个人词典](personal-dictionary.md) | 转写引擎与模型准备、改写执行（只写如何使用） |
| 词条来源（manual / automatic）的存储格式与兼容 | [个人词典](personal-dictionary.md) | 修正学习 |
| 关闭词典时停止自动学习 | [修正学习](correction-learning.md) | 个人词典 |
| `finalText` 的含义 | [听写历史与统计](dictation-history-and-stats.md) | 修正学习、文本交付 |
| 远程配置分发 | 本 INDEX 的「通用约定」 | 应用兼容名单、改写服务与模型（只写差异） |
| 隐私边界 | 本 INDEX 的「通用约定」 | 各 spec 只写自己的数据去向 |

## 通用约定

### 远程配置分发

适用于由仓库文件远程下发、无需发版即可更新的配置（目前是 [应用兼容名单](app-compatibility.md) 和 [改写服务与模型](rewrite-services-and-models.md) 的模型目录）：

- 仓库中的同一个文件既是随应用打包的离线基线，也是客户端从 GitHub `main` 下载的远程版本。
- 客户端启动时和运行期间定期在后台检查更新；设置中可手动检查。网络失败不影响使用，继续使用已有版本。
- 每次修改都必须递增 `revision`，不得重复或回退；客户端忽略不高于本地版本的 `revision`。撤销一次修改也要用新的、更高的 `revision`。
- 修改前运行对应的校验脚本，经 PR 合并后生效。配置格式变更、新的协议或能力仍需发版。
- 下载内容只是公开配置，请求不携带用户数据。

各 spec 只写自己的文件位置、字段、检查频率等差异，以及该配置不能改变的安全边界。

### 隐私边界

- 转写文本、剪贴板内容、音频和声纹只发送给用户明确选择的服务；除此之外留在本机或用户自己的 iCloud。
- 用户内容不写入日志。
- 每份 spec 在需求中写明本功能的数据去向；与这条原则冲突的地方必须在该 spec 中明确说明并标为待产品确认。

## 待产品确认

各 spec 的「待产品确认」小节共列出约 100 项，按 spec 逐份审阅。已经决定的：

- 会议录制缺少系统音频录制时不开始录制，不退化为只录麦克风（见 [权限与恢复](permissions-and-recovery.md) FR-008）。

跨多份 spec、值得优先拍板的问题：

- 缺 key 或改写失败时输出原文，是否确认为产品策略（[改写执行](rewrite-execution.md)、[听写结果与失败处理](dictation-outcomes.md)）。
- VAD 裁切会改变音频时长、Fun-ASR Nano 跳过后处理，是否为预期行为（[转写引擎与模型准备](transcription-engines.md)）。
- 录音中途切换麦克风是否立即生效（[音频输入设备](audio-input-devices.md)）。
- 乐观完成是否扩大到兼容名单之外的应用；选区替换能力保留还是删除（[文本交付](text-delivery.md)）。
- 从菜单、设置页或预期会议提醒开始会议录制时，是否统一检查听写状态和权限（[macOS 听写会话](macos-dictation-session.md)、[会议录制与保存](meeting-recording.md)）。
- 听写历史与会议文件的保留期限与删除方式（[听写历史与统计](dictation-history-and-stats.md)、[会议录制与保存](meeting-recording.md)）。
- iOS 云端转写与“本机转写”的用途说明不一致；Mac 与 iPhone 是否共享词典（[iOS 键盘听写](ios-keyboard-dictation.md)、[转写引擎与模型准备](transcription-engines.md)、[个人词典](personal-dictionary.md)）。
- MCP 本地 HTTP 是否需要鉴权（[MCP 对外契约](mcp.md)）。
