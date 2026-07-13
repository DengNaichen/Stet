---
name: harnesskit-init
description: 编排 Context Harness 的 missing-only Markdown materialize、预热轮、地图驱动的逐 artifact 封存循环、确定性 Claim provenance 与最终 verifier/receipt。用于 Bootstrap 或选择性 Adopt。
---

# Harness 初始化

本 skill 是用户可见的总编排器。它只编排预热轮、artifact 处理计划、逐份循环、pause/resume、coverage review 和完成门禁；不替 artifact owner 读取证据、写 statement、判断 `kind`、选择 source 或发明 confirmation question。

## 职责分工

- `$harnesskit-kickoff` 是 artifact 地图与预热轮 owner；它读取 repository evidence，判断 repo shape 与 part roots，并只声明 project identity、validation entrypoint 等真正跨 artifact 的问题。
- Fill skills 是本份轮次的语义 owner；它们负责当前 artifact 的证据扫描、Claim draft、问题声明、答案复核、最小 Markdown 写入、authoring checklist 清理与 sidecar 封存。
- Init 只消费 kickoff 地图与 repo-local manifest，动态展开 artifact 处理计划，并按 owner 声明 emit 轮次；不自行读取 repository evidence，也不把多个 artifact 的问题合并。
- Agent 只负责语义、statement、Claim 边界、`kind`、source path 与问题内容。
- `scripts/claims-verify.cjs` 负责 ID allocation、whole-file SHA-256、confirmation record、sidecar serialization/order、schema 与 inventory verification。
- 人类拥有 Markdown 表达；intent 默认通过真实用户回答确认。只有 artifact owner 核实 repository evidence 已采用独立、权威的 confirmation source 时，才复用该已有确认；不得要求或创建新的决策文档。

`.harnesskit/audit/state/run-state.json` 只保存预热轮或当前 artifact 的位置与本份 pending 轮次；evidence、transcript、sidecar 和 receipt 都不是日常 agent guidance 的替代品。

Materialize 本轮创建的 `.harnesskit/**`、`scripts/claims-verify.cjs`、`scripts/verify` 与 `scripts/verify.cjs` 是 HarnessKit 内部完成门禁。它们可以用于 allocation、provenance 和完成校验，但不得成为目标 Markdown 的项目事实、Claim statement、observed source 或目标验证结果。

## Missing-only materialize

从目标仓库根目录运行：

```sh
node /opt/harnesskit/scripts/init-materialize.mjs --target "$PWD"
```

若环境没有 `/opt/harnesskit`，使用实际 HarnessKit asset root 下的 `scripts/init-materialize.mjs`。Helper 只创建 `templates/init/**` 中缺失的文件，并在缺失时创建精确的 `CLAUDE.md -> AGENTS.md` 相对 alias；已有普通 `CLAUDE.md` 或正确 alias 返回 `skipped_existing`，错误 alias 或其他形态返回 conflict。不得覆盖、删除或重新格式化已有文件，也不得把这一例外扩展成通用 symlink 支持。

出现 `conflicts[]` 或非零退出码时立即停止并报告相对路径。不要自行复制模板或猜测覆盖策略。

## Bootstrap 与 Adopt

按 materialize 前后的文件状态逐 artifact 判断：

- **Bootstrap**：从新建 skeleton 生成最少但足够的 durable guidance。标题、导航、解释性 prose、示例和未决 placeholder 可以不带 Claim ID；最终 durable guidance 只有在 provenance 完整后才能作为 tracked inventory 完成。
- **Adopt**：读取已有 Markdown，只选择本轮明确采用且 provenance 足够的 guidance。未选择的人写 bytes 必须保持不变；对被选择项只做形成 atomic Claim 所需的最小拆分或措辞调整，再关联 token。
- 若 artifact 已有非空 tracked inventory，把后续更新报告为当前范围外，不自行定义运行策略。

不要要求 Claim 位于固定 heading、列表或列位置。Markdown statement 是正文 source of truth；sidecar 只保存 provenance。

## 主工作流

