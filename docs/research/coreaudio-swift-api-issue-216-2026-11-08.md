# Issue 216：原生 Core Audio Swift API 调查

## 结论与证据边界

[Issue 216](https://github.com/DengNaichen/Stet/issues/216) 的替换方向可行，主要收益是移除设备属性读取中的手工内存管理，而非已经测得的性能改善。保留 Stet 的设备值类型、选择规则和线程边界，仅替换查询与监听适配层。

调查日期：2026-11-08。检查主 checkout `a1cffba291fa47b6218c1ddcb8edccc7fbd9bf77`；文档 worktree 基于 `58f4ee0`，设备目录、设备测试、会议系统采集和 Xcode 项目文件在两者间没有差异。设备目录与 issue 引用的 `b327f54` 也无差异。以下调查部分记录实施前状态；用户随后授权的实现与验证见文末。调查本身不是硬件验收。

## 现有契约

[AudioInputDeviceManager](../../StetMac/Core/Audio/Devices/AudioInputDeviceManager.swift) 的兼容要求如下：

| 操作 | 当前失败处理 | 迁移要求 |
| --- | --- | --- |
| 默认输入、默认输出 ID | 读取失败或 ID 为 0 时返回 nil，并记日志 | 保留 nil 与 unknown ID 检查 |
| 设备枚举 | 列表读取失败返回空数组 | 不向现有调用方抛错 |
| 输入通道 | stream configuration 读取失败返回 false | 保持任一 buffer 的通道数大于零这一条件 |
| 名称与 UID | 读取失败跳过该设备；名称为空也跳过 | 每个设备独立处理错误，不能让一个失败清空整个列表 |
| transport | 读取失败使用 unknown | 不应由于 transport 抛错而丢弃设备 |

[本地 AudioHardwareDevice](../../StetMac/Core/Audio/Devices/AudioHardwareDevice.swift) 是 `Equatable, Sendable` 值快照。建议保留它，在适配层用 `CoreAudio.AudioHardwareDevice` 限定系统类型名，避免把有动态属性和监听行为的系统对象传播到 UI、resolver 和录音控制层。

[选择解析器](../../StetMac/Core/Audio/Devices/AudioDeviceSelectionResolver.swift) 优先使用指定 UID；缺失时回退且保留偏好。默认路线依次为内建、可用的系统默认输入、类型优先级最高的设备。因此不能简单把设备列表按 transport 排序后取首个。具体类型优先级及 handheld Apple device 名称判定仍由本地值类型负责。

## 监听范围与风险

[AudioDeviceChangeMonitor](../../StetMac/Core/Audio/Devices/AudioDeviceChangeMonitor.swift) 只订阅 `kAudioHardwarePropertyDevices`，通过主队列发送通知。它没有订阅默认输入或默认输出变化。多个调用方共用计数；首次 start 注册，最后一次 stop 注销，deinit 尝试清理。注册失败会回退计数；注销失败会记录日志但仍清空本地状态。

原生 Swift listener 不能消除这套应用级引用计数，也不能证明失败路径已正确。迁移需要持有系统对象及 delegate，以相同对象、属性、队列和 delegate 配对注销，避免局部变量释放、重复注册、回调强引用环和 MainActor 越界。是否改善既有注销失败后的状态处理，应明确写为行为修复，而非宣称纯机械替换等价。

[MeetingSystemAudioCapture](../../StetMac/Core/Audio/Capture/MeetingSystemAudioCapture.swift) 另在 controlQueue 上监听默认输出和输出采样率，回调会停止并重新启动系统音频采集。该链路属于 [Issue 93](https://github.com/DengNaichen/Stet/issues/93)，不应借此次重构改为主队列或重写恢复流程。

因此 issue 中“默认设备变化行为保持一致”的验收应区分：默认设备查询结果、设备 UI 的列表通知、会议系统音频恢复。给列表 monitor 新增默认设备订阅是新增行为，不是现有行为的迁移。

## 测试与实施边界

现有 [resolver 测试](../../StetMacTests/Core/Audio/Devices/AudioDeviceSelectionResolverTests.swift) 和 [selection manager 测试](../../StetMacTests/Core/Audio/Devices/AudioDeviceSelectionManagerTests.swift) 覆盖指定 UID、内建优先、外接缺失回退、重连恢复及偏好保存，可以继续保护规则。

现有 [查询测试](../../StetMacTests/Core/Audio/Devices/AudioInputDeviceManagerTests.swift) 多数允许 nil/空数组；名为 `allInputDevicesReturnsNonEmptyListOnMostSystems` 的测试实际上没有断言非空。[监听测试](../../StetMacTests/Core/Audio/Devices/AudioDeviceChangeMonitorTests.swift) 仅调用 start/stop 和检查通知名，没有断言注册次数、注销次数或通知到达。它们通过不能证明迁移等价。

建议实施时为 listener 注册边界提供一个小型可注入适配器，验证两次 start 只注册一次、第一次 stop 不注销、最后 stop 只注销一次、注册失败可重试、额外 stop 无操作、销毁清理、回调通知与主队列语义。属性读取测试应覆盖单设备中途消失、transport 失败回退和列表部分成功，避免只测试伪造结果而绕过新适配层。

[音频输入设备 spec](../specs/audio-input-devices.md) 已记录听写使用缓存选择而会议开始前主动刷新的差异。切换查询 API 不会自动修复关闭设备 UI 后拔出外接麦克风的缓存问题；不要将其计为本次重构已解决。

实施顺序建议：先改查询适配并比较真实设备快照，再改列表监听并验证多调用方生命周期；保留 resolver、selection manager 和会议恢复逻辑。最低系统与语言模式以 [Xcode 项目](../../Stet.xcodeproj/project.pbxproj) 为准：macOS 15、Swift 5、默认 MainActor。完成后仍须 stable Xcode 构建和相关测试，以及内建、可用外接/蓝牙设备的热插拔、默认切换和实际录音记录。

## 查询可以覆盖

Apple 的 [AudioHardwareSystem](https://developer.apple.com/documentation/coreaudio/audiohardwaresystem)、[AudioHardwareDevice](https://developer.apple.com/documentation/coreaudio/audiohardwaredevice)、[AudioHardwareObject](https://developer.apple.com/documentation/coreaudio/audiohardwareobject) 都标注 macOS 15.0 可用。stable SDK 声明和 Swift 5 模式双架构编译验证与此一致。

| 当前目的 | 原生接口 | 注意 |
| --- | --- | --- |
| 枚举设备 | `try AudioHardwareSystem.shared.devices` | 返回所有设备，仍需输入过滤 |
| 默认输入/输出 | `try system.defaultInputDevice` / `defaultOutputDevice` | 返回 optional；nil 和 throw 都要映射既有契约 |
| ID | `device.id` | AudioObjectID，不抛错 |
| UID | `try device.uid` | 继承自 AudioHardwareClock |
| 名称 | `try device.name` | 继承自 AudioHardwareObject；旧代码用旧式 C 字符串属性，需核查特殊设备名称 |
| transport | `try device.transportType` | 继承自 AudioHardwareClock；失败仍回退 Unknown |
| 输入能力 | `try device.inputStreamConfiguration` | `[AudioBuffer]`；保留 `contains { $0.mNumberChannels > 0 }` 语义，不改为是否有 stream 或是否可作默认输入 |
| UID 查找 | `try system.device(forUID:)` | 存在，但当前注释掉的 UID 查找无需复活 |

设备单项读取失败应跳过单项，不能一个总 `do/catch` 因一个设备消失就丢弃整张列表。原生 API 仍是多个独立属性读取，不是原子快照。

## 监听不是 closure 的直接替换

[addListener](https://developer.apple.com/documentation/coreaudio/audiohardwareobject/addlistener(forproperties:dispatchqueue:)) 和 [removeListener](https://developer.apple.com/documentation/coreaudio/audiohardwareobject/removelistener(forproperties:dispatchqueue:)) 都 throws，输入属性地址数组以及可选 dispatch queue。监听需要先设置 [delegates](https://developer.apple.com/documentation/coreaudio/audiohardwareobject/delegates)；[PropertyListenerDelegate](https://developer.apple.com/documentation/coreaudio/propertylistenerdelegate) 接收 `propertiesChanged(properties:)`。

Apple 明确说明：传入的 queue 被保留至配对注销；普通事件异步投递，IO 上下文事件有同步例外；queue=nil 会直接调用 delegate。注销应提供对应 queue，不能因为类型为 Swift 就省掉现有主线程/控制队列跳转。

建议实现推论（非 Apple 保证）：由每个 monitor 持有独立 system wrapper / delegate bridge，bridge 弱引用 monitor；显式配对注册和注销，清除 delegate，避免共享 singleton 的 delegates 被不同消费者覆盖。SDK 暴露 `AudioHardwareSystem(id:)`，已编译验证。API 没有提供订阅 token、多调用方计数或停止后排队回调失效机制，现有应用逻辑仍需保留。批量 add 是否全部成功/失败以及 deinit 的自动注销契约，公开文档没有保证；不要依赖未记录行为。

SDK 将 AudioHardwareObject/System/Device 声明为 `@unchecked Sendable`；PropertyListenerDelegate 没有 MainActor 或 Sendable 要求。这不是放宽应用层共享可变状态隔离的依据。

父代理已确认当前主 monitor 只订阅设备列表变化，会议另有 controlQueue 上的默认输出监听。因此默认设备变化的验收需明确覆盖哪个 monitor；此次迁移不应悄然新增系统默认输入/输出订阅来改变产品行为。

## 实测

stable Xcode `/Applications/Xcode.app` 的 Swift 6.3.3，Swift 5 language mode。SDK interface 在 `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/swift/CoreAudio.swiftmodule/arm64e-apple-macos.swiftinterface`，重点行 12–90（system 与 delegate）、462–526（device）、611–662（object）、680–689（clock uid/transport）。

临时 probe `/tmp/stet-216-probe.swift` 直接链接仓库真实 AudioInputDeviceManager.swift 和 AudioHardwareDevice.swift，逐项比较原生实现与旧实现的设备数组（包含 id/uid/name/transport）、全部设备输入能力、默认输入输出 ID；未录音、未修改默认设备、未注册监听。监听函数仅参与编译。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 5 -target arm64-apple-macos15.0 /tmp/stet-216-probe.swift StetMac/Core/Audio/Devices/AudioHardwareDevice.swift StetMac/Core/Audio/Devices/AudioInputDeviceManager.swift -o /tmp/stet-216-probe
/tmp/stet-216-probe
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -swift-version 5 -target x86_64-apple-macos15.0 -typecheck /tmp/stet-216-probe.swift StetMac/Core/Audio/Devices/AudioHardwareDevice.swift StetMac/Core/Audio/Devices/AudioInputDeviceManager.swift
```

全部退出 0。运行输出：

```text
run 1: PASS inputDevices=5 allDevices=8, values/input-capability/default IDs equal
run 2: PASS inputDevices=5 allDevices=8, values/input-capability/default IDs equal
run 3: PASS inputDevices=5 allDevices=8, values/input-capability/default IDs equal
```

限制：仅当前机器/当前设备快照一致；没有覆盖热插拔、Bluetooth 变化、listener 生命周期、macOS 15 真机运行或 Intel 真机运行，也没有证明集成后录音可用。此次 arm64 实际编译+运行，x86_64 仅 typecheck。

## 同日实施与验证

用户在调查后授权实施。工作保留在 `issue-216-coreaudio-research` 分支。实现只改动查询 manager、设备列表 monitor 及其测试；本地值类型、选择 resolver、selection manager、共享包和会议系统恢复代码没有修改。

- 查询使用原生 system/device 属性，保留单设备失败跳过、transport 失败回退 unknown、默认设备缺失返回 nil。manager 从 315 行减为 83 行，其中包含删除约 74 行原有注释旧代码，不能把净行数差全部算作活跃代码简化。
- monitor 持有独立系统 wrapper，用 `PropertyListenerDelegate` 桥接主队列通知，保留多调用方计数，配对注册与注销相同属性及队列。
- 两处生命周期防护：最后一个客户端停止后忽略排队通知；注销失败时保留注册状态以供重试，避免后续 start 重复注册。这是明确的失败路径改进，并非声称与旧失败行为逐字等价。
- 测试直接替换 SDK 开放类的属性与监听方法，无额外生产协议。覆盖部分设备属性失败、无输入通道、缺失/unknown 默认设备、注册共享、注册失败重试、注销失败重试、delegate 释放及主队列通知。

已执行的验证：

| 检查 | 结果与边界 |
| --- | --- |
| stable Xcode `make build` | 通过；最初因缺少 Metal Toolchain 失败，使用 `xcodebuild -downloadComponent MetalToolchain` 安装后重跑成功 |
| Xcode 定向测试 | 8 个 suite、37 个测试通过，0 失败、0 跳过；xcresult summary 已确认实际执行数量，包含全部设备 suite 和 MacCaptureAudioDevicePlannerTests |
| `make lint` | 通过，SwiftLint 404 文件零违规，Swift 格式和文档链接通过 |
| `python3 scripts/arch-check.py --summary` | 通过，新增及基线违规均为 0 |
| 独立 SwiftPM 测试 harness | 直接引用真实生产文件和仓库测试，29 个测试通过；不是 App 工程集成测试的替代 |
| 修改后的查询与 HEAD 旧查询对比 | 当前机器连续 3 次完全一致，5 个输入设备；比较设备值、默认输入/输出值与 ID、所有设备输入能力 |
| 原生 listener smoke | 真实 manager 两次 start、两次 stop 完成；未主动触发硬件事件，不能证明回调验收 |
| Intel 目标 | 修改的设备生产文件以 Swift 5、默认 MainActor、`x86_64-apple-macos15.0` 类型检查通过；没有 Intel 真机运行 |

本次没有更改系统默认音频设备，没有启动录音。仍未验收物理热插拔、蓝牙变化、真实硬件回调及集成后的录音结果；不将查询对比或编译通过当作这些验收。

Xcode 定向测试命令（stable Xcode）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Stet.xcodeproj -scheme Stet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  -only-testing:StetTests/AudioDeviceChangeMonitorTests \
  -only-testing:StetTests/AudioInputDeviceManagerTests \
  -only-testing:StetTests/AudioInputDeviceQueryContractTests \
  -only-testing:StetTests/AudioDeviceSelectionResolverTests \
  -only-testing:StetTests/AudioDeviceSelectionManagerTests \
  -only-testing:StetTests/AudioHardwareDeviceTests \
  -only-testing:StetTests/SystemAudioDeviceProviderTests \
  -only-testing:StetTests/MacCaptureAudioDevicePlannerTests test
```

## 变异验证与测试收敛

此前的 37 个测试通过不能证明检错能力。按用户要求，使用[变异脚本](../../scripts/test-audio-device-mutations.py)对实际生产源码的隔离副本施加 20 个定向变异。每次只改一个变量，运行真实的查询契约与监听测试；编译错误、超时不计为捕获，只有构建成功后的测试断言失败才记为 killed。运行前和全部恢复后的基线均必须通过。

[修正前证据](coreaudio-mutations-2026-11-08-before.json)为 **17/20**，发现三个存活变异：

| 存活变异 | 原测试为什么漏掉 | 修正 |
| --- | --- | --- |
| 注册失败后不回退调用方计数 | 重试前的 stop 恰好抵消错误计数 | 改为失败后直接重试，最后一次 stop 必须注销 |
| 默认输入设备值始终返回 nil | 只有元数据错误、缺失及 unknown 默认设备的断言，没有健康默认输入的断言 | 同一用例补上健康输入值，并保留 ID 不依赖元数据的检查 |
| 注销失败后仍向零调用方发送通知 | 只检查注册/注销次数，没有在失败停止后触发回调 | 同一用例验证停止后不通知，恢复调用方后通知恢复 |

删除查询文件中 6 个依赖宿主设备且允许 nil/空列表的 smoke 用例，以及监听文件中 2 个重复用例。这两个文件从 **16 个测试收敛为 8 个**，不是通过增加用例数量来追求更好看的统计。

[修正后证据](coreaudio-mutations-2026-11-08-after.json)为 **20/20**，没有编译无效项或超时；恢复基线通过。范围包括默认设备、输入通道过滤、设备属性失败、transport 回退、列表部分失败、重复注册、过早注销、失败重试、通知投递、强引用泄漏、deinit 清理、订阅属性及队列。

这只是所选 20 个语义变异的结果，不是全量变异覆盖，也不证明真实 Core Audio 驱动或硬件行为。测试替换 SDK 属性/监听方法，执行真实 manager/monitor；真实硬件回调、热插拔、蓝牙及录音仍需另行验收。

可复现命令：

```sh
python3 scripts/test-audio-device-mutations.py --report /tmp/stet-audio-mutations.json
```

最终在 App 工程中重跑设备与采集规划定向测试：**7 个 suite、29 个测试通过**（比前一轮少 8 个）。生产代码本轮没有改变。证据 JSON 包含生产和测试文件 SHA-256 以及各变异触发的断言，临时完整构建日志路径由脚本打印。
