# Technical Plans

本目录保存按 Spec 产生的 Technical Plan。Plan 是一次实现的冻结设计记录，不是当前架构或规则的事实源。

## 生命周期

- `active/`：正在起草、已确认并驱动实现，或等待实现完成的 Plan。
- `completed/`：实现已完成并通过验证的 Plan。归档后不再维护。
- Plan 不删除；后续整理长期架构文档时可将 completed Plan 作为历史来源阅读。

## 边界

- Spec 记录产品目标与用户可感知结果。
- Technical Plan 记录实现前的技术探索、方案比较、边界和验证策略。
- 当前实现以代码、[ARCHITECTURE.md](../ARCHITECTURE.md)、[rules/](../rules/index.md) 和 [VALIDATION.md](../VALIDATION.md) 为准；不要从 completed Plan 推导当前行为。

## 命名

<!-- TODO: 选定命名约定，例如 `<issue-id>.md` 或 `<feature-slug>.md` -->

文件示例：`active/<id>.md`

## 工作流

<!-- TODO: 与 spec-authoring / technical-plan skill 的 handoff 说明 -->

实现过程中如发生偏离，在原工作项或 PR 中记录，不回写成事后正确答案。