1. 运行 missing-only materialize，并保存每个 artifact 的 `created` / `skipped_existing` 结果。
2. 调用 `$harnesskit-kickoff` 完成 repo-shape、part roots 与跨 artifact 信息核实，取得 artifact 地图。Kickoff 只在 repository evidence 无法收敛高影响共享信息时声明预热轮；没有问题时为零轮。
3. 若存在预热轮，按 [protocol/README.md](../../protocol/README.md) 由 init emit；输出 `needs_input` 后立即停止读写。Continuation 从保存的预热轮恢复，不重跑 materialize 或重复已回答问题。能回 repository 验证的答案由 kickoff 复核后进入地图；repository evidence 无法裁决的答案路由给对应 artifact owner，在本份循环内作为 intent 处理。预热轮本身不写 Claim。
4. Init 按 kickoff 地图与 repo-local manifest 动态展开本次 artifact 集合与顺序；计划必须覆盖地图 scope 内 manifest 登记的每个 artifact，不把固定路径列表当成合同。单 project 默认展开为 validation → development → architecture → rules（CODING、RELIABILITY、SECURITY、PRODUCT_SENSE）→ agents；AGENTS 只在全部内容 artifact 封存后处理。Monorepo 只按 kickoff 提供的 repo shape、part roots 与 artifact 地图展开，不自行发明 root/part 细则。
5. 按计划逐 artifact 执行完整固定循环；当前 artifact 封存前不得进入下一份：
   1. 调用对应 fill skill，只扫描本 artifact 所需 evidence，生成或选择 atomic Claims，并用 tooling 分配 ID。Observed 由 owner 执行最小 Markdown 写入；intent 只保存 pending draft，不得提前写入 target Markdown。
   2. 若本份存在 pending intent，把当前 artifact、allocated IDs、完整 proposed statements、Adopt exact selected bytes 或 Bootstrap insertion anchors 保存到 run-state，再由 init emit 仅属于本份的轮次。零 intent 不停顿；不得跨 artifact 折叠。单轮超过 8 题时按语义边界顺延溢出轮，不在题数边界腰斩领域。
   3. Continuation 只从保存的本份 pending context 恢复。先确认 target 与保存的 selected bytes/anchors 仍一致；不一致时停止并重新声明，不能模糊查找或覆盖。答案能回 repository 验证时由 owner 复核为 observed；证据无法裁决且用户明确同意的 intent 由 tooling 写 immutable confirmation record，再由 owner 最小写入 Markdown。
   4. 自定义修正交回本 artifact owner 重新核实，不把回答直接当 repository evidence。语义变化时退休原 ID、重新分配并按需重新确认；拒绝或未确认的 draft 直接丢弃，target Markdown 保持未改，已分配 ID 退休且永不复用。每个 confirmation batch 使用新的唯一 repo-relative ref，已存在 record 不得覆盖或改写。
   5. Owner 删除本 artifact 中由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；不得删除其他 HTML comment 或人写内容，marker 缺对时停止并报告冲突。
   6. Owner 把本 artifact 的**当前完整 tracked inventory**交给 tooling 整份写 sidecar 并封存；不能只提交本轮新增项，空 inventory 写空 `items`。后续 artifact 只读取已封存定稿。
6. 后续 artifact 的证据或回答若与已封存 Claim 矛盾，从最早受影响的 artifact 重新进入固定循环，交回原 owner 按 retire → 重新分配 → 重新核实或确认 → 重新封存处理，再依计划重核后续 artifact；不得静默保留冲突或整份重写。
7. 全部 artifact 封存后执行内容 coverage review：检查 owner 边界、重复表达、证据支持、模板 section 三态（已填充、已删除、或明确写明无证据/待确认）与高影响缺口。发现问题时交回对应 owner 重新执行本份循环并封存，直到 review 收敛。
8. 运行 `node scripts/claims-verify.cjs verify --final --json`，按 artifact、ID、字段、source 或残留 authoring checklist 修正失败并重跑，直到 `valid: true` 且 `status: passed`。普通 `verify` 允许未完成轮次保留 checklist；只有 `--final` 是退出门禁。
9. 运行 HarnessKit 内部 root validation runner。只有 receipt `status: passed` 才能完成；引用 latest receipt 及 run receipt 路径，但不得把该 receipt 写成目标仓库的验证事实或结果。

## Questionnaire 编排

Questionnaire 只采用 [protocol/README.md](../../protocol/README.md) 定义的 UX、wrapper、字段、批量上限与 resume wire contract；其中的旧 workflow 分阶段与轮次顺序不适用于本编排，artifact 顺序与轮次由本 skill 定义。不要新增协议字段或在本 skill 复制 JSON schema。

