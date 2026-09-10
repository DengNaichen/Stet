# 从用户修正中自动学习术语：开源调查

调查日期：2026-09-10。范围：macOS 粘贴后的手动修正、术语提取、词典学习。本文是调查记录，尚未成为实施方案。只检查源码、文档和算法；没有安装运行第三方 GUI，也没有验证微信、Chrome 等应用中的实际捕获成功率。

后续决策：用户已明确选择“不做意图识别，直接学习替换结果，来源区分 manual / automatic”。本文关于置信度和候选累计的建议不再是实施要求。已落地的 Python 参考及边界样例见 [correction_learning](../scripts/correction_learning/README.md)。

## 结论

社区已有实际实现。最接近 Stet 的是 OpenWhispr 和 TypeWhisper：短时间读取本次粘贴所在的输入框，比较用户修改前后文本，把提取的词或修正规则存到词典。已检查的学习路径使用确定性文本差异、相似度和规则，不训练模型。Veery 另有修正次数累计后晋升的机制。

第一版适合复用这一结构，并用 Swift 写小型提取器。主要难点是可靠捕获同一输入框、定位本次输出区域，以及处理中文与英文混输；更复杂的机器学习不能解决读不到文本的问题。现成英文分词和编辑距离门槛不能直接照搬。

## 已核查的开源实现

### OpenWhispr

快照：`a2c76ef9ce2f121f5e1bd32af8a7530c8f86aff7`。

