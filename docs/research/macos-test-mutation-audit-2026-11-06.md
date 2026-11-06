# macOS 测试严格审查与变异实验 — 2026-11-06

## 结论与范围

只审 macOS 默认 `StetTests` 的641个方法，以及3个未接入默认scheme的UI方法。此报告深化[首轮盘点](macos-test-audit-2026-11-06.md)，不把原先的弱断言筛查冒充变异证明。

本轮做了全量声明/断言静态筛查、可疑测试与生产实现的深入检查，并在隔离副本中实际运行24个定向生产行为变异。方法是对有价值行为故意引入错误，重新构建，再观察真实断言失败；没有改断言或mock来制造红灯。

| 层次 | 数量与解释 |
|---|---|
| 原默认测试方法 | 641（640 Swift Testing + 1 XCTest） |
| 本轮实际覆盖的变异实验测试方法并集 | 124；同一方法在不同变异下会重复运行 |
| 有效变异 | 24；13被测试发现，11存活 |
| 删除前至少发现一个变异的方法 | 38，其中8个是可被更强测试替代的重复保护 |
| 删除的默认方法 | **15 = 7个无独立业务判别力 + 8个冗余** |
| 其他删除 | 1个未运行的UI启动模板 |
| 保留且有具体加强理由的方法 | **29**；不等于29个完全没用 |
| 暂缓删除判断 | 6（3个新增删除建议暂缓、3个契约/归属不确定） |
| 其余静态保留 | 591；只表示本轮未证明该删，不是591个已获动态认证 |

**24是定向选取的行为变异，不是随机样本。13/24不能作为全应用的变异分数，更不能说641个测试的45.8%无效。** 一个变异被整组漏掉表示某个行为缺口；不表示该组每个测试都无用。一个测试抓到变异也不保证它有独立价值——可能被另一个测试完全包含。

静态范围内逐方法判定：[清单JSON](macos-test-mutation-audit-2026-11-06-inventory.json)。原始行号对应删除前快照；`retain_not_dynamically_certified`明确表示未动态认证。普通保留项只做声明/断言筛查，不能声称641条都经过同等深度的生产代码审查。

## 找到的讨论与采用的标准