- 只 emit kickoff 或当前 artifact 实际声明的问题；不设置固定轮数、最少问题数或额外语义门槛。
- 每个 waiting round 最多 8 题、一轮一次 pause；超限时按语义边界拆分，整轮提交后 resume。
- Artifact 轮次只包含本份 pending intent。零 intent 直接封存，不把问题借位到相邻 artifact。
- 输出 `needs_input` 后停止任何 repository 读写。Continuation 从 run-state 保存的预热轮或当前 artifact、Claim IDs、完整 proposed statements 和 exact selected bytes/insertion anchors 继续；不要依赖旧 session 记忆。
- 用户自由文本是修正或定向复核指令；只有经 repository evidence 复核后才能成为 observed，证据无法裁决时必须在本份轮次按 intent 确认。

## 确定性 tooling

所有命令都从目标仓库根目录运行：

```sh
node scripts/claims-verify.cjs allocate --artifact "docs/ARCHITECTURE.md" --count 1
node scripts/claims-verify.cjs confirm-user --ref ".harnesskit/audit/transcript/confirmations/2026-07-11-architecture-01.json" --confirmed-by "实际确认者" --date "YYYY-MM-DD" --claim "ARCHITECTURE-0001"
mkdir -p .harnesskit/audit/evidence
node scripts/claims-verify.cjs write-sidecar --artifact "docs/ARCHITECTURE.md" --input ".harnesskit/audit/evidence/architecture-sidecar-input.json"
node scripts/claims-verify.cjs verify --json
node scripts/claims-verify.cjs verify --final --json
```

示例路径和 ID 只说明 CLI 形状；实际 artifact、ref 和 IDs 必须来自 repo-local manifest 与 allocation 输出。每批用户确认使用新的唯一 ref，`confirm-user` record 一经写入不可覆盖。`write-sidecar` 输入必须枚举当前 Markdown 的完整 tracked inventory，并只提供 tooling 已分配的 `id`、agent 判断的 `kind`、observed source path 列表或已成立的 `confirmed_by` locator；writer 会整份替换该 artifact sidecar，同时计算 hash、排序并写最终 JSON。不要手写 ID、SHA-256 或最终 sidecar。

Verifier 把 canonical Markdown 中任何 literal registered token 都计入 inventory，包括 HTML 和 code fence 内。普通交叉引用使用裸 ID；非规范示例使用不匹配真实编号的占位符，例如 `[CODING-NNNN]`。

## 完成门禁

逐项确认：

- Kickoff 地图已消费，地图 scope 内每个 manifest-registered claim-bearing artifact 都已完成本份循环并恰有一个封存 sidecar；run-state 不含 pending 轮次。
- Markdown token IDs 与 sidecar item IDs 集合完全相等；ID 全仓唯一，namespace 与编号合法，sidecar items 和 sources 为 canonical order。
- 每条 Claim 是单一 owner 下的 atomic `observed` 或 `intent`；statement 只在 Markdown。
- 每个 observed source 安全、存在且 hash fresh；每个 intent 都有可定位的真实 `confirmed_by`。
- Adopt 中所有未选择的人写 bytes 与修改前一致；没有整份文档替换、无关重排或格式化。
- 所有 HarnessKit authoring checklist block 已删除，且 manifest-registered artifact 中不再残留对应 start/end marker。
- Coverage review 已覆盖 owner 边界、重复、证据支持、section 三态与高影响缺口；发现项已由对应 owner 修正并重新封存。
- `AGENTS.md` 只做启动和路由；Architecture、Development、Validation 与 rules 各守 owner 边界。
- Claim verifier `passed`，root validation receipt 也为 `passed`。`not_configured`、`failed`、`skipped` 或 `not_run` 都不能报告为完成门禁通过。

## 边界

- 只处理本次 Bootstrap 或选择性 Adopt；不从已有 sidecar 反向恢复或覆盖 Markdown。
- Init 不读取 repository evidence、不替 kickoff 判断 repo shape，也不替 fill owner 生成 artifact 内容。
- 不硬编码 monorepo 展开细则，不定义超时或无人值守降级。
- 不实现 force overwrite，不接管未选择的人写内容。
- 不虚构 repository facts、commands、CI、branch protection、release、compatibility 或 security policy。
- 不让 agent 计算 ID、hash、JSON ordering 或 verifier 结果。
- 不用本次 init 顺手修改 runtime/protocol/schema；发现漂移时报告对应 owner。
