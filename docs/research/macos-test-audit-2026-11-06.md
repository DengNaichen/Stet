# macOS 测试盘点与价值审查 — 2026-11-06

## 范围与结论

仅 macOS：`StetMacTests`、`StetMacUITests`，以及它们执行到的 macOS 生产代码。排除 iOS、Python 和共享包独立测试目标。基于 HEAD `fb82cea` 加调查时已有的未提交修改；不是干净提交的 CI 基线。本次未修改生产代码或测试。

- 默认测试集：**641 个测试方法**，99 个含测试声明的文件；640 个 Swift Testing `@Test` + 1 个 XCTest。含辅助代码共106个 Swift文件、18,376行。
- 10 个参数化方法展开为33次调用，因此本次实际调用为 **664 次**；数量对比使用641个方法，避免靠参数化膨胀。
- 本次执行：**627 方法通过、14 失败、0 个框架报告的跳过**（展开后650次通过、14失败）。
- macOS app 的本次可执行代码行覆盖率：**40.43%（14,484 / 35,829）**。有失败，不是全绿基线。
- 已确认 **4 个方法的唯一结果断言没有业务判别力**；另外17个明确改进候选，合计 **21/641 = 3.28%**。这是已定位候选的下限，不能说“只有3.28%有问题”或“21个完全没用”。
- 另有3个 UI 方法没有接入默认测试；其中2个为启动/截图模板，无产品行为断言。

## 执行证据与统计口径

实际运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test \
  CI_XCODEBUILD_FLAGS='-resultBundlePath /tmp/stet-macos-test-audit-20261106.xcresult'