最接近用户描述的是 Michael Bromley **2026-09-07** 的 [The Problem With Your AI Tests 原文](https://github.com/michaelbromley/michaelbromley.co.uk/blob/master/content/blog/2026-09-07-the-problem-with-your-ai-tests.md)，有对应的 [Hacker News讨论](https://news.ycombinator.com/item?id=49599049)。它批评自测setup、永真/弱断言和无论分支都通过。HN帖子规模很小，不能包装成业界共识，也不能确认就是用户记忆中的原帖。

更具体的近期案例是 **2026-10-13** 的 [mattpocock/skills #1269](https://github.com/mattpocock/skills/issues/1269)：重放测试删掉了真实bug的触发参数，恢复真实fixture才得到有效红灯。这是项目报告，不是“垃圾测试占比”的普遍统计。未引用未经核实的X帖子。

方法依据：

- Google 的 [Code Coverage Best Practices](https://testing.googleblog.com/2020/08/code-coverage-best-practices.html)：执行覆盖不等于正确性验证，coverage适合发现未执行风险，不能只追数字。
- Stryker 官方 [mutant states](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/) 与 [equivalent mutants](https://stryker-mutator.io/docs/mutation-testing-elements/equivalent-mutants/)：编译/运行环境错误与行为杀伤分开；等价变异不能当测试失败。这里引用方法，不建议将其JS/.NET工具直接用于Swift。
- [ICSE 2021原始研究](https://homes.cs.washington.edu/~rjust/publ/mutation_testing_practices_icse_2021.pdf)支持选择性、与变更相关的变异作为改进测试证据，并不证明任何具体测试可删。

本轮采用的删除条件：无独立业务断言且没有独有契约，或保留的更强用例覆盖相同契约，并在相关实测变异上仍能抓错。Mock调用次数可能保护委托/资源生命周期；no-throw可能保护合法API使用；合成Equatable也可能表达领域相等语义。这些都不按形式一刀切删除。

## 实验控制与局限

- 副本：`/tmp/stet-mutation-audit-20261106`，复制调查时工作区（含用户未提交改动），独立DerivedData；复用已下载的SourcePackages。变异不写入主工作区生产文件。
- 副本初始全量基线：641方法，627通过、14失败；与首轮相同的音频/VAD文件系统错误。每个选定suite中的原始测试都在该基线通过，14个既有失败没有进入任何变异的kill计数。
- 每次只应用一个变异，重新执行xcodebuild test，解析xcresult具体方法的断言失败，finally还原生产文件。24个变异均成功编译并实际发现非零测试，没有编译失败或空测试集伪装成kill。
- 样本包含清空监听、设备恒空、忽略偏好、破坏剪贴板保护等可观察行为变化；不是无语义影响的变量重命名。M19加载写回还可能改变通知授权触发时机，不能因最终Bool相同就视为等价。
- 变异结果只声称所选suite范围，不把定向存活称作“全仓库任何测试都抓不到”。未运行线程sanitizer、真实麦克风/ASR/AX端到端测试。
- 期间其他会话产生`d9878e7`和`0b885e5`架构提交。本会话不提交，保留其他工作；变异对照始终基于固定副本以避免并行生产修改污染因果关系。

可复现定义、每次结果、具体失败方法与通过方法：[实验JSON](macos-test-mutation-audit-2026-11-06-evidence.json)。临时目录还保存`run_mutations.py`、`prune_tests.py`、所有xcresult与日志；JSON保存生产文件、替换锚点/函数体、测试范围，可在原始快照上复现。原始可执行产物未加入Git。

## 实际变异结果

| ID | 故意引入的错误 | 原测试结果 |
|---|---|---|
| M01 | 系统provider枚举永远返回空设备 | 存活，2/2过 |
| M02 | 系统provider默认输入永远nil | 存活，2/2过 |
| M03 | CoreAudio默认输入/输出ID永远nil | 存活，9/9过 |
| M04 | 设备枚举永远空数组 | 存活，9/9过 |
| M05 | 每个设备都报告没有输入通道 | 存活，9/9过 |
| M06 | 设备变动监听start完全no-op | 存活，4/4过 |
| M07 | 设备变动监听stop完全no-op | 存活，4/4过 |
| M08 | addObserver只返回UUID，不保存callback | 发现，3个方法失败 |
| M09 | removeObserver完全不删除 | 发现，2个方法失败 |
| M10 | 忽略排除应用设置 | 发现，5个方法失败 |
| M11 | 录音文件稳定等待完全no-op | 存活，7/7过 |
| M12 | 麦克风选择不持久化 | 发现，2个方法失败 |
| M13 | 用户复制新内容后仍强制恢复旧剪贴板 | 发现，3个方法失败 |
| M14 | 内置麦克风默认路由反而优先选外置 | 发现，5个方法失败 |
| M15 | 听写面板scale改为0 | 发现，2个方法失败 |
| M16 | 听写面板bottomInset改为-1 | 发现，2个方法失败 |
| M17 | 引导页语言切换不保存首选语言 | 存活，2/2过 |
| M18 | 用户关闭reveal仍显示结果面板 | 存活，22/22过 |
| M19 | load期间开启写回偏好 | 存活，3/3过 |
| M20 | ChatGPT不再识别为AI应用 | 发现，7个方法失败 |
| M21 | AntiGravity不再识别为AI应用 | 发现，2个方法失败 |
| M22 | 应用monitor的start完全no-op | 发现，9个方法失败 |
| M23 | Xcode不再识别为AI应用 | 发现，2个方法失败 |
| M24 | 明明存在的首选外置麦克风却被丢弃 | 发现，4个方法失败 |

特别值得保留的测试：剪贴板外部变化保护、observer真正收到通知/移除后不再通知、外置设备暂时消失后保存用户偏好。它们不是“在测mock自己”，实测会对真实错误变红。

## 实际精简的测试

**15个默认测试 + 1个未接入默认流程的UI模板**，不改生产行为。

| 文件/组 | 删除方法 | 依据/保留保护 |
|---|---|---|
| AudioDeviceProvidingTests | defaultInputDeviceReturnsDevice | `nil或非nil`永真；M02存活 |
| AudioInputDeviceManagerTests | hasInputChannelsReturnsBoolForValidDevice | `true或false`永真；M05存活 |
| AudioDeviceChangeMonitorTests | sharedInstanceExists | 非Optional单例!=nil由类型保证；其他生命周期入口仍保留 |
| AppBranchMonitorObserverTests | addObserverReturnsValidUUID | UUID字符串非空不验证注册；M08由真实callback测试抓到 |
| SpeechEnhancementTypesTests | customPlanRetainsAllProperties、resultRetainsOutputURLAndRewriteFlag、resultCanIndicateNoRewrite | 仅回读Swift合成memberwise init；保留业务disabled默认参数 |
| AppBranchMonitorErrorHandlingTests | startMonitoringHandlesInitializationErrorsGracefully | 没有制造错误；正常start与注册数量已有更强测试，M22验证 |
| MacDictationPanelLayoutTests | fixedLayoutUsesPositiveDisplayScale、fixedLayoutBottomInsetKeepsPanelAnchoredAboveScreenEdge | `==0.66`严格包含`>0`，`==12`包含`>=0`；M15/M16保留精确断言 |
| AppAudienceTests | appAudienceRecognizesAIFacingAppsByBundleIdentifier、appAudienceRecognizesCommonIDEsAsAIFacingTargets、appAudienceRecognizesAntiGravityStyleAIAppsByName | 全工具矩阵分别隔离bundle/name，比同时提供两个正确字段更强；M20/M21/M23验证 |
| AudioDeviceSelectionResolverTests | resolveWithPreferenceEnumUsesBuiltInDefault、resolveWithPreferenceEnumUsesExternalDevice | UID overload直接委托同一分支，保留测试另查fallback与干扰顺序；M14/M24验证 |
| StetUITests | testExample | 仅launch的未完成模板；其他UI方法保留启动/截图与性能采样，均仍未接入默认scheme |

保留的29个弱测试详见清单的`strengthen`。最明确的缺口包括设备空集合、监听无最终状态、文件等待被测试自己的`await writerTask.result`掩盖、预激活buffer只断言帧数而不看实际样本、ASR缺fixture直接return、语言不持久化、reveal关闭仍展示。

其中一些只来自静态反例，尚未实际执行：buffer保留旧样本、噪声/语音电平恒定返回范围内常数、通知正文遗漏时间、rewrite语言请求遗漏。它们与已执行M01–M24有明确区分；原本失败的音频测试尤其不能据此报告有效mutation score。

三个新增删除建议暂缓：内部通知字符串常量、合成Codable往返、重复但同样失效的文件等待测试。前两者外部契约可能需要更明确确认；后者应先修好保留的等待测试。另两个合成设备相等测试和一个macOS测试目标内的iOS格式兼容契约暂不删。

## 删除后验证

已重放受删除影响的18个变异，所有kill/survive结论不变；每个变异的剩余失败方法集合，恰好等于删除前失败集合减去被删方法。另6个（M11/M12/M13/M17/M18/M19）测试suite完全未修改，未机械重复运行。保留测试仍检测到原13个已发现的错误，原11个缺口仍明确存在。

原38个能抓到本轮错误的方法中删掉8个重复方法，保留30个，检测到的错误集合没有减少。主工作区完整回归确认 **626个方法，612通过、14失败、0框架报告跳过**。14个失败方法集合与原641方法基线完全一致，仍为音频/VAD文件系统错误；没有新失败，但不能报告全绿。`make test`退出2，内层xcodebuild退出65。结果包为`/tmp/stet-mutation-audit-20261106/final-workspace.xcresult`。

变异副本的生产文件已按初始SHA-256清单验证全部还原；主工作区的测试精简与副本逐字节一致。修改测试的swift-format lint及git diff --check通过。本会话没有提交。

## 独立 PR 验证

本批变更从最新 `origin/main`（`2c6a918`）建立独立分支，只迁入测试删除和审计材料，未包含审计时工作区的架构重构。独立分支完整运行仍为626方法、612通过、14失败；失败方法集合与审计基线完全一致。`make lint`通过（SwiftLint零违规、swift-format通过）。

本地命令：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test CI_XCODEBUILD_FLAGS='-derivedDataPath /tmp/stet-test-audit-pr-build -clonedSourcePackagesDirPath <existing SourcePackages cache> -disableAutomaticPackageResolution -resultBundlePath /tmp/stet-test-audit-pr.xcresult'`。测试结果不是全绿；此PR未修复既有VAD文件系统失败。
