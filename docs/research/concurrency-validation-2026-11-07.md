# 并发审计问题验证与修复（2026-11-07）

从 [#159](https://github.com/DengNaichen/Stet/issues/159) 沿
[#177 审计索引](https://github.com/DengNaichen/Stet/issues/177) 核查 #156–#176 共 21 项。
复核基线为 main `98d8bbc`；原始 issue 基于 `b9638d2`，中间的被动监听删除和既有修复必须计入结论。
本记录针对本分支的代码与自动测试，不把模拟依赖的结果等同于物理设备或实际 UI 性能验收。
本轮验收范围仅为 macOS 及其共享代码，使用稳定版 Xcode；iOS 不纳入本轮工作。

## 逐项结论

| Issue | 当前结论 | 处理与证据 |
| --- | --- | --- |
| [#156](https://github.com/DengNaichen/Stet/issues/156) | 已不适用 | `7698c1c` 已删除被动会话 coordinator，原来的 arm/shutdown/processing 链不存在。 |
| [#157](https://github.com/DengNaichen/Stet/issues/157) | 既有修复有效 | `a75b569` 已通过 lastWrite 串联历史写入；重新运行历史服务 11 项测试。 |
| [#158](https://github.com/DengNaichen/Stet/issues/158) | 已不适用 | 被动监听 Bool 门与恢复入口已删除。该结论不证明所有主动录音入口之间完全互斥。 |
| [#159](https://github.com/DengNaichen/Stet/issues/159) | 修复 | 媒体查询、脚本只在专用串行队列运行；结束后的迟到查询不能暂停媒体；查询回调结果加锁。 |
| [#160](https://github.com/DengNaichen/Stet/issues/160) | 既有修复有效 | 六个相关处理类型已 nonisolated，处理入口有 @concurrent；再次运行阻占 MainActor 的回归。 |
| [#161](https://github.com/DengNaichen/Stet/issues/161) | 修复 | AX system-wide 与 focused element 都设置 100ms 消息超时；复制改为可取消的异步轮询，超时有界，复制完成同时取消也恢复剪贴板。 |
| [#162](https://github.com/DengNaichen/Stet/issues/162) | 已不适用 | 被动收尾、beginActive/resumePassive 依赖已删除；主动听写不再等待该链。 |
| [#163](https://github.com/DengNaichen/Stet/issues/163) | 修复 | 采集与 FunASR actor 使用专用串行 executor，保持原 actor 顺序；消除 startRunning 的额外 sync，避免 recorder 析构等待自身队列。 |
| [#164](https://github.com/DengNaichen/Stet/issues/164) | 修复 | willTerminate 通知内同步恢复静音，不依赖析构中的 Task。 |
| [#165](https://github.com/DengNaichen/Stet/issues/165) | 修复 | MCP 控制器记录最新运行意图、停止任务与 run ID，等待停止完成后重启，忽略旧 run 回调。 |
| [#166](https://github.com/DengNaichen/Stet/issues/166) | 修复 | 只清理当前 refresh ID；代际检查拒绝旧结果和错误；EventKit 通知缓冲保留最新一次。 |
| [#167](https://github.com/DengNaichen/Stet/issues/167) | 修复 | fallback 激活复用公开入口及错误清理；失败转 error，停止电平流。 |
| [#168](https://github.com/DengNaichen/Stet/issues/168) | 已不适用 | 无 lease 的被动转写入口已删除；现有会议 prepare/finish 路径持有和释放 lease。 |
| [#169](https://github.com/DengNaichen/Stet/issues/169) | 修复 | 生产读写共用 ProfileStore actor；模型加载共享同一个 Task，失败后允许重试；测试仍可注入独立实例。 |
| [#170](https://github.com/DengNaichen/Stet/issues/170) | 修复 | NIO handler 明确 nonisolated；HTTP 与 SDK 工具任务受生命周期管理，客户端单请求取消也传到工具任务；文件读取和 MCP 日历查询脱离 MainActor，EventKit 对象留在查询 actor 内。 |
| [#171](https://github.com/DengNaichen/Stet/issues/171) | 修复 | startup/runtime 探针同步记录时间和顺序，去除两层非结构化 Task；文件落盘在专用队列。 |
| [#172](https://github.com/DengNaichen/Stet/issues/172) | 修复 | 独立 DictationMeteringState 只通知胶囊；主会话不因每帧电平通知。被动状态广播已随功能删除。 |
| [#173](https://github.com/DengNaichen/Stet/issues/173) | 修复 | 四个纯转发 VM 同步通知；保留 willSet 后读取新值所需的调度和跨 actor 通知。 |
| [#174](https://github.com/DengNaichen/Stet/issues/174) | 修复并逐项澄清 | AppBranch、设备监听/选择统一主 actor 所有权，移除不必要锁与跳转；简化设置、热键、修正学习和统计标注；转换回调局部 Bool 代替每 buffer 的锁。真实跨队列锁保留，理由见下。 |
| [#175](https://github.com/DengNaichen/Stet/issues/175) | 修复并逐项澄清 | 被动 actor 与无界帧桥已删除；无状态适配器用值类型；采集启动直接在 activeTask await，保留取消排序。电平/特征桥保留，理由见下。 |
| [#176](https://github.com/DengNaichen/Stet/issues/176) | 清理并逐项澄清 | 合并有界广播实现，删除全注释热键文件、只被测试调用的处理入口与录音 snapshot、未使用的本地 Sherpa recognizer；清理重复 import 和无效 detached；记录隔离标注约定。 |

## 没有照建议删除的代码

- `firstBufferLock` 保护控制队列重置与采集回调认领；normalized-session 锁保护采集回调转换与控制队列 close。
  它们并非单线程访问，删除会引入竞态。
- [ConfigurableSpeechService](../../StetMac/Core/Speech/ConfigurableSpeechService.swift) 的电平/特征桥提供跨 recorder 重建的稳定订阅，并在停止时发归零信号。
  它们是 latest-value 有界缓冲，不是已删除的无界音频帧队列。
- AppModel 析构清理仍可服务非进程退出的生命周期；正常进程退出不保证析构 Task 执行，不能把它当作退出恢复机制。
- 上游 Vendor 的 Sherpa wrapper 不做无调用方裁剪；只删除本仓库 StetASR 中无调用方的重复 recognizer。
  显式隔离标注可用于表达意图，约定见 [Coding Rules](../rules/CODING.md#swift-隔离标注)。

## 验证方法与边界

先用真实生产入口和可控依赖固定失败顺序，再运行同一测试验证修复。
红测涵盖媒体等待、延迟复制、纯转发时序、终止恢复、MCP 快速关开、refresh 所有权、激活失败、
模型并发加载、电平通知、HTTP 与 SDK 单请求取消和探针顺序；不以“没有崩溃”代替问题断言。
交叉审查额外捕获并修复了取消时的剪贴板恢复、目标应用查询 await 后的会话重查、SDK handler 到工具 Task 的取消传播；均补了回归。

测试覆盖位置：

- [macOS tests](../../StetMacTests)：MainActor/队列边界、通知传播、启动/取消、服务停止与失败恢复。
- [StetEngine tests](../../Packages/StetEngine/Tests)：历史写入顺序、专用 executor 和现有共享模型逻辑。
- [验证入口](../VALIDATION.md)：完整 macOS 测试、lint、架构检查及共享代码影响的 iOS 编译。

未进行真实媒体授权弹窗、失效物理音频设备、实际 FunASR 长推理、系统日历大数据量、退出后系统音量的人工验收。
AX 超时限制单次 IPC，不代表完整多属性读取耗时为 100ms。已经同步进入系统 API 的写入不能靠 Task 取消回滚。
本轮没有测量真实动画帧率或声称消除所有潜在并发问题。

## 集成验证结果

| 命令 | 结果 | 范围 |
| --- | --- | --- |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` | passed，退出码 0 | 629 个 Swift Testing 测试 / 97 个 suite，另 1 个 XCTest，全部通过；包含应用构建。 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StetEngine --scratch-path .build/concurrency-engine` | passed，退出码 0 | 共享包全部 72 个测试 / 12 个 suite。 |
| `make lint` | passed，退出码 0 | SwiftLint 398 文件零违规、Swift 格式和 Markdown 链接。 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 scripts/arch-check.py` | passed，退出码 0 | R0–R7 零违规。 |
| `scripts/validate-agent-entrypoints`、`git diff --check` | passed，退出码 0 | 仓库入口与 patch 空白检查。 |
| `make ios-build` | failed，退出码 2 | runtime 下载完成；本机只有 stable Xcode，缺少命令要求的 `/Applications/Xcode-beta.app`，因此未执行 iOS 27 编译。 |

三位子 agent 分别验证音频、服务、听写与持久化，并交叉审查；所有补丁统一集成后重新跑上述 macOS 全量测试。
表中的 iOS 结果保留此前附加尝试的记录，不作为 macOS 交付的阻塞项。按用户澄清已停止 iOS 组件下载、撤回临时 iOS 构建配置改动，原配置保持不变。
