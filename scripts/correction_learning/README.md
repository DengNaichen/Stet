# 从用户修改中学习词条：Python 参考实现

本阶段完成差分与词典合并逻辑，不接 macOS 输入框，不改 Stet 的实际词典。
比较的两个文本必须属于同一次 dictation 的同一区域；不能直接传整个聊天窗口。

后续 Swift 移植与 app 接入已经实现，见 [功能说明](../../docs/specs/correction-learning.md)。
Swift 使用系统中文分词，已通过这里全部 122 个固定样例和同样的 2,488 个组合输入；不需要在 app 内运行 Python。

## 已对齐的行为

- 只提取替换后的完整词或连续短语，不做意图、术语类别、发音或相似度判断。
- 独立的纯插入、纯删除跳过。词内部增删字符算词的替换，例如 `Pyton → Python`。
- 大小写修改也算替换。纯空白、标点和 emoji 修改不形成词条；词条至少包含字母或数字。
- 不设词长、改动比例或“看起来像重写”的过滤；`明天 → 后天`、`3 → 4`、整句替换均可学习。
- 标准拼写保留：`C++`、`C#`、`.NET`、`@scope/name`、`get_user_id` 等。
- 每个词条只有 `term` 和 `source`，来源为 `manual` / `automatic`。
- 旧字符串词典迁移为 `manual`；自动学习不能覆盖已有手动词条；手动添加同一个自动词条时提升为 `manual`，使用手动拼写。
- 去重采用 NFC 规范化、合并词条空白、`lower()`；不采用 NFKC 或 casefold。保持首次插入顺序，自动词条重复学习不会新增。

## 接口

```python
extract_replacements(original: str, edited: str) -> list[Replacement]
# Replacement(original="拍图", replacement="Python")

merge_glossary(existing, terms, *, source="automatic") -> list[GlossaryEntry]
# GlossaryEntry(term="Python", source="automatic")
```

提取结果按修改位置排序，重复出现的修改保留为独立证据；词典合并时再去重。
`Replacement` 的两个字符串是 NFC 规范化文本的原始片段，内部空白保留；词典入库再合并空白。
两者都不修改输入、不写文件。非法来源报错。为了约束差分开销，单侧输入最多 32,000 个 Unicode
code point、4,096 个 token；超限显式抛出 `ValueError`，不会静默生成空学习结果。

## 运行

需要 Python 3.10+；本次实际使用 Python 3.11.15。唯一第三方依赖固定为 `jieba==0.42.1`。
从仓库根目录执行：

```sh
python3.11 -m venv /tmp/stet-correction-learning-venv
/tmp/stet-correction-learning-venv/bin/pip install -r scripts/correction_learning/requirements.txt
/tmp/stet-correction-learning-venv/bin/python -m unittest discover -s scripts/correction_learning -v
```

也可以用 `uv venv` 和 `uv pip install` 创建同样的隔离环境。jieba 首次使用会初始化词频字典，缓存位于系统临时目录；字典和缓存不进入仓库。

命令行接收一个 JSON 对象，从标准输入读取，向标准输出返回结果：

```sh
/tmp/stet-correction-learning-venv/bin/python scripts/correction_learning <<'JSON'
{"original":"我用拍图写代码","edited":"我用Python写代码","glossary":["Swift"]}
JSON
```

输出：

```json
{
  "replacements": [{"original": "拍图", "replacement": "Python"}],
  "glossary": [
    {"term": "Swift", "source": "manual"},
    {"term": "Python", "source": "automatic"}
  ]
}
```

`glossary` 可以包含旧字符串或新的 `term` / `source` 对象。CLI 不回写传入文件；无效请求以状态码 2 退出。

## 算法与来源

借鉴 OpenWhispr 的“词级差分 → 替换词 → 词典”结构，没有移植其 JS 实现，也没有复制 TypeWhisper 的 GPL 源码。

1. NFC 规范化。
2. 对连续 CJK 文本用 jieba 精确分词，明确关闭 HMM，不使用新词模型或意图分类。其他文本使用保留技术拼写的 Unicode 词边界；标点作为差分定位锚点。
3. 固定完全相同的 token 前后缀，避免 `foo foo → bar foo` 被误配为插入加删除。
4. 使用 Python `difflib.SequenceMatcher(autojunk=False)` 对剩余 token 做差分。匹配时忽略大小写，再单独提取大小写替换。
5. 只取 `replace` 区间和大小写变化区间；去掉区间边缘的独立标点/符号；恢复完整词或短语。
6. 把 replacement 文本合并进词典并标记来源，不自动创建 original→replacement 强制替换规则。

参考：[OpenWhispr 提取器](https://github.com/OpenWhispr/openwhispr/blob/a2c76ef9ce2f121f5e1bd32af8a7530c8f86aff7/src/utils/correctionLearner.js)、
[Python difflib](https://docs.python.org/3/library/difflib.html)、[jieba](https://github.com/fxsjy/jieba)。
OpenWhispr / jieba 的项目许可证均标注 MIT。这里使用 jieba 作为依赖，没有复制它的词频字典到仓库。

## 测试与移植

- `cases.json`：108 个有明确预期的文本样例，涵盖中文、繁体、中英混输、技术标识符、重复词、多处编辑、大小写、Unicode 组合形式、emoji、多词短语及纯增删。
- `glossary_cases.json`：14 个词典来源、迁移、去重与拼写样例。
- `test_learning.py`：另有 768 个上下文组合、1,720 个重复序列插入/删除输入，以及来源校验、幂等性、输入不变、资源上限和 CLI 集成测试。
- 预期来自固定文字样例和已知的独立增删操作；没有调用被测算法来生成答案。

Swift 移植必须继续使用这些 JSON 输入/输出作为验收标准。迁移时有两个需要显式保留的行为：

1. Swift 标准差分与 Python SequenceMatcher 的重复文本配对并不保证一致，不能只换一个 API 就认为移植完成。
2. jieba 的词频字典决定中文边界；Swift 系统分词器不保证给出相同结果。可先验证系统分词器，若要严格一致，需要兼容的字典分词实现及相同字典版本。分词字典的准确性不等于术语或修改意图判断。

当前不输出字符下标，避免把 Python code point 偏移误当作 AX 的 UTF-16 偏移；接输入框时应在平台层转换并绑定具体 History ID。

## 已知边界

两个文本快照无法恢复用户实际按键过程。同样的 `Use old → Use Python today`，既可能是把 old
替换成短语，也可能是替换成 Python 后追加 today；没有共同锚点时，本实现把整个连续变化区间
作为 `Python today` 学习。没有加入意图判断来猜测两者。独立纯追加会跳过。

同理，`Pytho → Python` 按词内修复学习 Python；仅看两帧无法确认这是修复还是继续打字。
中文生僻人名、多义词或未收录词可能被分词器切成片段；当前测试通过不代表所有中文词边界都正确。
需要把真实遗漏继续补成固定样例，再调整边界规则。

终端输入、聊天已发送状态、IME 提交状态和 macOS 应用兼容性均不属于此 Python 阶段的验证范围。