xcrun xcresulttool get test-results summary --path /tmp/stet-macos-test-audit-20261106.xcresult
xcrun xccov view --report --json /tmp/stet-macos-test-audit-20261106.xcresult
```

`make` 退出码2，内层 xcodebuild 报65 / TEST FAILED。Swift Testing 640个测试、95个suite；另1个 XCTest成功。不能只看前面的 XCTest “All tests passed” 就认定整个测试集成功。

本机临时原始证据（不是长期归档）：结果包（本机临时文件 `/tmp/stet-macos-test-audit-20261106.xcresult`）、运行日志（本机临时文件 `/tmp/stet-macos-test-audit-20261106.log`）、测试摘要（本机临时文件 `/tmp/stet-test-summary.json`）、覆盖率JSON（本机临时文件 `/tmp/stet-coverage.json`）。

14个失败分布：AudioSignalAnalyzerTests 5个、DefaultAudioPostProcessorTests 8个、ConfigurableSpeechServiceTests 1个。共同错误为访问 `/Users/nd/Library/Application Support` 时的 Cocoa 512 / POSIX 20 “Not a directory”；最后一个测试期望 emptyTranscription，却收到该文件系统错误。音频分析直接初始化真实 FluidAudio VadManager（[实现](../../StetMac/Core/Audio/Processing/AudioSignalAnalyzer.swift#L34)），并非完全隔离的纯算法测试。检查时该目录在宿主机确实存在，**尚未诊断根因**，不能推断目录真的被破坏，也不能认定这14个测试无用。

## 覆盖率：只反映执行过，不代表验证过

| 范围 | 已执行行 / 可执行行 | 行覆盖率 |
|---|---:|---:|
| Stet.app（只含报告中映射到 app 的代码） | 14,484 / 35,829 | **40.43%** |
| StetMac/Core | 9,519 / 16,126 | 59.03% |
| StetMac/App | 2,048 / 3,429 | 59.73% |
| StetMac/Features（含大量 SwiftUI） | 2,052 / 15,033 | 13.65% |
| StetMac/Shared | 688 / 1,018 | 67.58% |
| StetVisuals.framework（单独目标） | 509 / 2,306 | 22.07% |

App汇总另含 StetApp.swift 和 ContentView.swift。Xcode所有target总计23.36%混入MCP、NIO等第三方代码，不适合作为本应用覆盖率。上述是可执行代码行比例，不是文件比例、分支覆盖率或功能完整率；条件编译未纳入、无可执行映射的源文件不在分母。应用启动也会产生覆盖，不能将每一条已执行行都视为有断言保护。

核心协调路径较高：ConfigurableSpeechService 90.79%、MacDictationWorkflowController 92.20%、MacDictationCaptureCoordinator 86.84%、MacPassiveListeningCoordinator 86.62%。但 MacAudioCaptureService 7.80%，真实采集边界远低于流程协调层。AudioSignalAnalyzer 27.99%、DefaultAudioPostProcessor 19.05%，受到本次失败影响。**高协调层覆盖不等于真实麦克风 → ASR → 目标应用写入的端到端流程已被验证。**

## 测试价值判据

逐文件扫描测试声明与断言，深入阅读可疑方法及对应生产实现，并检查是否已有更强的重复测试。没有对641个方法逐个做mutation testing，不能认证未列出者全都高价值。判据是：能否指出一种真实生产错误，使测试可靠失败；而非mock数量、测试长短或覆盖率。

## A. 无判别力结果断言：4 个

| 方法 | 问题 | 来源 |
|---|---|---|
| defaultInputDeviceReturnsDevice | `device != nil || device == nil` 永真，返回 nil 的坏实现仍通过 | [StetMacTests/Core/Audio/Devices/AudioDeviceProvidingTests.swift:15](../../StetMacTests/Core/Audio/Devices/AudioDeviceProvidingTests.swift#L15) |
| hasInputChannelsReturnsBoolForValidDevice | `hasChannels == true || hasChannels == false` 永真；没有设备时直接 return | [StetMacTests/Core/Audio/Devices/AudioInputDeviceManagerTests.swift:62](../../StetMacTests/Core/Audio/Devices/AudioInputDeviceManagerTests.swift#L62) |
| sharedInstanceExists | `shared` 是非 Optional `static let`，`monitor != nil` 无业务判别力 | [StetMacTests/Core/Audio/Devices/AudioDeviceChangeMonitorTests.swift:9](../../StetMacTests/Core/Audio/Devices/AudioDeviceChangeMonitorTests.swift#L9)；生产定义 [StetMac/Core/Audio/Devices/AudioDeviceChangeMonitor.swift:7](../../StetMac/Core/Audio/Devices/AudioDeviceChangeMonitor.swift#L7) |
| addObserverReturnsValidUUID | `UUID.uuidString` 非空由 Foundation UUID 类型保证；即使 addObserver 从未存储 callback 也通过 | [StetMacTests/Core/AppBranch/AppBranchMonitorObserverTests.swift:8](../../StetMacTests/Core/AppBranch/AppBranchMonitorObserverTests.swift#L8) |

## B. 只检查不崩溃/完成，不验证状态：6 个

这组不是零价值：可以捕获 crash/deadlock，在 TSan 开启时还可能暴露 race。但普通测试通过不能证明声称的线程安全或资源生命周期正确。

1. concurrentRemoveObserverCallsAreThreadSafe（末尾 `#expect(true)`）— [StetMacTests/Core/AppBranch/AppBranchMonitorConcurrencyTests.swift:33](../../StetMacTests/Core/AppBranch/AppBranchMonitorConcurrencyTests.swift#L33)
2. concurrentSetExcludedBundleIDCallsAreThreadSafe（末尾 `#expect(true)`，随机输入）— [StetMacTests/Core/AppBranch/AppBranchMonitorConcurrencyTests.swift:77](../../StetMacTests/Core/AppBranch/AppBranchMonitorConcurrencyTests.swift#L77)
3. concurrentStartStopCallsAreSafe（无状态或注册清理断言）— [StetMacTests/Core/AppBranch/AppBranchMonitorConcurrencyTests.swift:54](../../StetMacTests/Core/AppBranch/AppBranchMonitorConcurrencyTests.swift#L54)
4. removeObserverHandlesInvalidUUIDGracefully（无断言）— [StetMacTests/Core/AppBranch/AppBranchMonitorObserverTests.swift:18](../../StetMacTests/Core/AppBranch/AppBranchMonitorObserverTests.swift#L18)
5. startMonitoringCanBeCalledMultipleTimes（无断言）— [StetMacTests/Core/Audio/Devices/AudioDeviceChangeMonitorTests.swift:15](../../StetMacTests/Core/Audio/Devices/AudioDeviceChangeMonitorTests.swift#L15)
6. stopMonitoringWithoutStartIsHarmless（无断言）— [StetMacTests/Core/Audio/Devices/AudioDeviceChangeMonitorTests.swift:24](../../StetMacTests/Core/Audio/Devices/AudioDeviceChangeMonitorTests.swift#L24)

应验证 observer 是否仍被调用、最终订阅注册/删除是否平衡、排除规则是否最终生效。尤其 AudioDeviceChangeMonitor 生产代码有 monitorClientCount、listener 注册/移除，现有两个生命周期测试即使 start/stop 变成空函数也会通过：[StetMac/Core/Audio/Devices/AudioDeviceChangeMonitor.swift:7](../../StetMac/Core/Audio/Devices/AudioDeviceChangeMonitor.swift#L7)。

## C. 硬件为空即可通过：7 个

- SystemAudioDeviceProviderTests.allInputDevicesReturnsDeviceList — [StetMacTests/Core/Audio/Devices/AudioDeviceProvidingTests.swift:8](../../StetMacTests/Core/Audio/Devices/AudioDeviceProvidingTests.swift#L8)。`[].allSatisfy` 为 true。
- AudioInputDeviceManagerTests 以下 6 个：defaultInputDeviceIDReturnsValidIDOrNil、defaultOutputDeviceIDReturnsValidIDOrNil、defaultInputDeviceReturnsDeviceOrNil、builtInInputDeviceReturnsBuiltInOrNil、defaultOutputDeviceReturnsDeviceOrNil、allInputDevicesReturnsNonEmptyListOnMostSystems — [StetMacTests/Core/Audio/Devices/AudioInputDeviceManagerTests.swift:9](../../StetMacTests/Core/Audio/Devices/AudioInputDeviceManagerTests.swift#L9)。

前五个仅 `if let` 后断言；最后一个允许空数组，且 allSatisfy 后的循环重复同一检查。不能因为测试名称含 “NonEmpty” 就认为验证了设备枚举。若底层所有查询退化为 nil/[]，这 7 个仍通过。依赖机器硬件本身合理，但需在固定硬件环境断言前置条件，或将枚举/错误映射分离为可注入的行为测试；不能贸然在任意 CI 硬编码必须有麦克风。

## D. 仅复述 Swift 自动成员初始化：3 个

- customPlanRetainsAllProperties — [StetMacTests/Core/Audio/Processing/SpeechEnhancementTypesTests.swift:23](../../StetMacTests/Core/Audio/Processing/SpeechEnhancementTypesTests.swift#L23)
- resultRetainsOutputURLAndRewriteFlag — [StetMacTests/Core/Audio/Processing/SpeechEnhancementTypesTests.swift:52](../../StetMacTests/Core/Audio/Processing/SpeechEnhancementTypesTests.swift#L52)
- resultCanIndicateNoRewrite — [StetMacTests/Core/Audio/Processing/SpeechEnhancementTypesTests.swift:60](../../StetMacTests/Core/Audio/Processing/SpeechEnhancementTypesTests.swift#L60)

生产类型只有 `let` 属性和 Swift 自动合成 memberwise init，无转换/校验/分支：[StetMac/Core/Audio/Processing/SpeechEnhancementTypes.swift:3](../../StetMac/Core/Audio/Processing/SpeechEnhancementTypes.swift#L3)。测试大部分是在确认语言的赋值语义。与业务默认值不同：disabledPlanHasCorrectDefaults 固定了音频参数契约，不能仅因小或简单就删除。

AppInfo 的字段初始化测试也偏低价值，但其 init 是手写映射，仍能抓参数写错；没有算入这个严格的 3 个计数。其 Equatable 是手写的四字段比较，因此一组 equality tests 不是“测 Swift 编译器”，不应误删：[StetMac/Core/AppBranch/AppInfo.swift:67](../../StetMac/Core/AppBranch/AppInfo.swift#L67)。

## E. 名称声称错误处理，实为已有正常路径重复：1 个

startMonitoringHandlesInitializationErrorsGracefully 没有注入任何错误，只正常 start 后检查 isMonitoring：[StetMacTests/Core/AppBranch/AppBranchMonitorErrorHandlingTests.swift:14](../../StetMacTests/Core/AppBranch/AppBranchMonitorErrorHandlingTests.swift#L14)。与 startMonitoringSetsIsMonitoringToTrue 使用同样 harness，后者还额外验证 observerCount==1：[StetMacTests/Core/AppBranch/AppBranchMonitorTests.swift:8](../../StetMacTests/Core/AppBranch/AppBranchMonitorTests.swift#L8)。应合并或真正制造失败场景。

## 另外一处结果可信度问题（不加入上述 21 个）

transcribesRealGGUFAudioWithHotwordsWhenOptedIn 在音频文件不存在时直接 return，测试会表现为通过而非明确跳过；存在时也只验证文本非空，无法验证转录准确性或热词有效性：[StetMacTests/Core/FunASR/FunASRNanoTranscriptionServiceTests.swift:158](../../StetMacTests/Core/FunASR/FunASRNanoTranscriptionServiceTests.swift#L158)。这属于“看似覆盖真实 ASR，实际默认可能完全没运行”。

## 避免误判：这些小测试/使用 mock 的测试仍有明确价值

- AudioDeviceSelectionManagerTests.refreshDevicesFallsBackToBuiltInButPreservesExternalPreference 模拟 USB 设备消失，同时验证内置回退与持久化偏好保留；这是实际用户行为，不是自测 mock：[StetMacTests/Core/Audio/Devices/AudioDeviceSelectionManagerTests.swift:28](../../StetMacTests/Core/Audio/Devices/AudioDeviceSelectionManagerTests.swift#L28)。
- PasteboardRestoreCoordinatorTests 使用真实独立 NSPasteboard + 可控时钟，保护快速连续粘贴后的原剪贴板恢复和用户主动复制不被覆盖：[StetMacTests/Core/Clipboard/PasteboardRestoreCoordinatorTests.swift:44](../../StetMacTests/Core/Clipboard/PasteboardRestoreCoordinatorTests.swift#L44)。
- MacDictationCaptureCoordinatorTests.cancelledPasteRestoresOnlyItsOwnClipboardOverride 参数化用户是否在中途复制，验证取消后恢复归属：[StetMacTests/App/Workflows/MacDictationCaptureCoordinatorTests.swift:624](../../StetMacTests/App/Workflows/MacDictationCaptureCoordinatorTests.swift#L624)。
- OpenAIPrimitiveTests 的错误映射虽小，却区分 provider/HTTP status/解码失败，可抓真实回归：[StetMacTests/Core/AIProviders/OpenAICompatible/OpenAIPrimitiveTests.swift:11](../../StetMacTests/Core/AIProviders/OpenAICompatible/OpenAIPrimitiveTests.swift#L11)。
- TestClockTests 是测试基础设施但有明确任务唤醒/取消语义，不能按“测试 helper”归为没用：[StetMacTests/Support/TestClockTests.swift:7](../../StetMacTests/Support/TestClockTests.swift#L7)。
- initializeAcceptsStreamableHTTPAcceptHeader 没有本地 #expect，但调用的 initialize helper 内有状态码与协议断言，不能通过搜索“无断言”误判：[StetMacTests/Core/MCP/StetMCPProtocolServerTests.swift:489](../../StetMacTests/Core/MCP/StetMCPProtocolServerTests.swift#L489)。
- activateRecordingWindowWithoutStartingDoesNotThrow 只有 `try` 调用，异常自动使测试失败，仍是明确 no-throw 契约：[StetMacTests/Core/Audio/Capture/MacCaptureAudioFileRecorderTests.swift:22](../../StetMacTests/Core/Audio/Capture/MacCaptureAudioFileRecorderTests.swift#L22)。

没有发现足以量化为全仓库结论的“多数测试只测 mock 自己”。本次可证明的是少量具体低价值/弱断言集中于 Audio Devices 和 AppBranch 边缘测试；主听写、取消、粘贴恢复、设备回退有大量行为断言。应以能否抓住一个具体错误为审查标准，而不是测试行数、mock 数量或覆盖率。


## 默认流程没有真正的 UI 端到端保护

`StetMacUITests` 的3个方法：`testExample` 仅launch，`testLaunch` 仅launch+截图而不比较，`testLaunchPerformance` 测启动耗时，但未找到仓库基线且默认不运行。前两者保留启动smoke/人工看截图的有限价值，不能算验证听写或粘贴功能。

来源：[启动与性能模板](../../StetMacUITests/StetUITests.swift#L26)、[截图模板](../../StetMacUITests/StetUITestsLaunchTests.swift#L21)。这3个没有消耗当前默认测试的执行时间，问题在于它们并未提供期望中的UI回归保护。

默认 [scheme](../../Stet.xcodeproj/xcshareddata/xcschemes/Stet.xcscheme#L44) 已启用coverage，但Testables只包含StetTests；[Makefile](../../Makefile#L49) 进一步限定only-testing:StetTests；[CI](../../.github/workflows/monorepo-ci.yml#L167) 调用make test，没有发布xccov摘要或上传xcresult。共享包独立测试也没有在此默认命令中运行，但共享生产代码仍可能被macOS测试间接执行。

本次真实ASR opt-in方法0.003秒就显示通过，默认音频fixture不存在；源码缺文件直接return，解释了为什么摘要0 skipped也不能证明所有真实集成都执行过。该方法未计入21个弱断言候选。

## 判断

现有证据不支持“多数测试在测没用的东西”。明确的弱断言集中在设备枚举、observer与类型字段回读；听写取消、粘贴恢复、外接设备回退等有可解释的用户行为保护。最值得关注的是 **通过不代表做过验证**（永真、空集合、提前return）和 **高覆盖的模拟协调层与低覆盖真实边界之间的缺口**。14个失败需要恢复可信基线；21个候选适合逐项强化或合并，而非为了减少数量一概删除。此次仅调查，不执行删改。