- macOS 原生 helper 对目标 AX 元素订阅值变化通知，30 秒退出。主进程也有 500 ms 轮询路径，学习前等待 1500 ms 无新变化。读不到时存在跳过逻辑，不依赖确认消息发送。[原生监听](https://github.com/OpenWhispr/openwhispr/blob/a2c76ef9ce2f121f5e1bd32af8a7530c8f86aff7/resources/macos-text-monitor.swift)、[监控管理](https://github.com/OpenWhispr/openwhispr/blob/a2c76ef9ce2f121f5e1bd32af8a7530c8f86aff7/src/helpers/textEditMonitor.js)、[学习与入库](https://github.com/OpenWhispr/openwhispr/blob/a2c76ef9ce2f121f5e1bd32af8a7530c8f86aff7/src/helpers/ipcHandlers.js#L1044)。
- 通过空白切词、词级最长公共子序列（LCS）提取替换；跳过替换数量超过原词数一半的情况、短于 3 的新词和重复词；要求归一化 Levenshtein 编辑距离不超过 0.65。写入的是正确词条。[提取器完整源码](https://github.com/OpenWhispr/openwhispr/blob/a2c76ef9ce2f121f5e1bd32af8a7530c8f86aff7/src/utils/correctionLearner.js)。
- 该源码路径未调用 LLM 或训练模型。原仓库 [9 个提取器测试](https://github.com/OpenWhispr/openwhispr/blob/a2c76ef9ce2f121f5e1bd32af8a7530c8f86aff7/test/helpers/correctionLearner.test.js) 本次运行全部通过。
- 项目 [LICENSE](https://github.com/OpenWhispr/openwhispr/blob/a2c76ef9ce2f121f5e1bd32af8a7530c8f86aff7/LICENSE) 标注 MIT。可重点参考监听、稳定窗口和词典入库结构。

### TypeWhisper

快照：`5f04ae3d1910a252748ba53f26a6e13d5cf18851`。

- 在同一 AX 元素上约每秒读取一次，最长 30 秒。Return、Enter、Tab、焦点变化、应用切换被当作完成修正信号；没有完成信号则超时不学习。这些信号是产品启发式，不能证明消息已经发送。[捕获服务](https://github.com/TypeWhisper/typewhisper-mac/blob/5f04ae3d1910a252748ba53f26a6e13d5cf18851/TypeWhisper/Services/TargetAppCorrectionLearningService.swift#L215)。
- 以公共前后缀定位变化，再向空白边界扩展；只接受 token 数相同且一个 token 替换，过滤删除、追加和部分格式变化。保存 original→replacement 规则。[差分服务](https://github.com/TypeWhisper/typewhisper-mac/blob/5f04ae3d1910a252748ba53f26a6e13d5cf18851/TypeWhisper/Services/TextDiffService.swift#L141)、[词典写入](https://github.com/TypeWhisper/typewhisper-mac/blob/5f04ae3d1910a252748ba53f26a6e13d5cf18851/TypeWhisper/Services/DictionaryService.swift#L789)。
- 有实际 ViewModel 集成、发布记录和测试，非仅 issue 提案。测试源码覆盖读取失败、撤销、取消、失焦、超时、保存失败等；本次未运行整套 GUI/项目测试。[集成](https://github.com/TypeWhisper/typewhisper-mac/blob/5f04ae3d1910a252748ba53f26a6e13d5cf18851/TypeWhisper/ViewModels/DictationViewModel.swift#L3038)、[测试](https://github.com/TypeWhisper/typewhisper-mac/blob/5f04ae3d1910a252748ba53f26a6e13d5cf18851/TypeWhisperTests/TargetAppCorrectionLearningServiceTests.swift)、[1.5 发布说明](https://github.com/TypeWhisper/typewhisper-mac/blob/5f04ae3d1910a252748ba53f26a6e13d5cf18851/docs/release-notes/1.5.0.md)。
- 项目声明 GPL-3.0-or-later / 商业双授权；本调查仅参考设计，没有移植源码。[授权声明](https://github.com/TypeWhisper/typewhisper-mac/blob/5f04ae3d1910a252748ba53f26a6e13d5cf18851/LICENSE-COMMERCIAL.md)。

### Veery

快照：`0d6b900b1e09d62e34d44cebf33acf4a447fcfb4`。

- 手动修改路径监听按键，在内存中重建编辑后的文本；用 Python SequenceMatcher 找词级差异，再用 fuzzy matching 匹配修正对象。重复修正默认累计 3 次晋升为词典项。[按键与差分代码](https://github.com/andyhcwang/veery/blob/0d6b900b1e09d62e34d44cebf33acf4a447fcfb4/src/veery/app.py#L847)、[计数与晋升](https://github.com/andyhcwang/veery/blob/0d6b900b1e09d62e34d44cebf33acf4a447fcfb4/src/veery/learner.py#L62)、[默认配置](https://github.com/andyhcwang/veery/blob/0d6b900b1e09d62e34d44cebf33acf4a447fcfb4/src/veery/config.py#L130)。
- 源码明确指出，按键重建无法看到鼠标移动光标，而且中文 IME 按键不是最终汉字，因此加入跳过疑似拼音残留等防护。对 Stet 中文场景，更适合参考累计证据的方法，不适合照搬按键重建路线。[同一源码的限制说明](https://github.com/andyhcwang/veery/blob/0d6b900b1e09d62e34d44cebf33acf4a447fcfb4/src/veery/app.py#L960)。项目标注 [MIT](https://github.com/andyhcwang/veery/blob/0d6b900b1e09d62e34d44cebf33acf4a447fcfb4/LICENSE)。

## 用 Stet 的例子实际验证

运行 OpenWhispr 原始 `extractCorrections`，词典参数为空数组：

| 输入 → 修改后 | 实际返回 |
|---|---|
| 我最近在学拍图 → 我最近在学Python | `[]` |
| 我最近在学 拍图 → 我最近在学 Python | `[]` |
| I am learning 拍图 today → I am learning Python today | `[]` |
| I am learning Pyton today → I am learning Python today | `["Python"]` |
| Pyton → Python | `[]` |
| I want coffee today → I want toffee today | `["toffee"]` |

原因分析：无空格中文被当作一个 token，整个 token 的一次替换超过 50% 门槛；即使加空格，“拍图”和“Python”的字符编辑距离仍过大。反之，字形相似并不保证是识别纠错，也可能是改变意思。

单独运行 TypeWhisper 原始 TextDiffService 的高置信度提取函数：

| 输入 → 修改后 | 实际返回 |
|---|---|
| 我最近在学拍图 → 我最近在学Python | 整句 original→replacement |
| meet tomorrow → meet later | tomorrow→later |

它的“高置信度”是结构规则，不是术语或语义分类。两组实验只证明这些反例，不代表对项目整体准确率的评测。

OpenWhispr 可复现命令：

```sh
node --test test/helpers/correctionLearner.test.js
node -e 'const {extractCorrections:f}=require("./src/utils/correctionLearner.js"); console.log(f("我最近在学拍图", "我最近在学Python", []));'
```

TypeWhisper 实验使用原始 `TextDiffService.swift`，追加对 `TextDiffService().extractHighConfidenceCorrections(original:edited:)` 的上述调用后通过 Swift 解释器执行。未修改第三方算法。

## 算法选择

| 候选 | 能做什么 | 对 Stet 的判断 |
|---|---|---|
| 公共前后缀、字符级 diff | 找到哪里发生变化 | 第一版足够定位单个局部修正，但需扩展到完整词，例如 Pyton→Python 应提取 Python，而不是字母 h |
| Swift CollectionDifference | 标准库的有序集合差分 | 需要多个修改区间时可用；不需要为 diff 引入 Python 或大型依赖 |
| diff-match-patch | Myers diff、模糊匹配与差分清理 | 成熟算法参考；原 Google 仓库 2024-08-05 归档，不必为了单个替换添加依赖 |
| SymSpell | 从已有词典按编辑距离等生成纠错候选 | 用于已知词查找；不负责观察用户修改，也不能单凭字符距离关联“拍图→Python” |
| 次数累计 / 规则评分 | 从重复修正积累证据 | 无需训练；对不明确的词可先记候选，再按跨会话证据晋升 |
| LLM / 可训练分类器 | 判断局部变化是否更像术语纠错 | 后续有真实样本与误收指标再评估；第一版不是必需，也不是正确性的保证 |

算法来源：[Swift SE-0240](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0240-ordered-collection-diffing.md)、[diff-match-patch](https://github.com/google/diff-match-patch)、[SymSpell](https://github.com/wolfgarbe/SymSpell)、[Python difflib](https://docs.python.org/3/library/difflib.html)。表中适用性为本次分析判断。

## 对 Stet 的建议（待实施）

1. 仅在可读取、能定位本次插入范围的目标输入框建立观察会话。绑定 History UUID、目标 PID、AX 元素和原输出；新的 dictation 开始时结束旧会话，防止旧回调写错记录。
2. 初始可试 30 秒观察窗口、约 1–2 秒稳定等待；这些是参考参数，需真实应用验证。优先 AX 值变化通知，必要时有界轮询；失焦、目标变化、读取失败时停止或跳过。不把回车、清空等当作“已发送”的证明。
3. 比较 Stet 实际输出和用户修订，以字符变化定位，保留拉丁词完整边界；不能只按空格分中文，也不能要求跨脚本纠正字符相似。修正与词典候选分开：清楚的短技术词可一次入库；追加、删除、整句重写不学习；普通词语或不确定意图先累积证据。
4. “拍图→Python”保留为证据，优先把 Python 加入词典，避免全局硬替换拍图。稳定读到的修订文本不能自动标为已发送。IME 中间态、鼠标选择、撤销、多处编辑、同一句出现两次应加入验收样例；短暂稳定也不能完全证明 IME 已提交。
5. 不需要改训 ASR。现有词典已经进入转写 prompt 和重写 preferredSpellings；实际收益取决于引擎、上下文和提示效果，不能保证入库即识别正确。[prompt 构造](../StetMac/Core/DictationPipeline/DictationPipelineFactory.swift)、[Nano hotwords](../StetMac/Core/FunASR/FunASRNanoTranscriptionService.swift)、[重写提示](../Packages/StetEngine/Sources/StetRewrite/TextRewriteService.swift)。
6. 观察快照建议仅存在内存，记录必要的修正证据。现有 `DictionaryModel` 会同步 iCloud，词典还可能随选定云端服务的 prompt 发送，因此不能把“本地差分”描述成整条学习链路完全不出设备。[实际词典存储](../Packages/StetEngine/Sources/StetCore/DictionaryModel.swift)。

辅助功能 API 提供值变化通知，但目标对象可能不支持订阅；源码样例不能替代目标应用兼容性测试。[Apple 值变化通知](https://developer.apple.com/documentation/applicationservices/kaxvaluechangednotification)、[订阅与错误返回](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification)。

建议最先验收 TextEdit 和用户最常用的两个目标应用，测量可读/可定位率、术语误收和漏收。若捕获稳定但术语判断仍差，再考虑分类模型；若捕获失败，先解决应用适配。
