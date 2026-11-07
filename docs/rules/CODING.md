# Coding Rules

本文件只记录跨端编码硬约束。路径职责见 [ARCHITECTURE.md](../ARCHITECTURE.md)；验证命令见 [VALIDATION.md](../VALIDATION.md)。

## 跨端规则

<!-- TODO: 生成源头与 Swift 包边界约定 -->

## 硬约束

以下规则必须始终成立，违反即为错误：

<!-- TODO: 逐条填写 -->

- <!-- TODO -->

## macOS 分层与依赖（[StetMac/](../../StetMac)）

由 `python3 scripts/arch-check.py` 强制，规则数据以脚本为准。目录是同一个 app target 里的代码组织，
没有编译器隔离，所以靠这个脚本守住方向。

| 层 | 目录 | 说明 |
|----|------|------|
| App | [App/](../../StetMac/App)、[StetMac/](../../StetMac) 根文件 | 组装根：创建并连接各协作者，实现 Presentation 定义的协议。 |
| Presentation | [Features/](../../StetMac/Features)、[Shared/UI/](../../StetMac/Shared/UI) | View 与 ViewModel。 |
| Core | [Core/](../../StetMac/Core) | 能力与流程：采集、转写、存储、系统适配。 |
| Shared | [Shared/](../../StetMac/Shared)（除 [UI/](../../StetMac/Shared/UI)） | 不含业务知识的基础代码。 |

依赖只能向内：App → Presentation → Core → Shared。与 [docs/macos-architecture-draft.md](../macos-architecture-draft.md) 的三层
（展示 / 应用流程 / 能力）的关系：脚本把"应用流程"按所在目录分别归入 App 或 Core。

硬约束（违反即为错误，脚本零容忍，不设基线）：

- Presentation 不引用 App 的任何类型。协议由使用方（Presentation）定义，App 实现。
- View 不存储 Core 的 class / actor / protocol 服务对象；由 ViewModel 持有，View 只读状态、转发操作。
  值类型（struct / enum）可以。
- View 不直接访问 Core / Shared 的单例（`Type.shared`）；放进 ViewModel，init 参数默认值可以是 `.shared`，
  这样测试能替换。ViewModel 里的单例默认值目前允许，但新代码优先由 App 注入。
- Core 和 Shared 不 import SwiftUI；Core 不引用 [Shared/UI/](../../StetMac/Shared/UI)；Shared 不引用 app 内其他层的类型。
- 每个 Swift 文件必须落在已声明的层里。新增顶层目录先在 `LAYER_OF_PATH` 中声明。

新增依赖时由 App 创建并注入，不在 View 的默认值里写具体实现。
[scripts/arch-baseline.json](../../scripts/arch-baseline.json) 只能收缩：修复后用 `--write-baseline` 重新生成，不手动添加条目。

脚本的盲区：只识别类型名的语法引用，看不到类型推断得到的引用、typealias，
`Type.shared` 用文本匹配（R7），不识别别名；也不检查生命周期、所有权和状态转换。
