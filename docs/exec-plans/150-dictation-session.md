# Issue 150：拆分听写展示与采集流程

状态：实现、自动化检查和构建完成；真实 GUI 验收受工具故障阻塞。关联 [issue 150 第二部分](https://github.com/DengNaichen/Stet/issues/150)。

## 现状与目标

[DictationViewModel](../../StetMac/Features/Dictation/DictationViewModel.swift) 同时承担展示状态、采集任务、启动与激活、取消隔离、计量订阅、结果变换和历史提交。
主线已移除被动监听；会议互斥入口仍在 [MacAppSessionController+Meeting.swift](../../StetMac/App/Workflows/MacAppSessionController+Meeting.swift) 与听写启动入口。
本次不恢复已删除的被动监听，也不改变采集、历史和文本投递语义。

## 设计

- 在 Core 的现有 Dictation 目录增加 [DictationSession](../../StetMac/Core/Dictation/DictationSession.swift)，拥有 SpeechService、历史记录、全部 Task、启动/激活/取消标志与递增会话 ID。Interface 为预热、开始、激活、停止、取消及只读状态流；不依赖 Presentation。
- ViewModel 保留展示状态、独立的高频计量状态与 DictationAction 映射。同步接收 session 的值，不增加调度跳转；结果投递后的剪贴板提示和错误反馈仍是展示职责。
- App 组装 session 并注入 ViewModel。现有 MacDictationWorkflowController 继续拥有目标应用、提示音、媒体恢复和文本投递，不引入第二套采集所有权。
- 沿用现有 SpeechService 与 DictationHistoryRecording seams；无需再为唯一实现增加协议。

## 必须保留的不变量

1. 取消立即使旧会话 ID 失效；新启动等待未完成的取消，旧结果和旧失败不得覆盖新会话。
2. 启动/激活期间停止仍等待采集就绪；提示音后的激活与超时激活保持原有行为。
3. 最后一次异步挂起后再次核对会话身份，再一起提交 raw/LLM 历史。
4. 高频 level/features 不触发普通展示状态发布；初始准备完成通知保持原有行为。
5. 会议忙碌时听写不能启动，听写忙碌时会议快捷键不能启动会议。

## 执行顺序

1. 将生命周期实现移入 Core，并让 ViewModel 只适配状态与操作。
2. 更新 App 组装与测试构造入口；把生命周期测试移至 Core，保留展示行为测试。
3. 跑架构检查、格式/lint、macOS 完整测试与构建。
4. 实际操作验证菜单/快捷键听写开始、取消、失败和会议互斥；单独记录真实音频操作与模拟依赖测试，不能互相替代。
5. 审查 diff 后独立提交并创建面向 main 的 PR，与 Observation PR 分开交付。

## 验证记录

2026-11-08，基于 `b327f54` 的独立 worktree：

- `passed`：`python3 scripts/arch-check.py`，退出 0，R0–R7 全部 0。
- `passed`：先 `make docs-lint-setup` 再 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make lint`，均退出 0。
- `passed`：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test`，退出 0，631 tests / 98 suites；覆盖旧会话迟到失败、取消后重启、延迟激活、空转写、raw/LLM 历史提交、展示反馈以及高频计量不发布普通展示更新。
- `passed`：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build`，退出 0。
- `passed`（模拟依赖）：既有会议忙碌阻止听写、听写忙碌阻止会议快捷键的集成测试。
- `not_run`（真实 GUI）：自动化界面工具对本机 Debug 应用持续返回 `timeoutReached`，Finder 可读但截图返回 ScreenCaptureKit `-3812`。未将测试构建或进程存在当作界面验收。实际听写开始/取消/失败与会议录制互斥仍待人工验收，PR 保持 draft。
- `skipped`：被动监听暂停/恢复；主线已经移除该运行时，该场景不再适用。

最终 ViewModel 100 行，流程 459 行，独立计量状态 15 行。原生命周期测试迁入 [DictationSessionTests](../../StetMacTests/Core/Dictation/DictationSessionTests.swift)，[DictationViewModelTests](../../StetMacTests/Features/Dictation/DictationViewModelTests.swift) 检查展示适配与计量隔离。
