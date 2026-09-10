# 从修改中学习词典

状态：active。平台：macOS 自动粘贴；词典数据模型由 macOS / iOS 共享。

## 目标

用户修改 Stet 粘贴到目标输入框的内容后，自动把替换结果加入个人词典。
不判断修改意图，不判断是不是专有名词或识别错误，也不按相似度或修改比例过滤。
词典保存正确词或短语，不创建全局 original→replacement 强制替换规则。

## 用户可见行为

- `拍图 → Python`、`Pyton → Python` 都学习完整的 `Python`。
- `明天 → 后天`、`3 → 4` 也学习；独立纯追加和纯删除跳过。
- 大小写修改可以学习，纯标点/空白/emoji 不创建词条。
- 每个词条记录 `manual` 或 `automatic` 来源；词典页用人物 / 星光图标和提示区分。
- 现有词条无来源时按手动添加处理；自动学习不覆盖已有手动来源；手动添加同一自动词条会提升为手动来源并采用手动拼写。
- 自动词条即时复用现有转写 prompt、Nano hotwords 和重写 preferredSpellings 链路。
- 关闭个人词典也停止自动学习。没有新增撤销提示、批准步骤或意图分类。

## 观察边界

在自己的粘贴键事件之前，捕获目标 app、同一 AX 输入框、原值和 UTF-16 选区。
先确认预期插入结果实际出现在该输入框中（最多等待 2 秒），再观察修改。
窗口最长 30 秒，间隔约 200 ms，修改稳定约 1 秒后提取；Return / Enter / Tab 可触发一次最终采样。
这些按键不是消息已发送证明，因此不改写 History 的 `finalText` 含义。

始终按粘贴前的前后文本定位本次插入区域。窗口外改动、目标 app / 输入框改变、超限、下一次听写、程序化替换或取消输出会结束旧观察。
读不到完整值、选区或可靠元素时跳过学习，不影响原有输出流程；仅复制到剪贴板不建立观察。
安全输入框不观察。原始快照仅留在内存，不写日志、不发送给新服务。
词典沿用已有 iCloud 同步和用户选定转写/重写服务的 prompt 行为。

## 实现入口

- [Swift 差分](../../Packages/StetEngine/Sources/StetCore/CorrectionExtractor.swift)：Unicode 词边界、系统中文分词、与 Python 相同的最长匹配和重复文本处理。
- [观察状态](../../Packages/StetEngine/Sources/StetCore/CorrectionObservation.swift)：验证插入、稳定窗口、范围隔离和 UTF-16 校验。
- [macOS 适配](../../StetMac/Core/TextInput/MacCorrectionLearningService.swift)：AX 只读适配、定时任务和代次隔离。
- [输出接入](../../StetMac/Core/TextInput/TextInjectionService.swift)：在自己的粘贴事件前准备、成功发出事件后观察。
- [词典来源](../../Packages/StetEngine/Sources/StetCore/GlossaryEntry.swift)、[持久化](../../Packages/StetEngine/Sources/StetCore/DictionaryModel.swift)。

`dictionary.entries` 继续保存字符串数组；`dictionary.entries.provenance.v1` 保存按实际拼写索引的来源。
来源缺失/未知时按 `manual` 处理。删除与清空同时更新元数据，明确的空云端数组按删除处理，不回退复活旧缓存。
旧版客户端可以继续读取词条；它们不能标注新的来源行为。云端文本/元数据分批抵达时，缺失的来源暂按手动展示，元数据通知到达后刷新。

## 验证

Python 与 Swift 共用 108 个差分样例和 14 个来源样例；另覆盖同样的 768 个上下文组合、1,720 个纯增删输入。
共享包测试覆盖 UTF-16 emoji 选区、未验证粘贴、外部区域改变、撤销、清空和超时。
macOS 测试用 AX 适配边界提供输入框状态，验证来源入库、目标切换、新会话、不可读和关闭词典，以及视图模型展示。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StetEngine
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make ci-build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make lint
```

Python 安装/运行及完整样例说明见 [参考实现](../../scripts/correction_learning/README.md)。
本次没有逐个实测微信、Chrome 等第三方 app 的 AX 行为，单元/集成测试通过不代表所有输入框均可读取。

## 明确的限制

两个文本快照无法区分相邻的多词替换和“替换后立即追加”：`old → Python today` 会学整个连续短语。
只观察编辑后的快照，不识别输入意图或 IME 提交状态；输入法组合过程在某些 app 中也可能暴露为文本变化。
系统中文分词器通过当前全部样例，但不保证所有生僻人名和 jieba 的边界完全一致；后续真实反例继续补入共用样例。
无确认的插入、多处重复导致无法定位的文本以及切换目标时错过的最后修改，宁可不学习。
