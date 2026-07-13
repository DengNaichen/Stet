---
name: harnesskit-init
description: 编排 Context Harness 的 missing-only Markdown materialize、Facts-before-Practices 问卷、确定性 Claim ID/provenance sidecar 与最终 verifier/receipt。用于 Bootstrap 或选择性 Adopt。
---

# Harness 初始化

本 skill 是用户可见的总编排器。它只拥有阶段顺序、集中组轮、pause/resume 和完成门禁；不替 artifact owner 写 statement、判断 `kind`、选择 source 或发明 confirmation question。

## 职责分工

- `$harnesskit-scan-facts` 读取 repository evidence，判断 repo shape，并声明 project identity、purpose/users、validation entrypoint 与 source-of-truth 位置等共享 Facts 问题。
- Fill skills 直接生成或选择各自 Markdown 中需要追踪的 atomic statement，判断 `observed | intent`、为 observed 选择 source paths，并声明本 artifact 的 intent confirmation question。
- Agent 只负责语义、statement、Claim 边界、`kind`、source path 与问题内容。
- `scripts/claims-verify.cjs` 负责 ID allocation、whole-file SHA-256、confirmation record、sidecar serialization/order、schema 与 inventory verification。
- 人类拥有 Markdown 表达；intent 默认通过真实用户回答确认。只有 scan evidence 明确证明目标仓库已采用独立、权威的 repository confirmation source 时，才复用该已有确认；不得要求或创建新的决策文档。

`.harnesskit/audit/state/run-state.json` 只保存暂停位置；evidence、transcript、sidecar 和 receipt 都不是日常 agent guidance 的替代品。

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
2. 调用 `$harnesskit-scan-facts` 完成 evidence scan、repo-shape 判断与共享 Facts 声明。
3. 若存在 Facts 问题，按 [protocol/README.md](../../protocol/README.md) 由 init 集中 emit；输出 `needs_input` 后立即停止读写。Continuation 从保存的 Facts round 继续，不重跑 materialize 或重复已回答问题。
4. Facts 收敛后，按顺序调用 `$harnesskit-fill-validation`、`$harnesskit-fill-development`、`$harnesskit-fill-architecture`、`$harnesskit-fill-rules`、`$harnesskit-fill-agents`。每个 skill 生成或选择自己的 atomic Claims 并调用 tooling 分配 ID。Observed 或 scan handoff 已证明存在独立、权威 repository confirmation 的 intent 可写入 Markdown；默认 intent 进入真实用户确认，只保存 pending draft，不得先改 target Markdown。
5. 若存在 Practices 问题，在 pause 前把每个 pending intent 的 artifact、allocated ID、完整推荐 statement、Adopt exact selected bytes 或 Bootstrap insertion anchor 保存到 run-state `open_questions`。Init 按 canonical protocol 集中组轮；问题显示具体 Claim ID 与完整 statement。输出 `needs_input` 后 target Markdown 必须仍未包含这些 pending intent。
6. Continuation 只从保存的 pending context 恢复。先确认 target 与保存的 selected bytes/anchor 仍一致；不一致时停止并重新声明，不能模糊查找或覆盖。对用户明确同意的 IDs，用 tooling 写 immutable confirmation record，再由原 artifact owner 执行最小 Markdown 写入。每个 confirmation batch 使用新的唯一 repo-relative ref；已存在 record 不得覆盖或改写。
7. 自定义修正交回原 artifact owner 重新核实，不把回答当 repository evidence；语义变化时退休原 ID并重新分配、重新确认。未确认或被拒绝的 pending intent 直接丢弃 draft，target Markdown 保持未改，其 allocated ID 退休且永不复用。随后每个 fill skill 先删除本 artifact 中由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block，再把**当前完整 tracked inventory**交给 tooling 整份写 sidecar；不得删除其他 HTML comment 或人写内容，marker 缺对时停止并报告冲突。不能只提交本轮新增项；空 inventory 写空 `items`。
8. 运行 `node scripts/claims-verify.cjs verify --final --json`，按 artifact、ID、字段、source 或残留 authoring checklist 修正失败并重跑，直到 `valid: true` 且 `status: passed`。普通 `verify` 允许未完成轮次保留 checklist；只有 `--final` 是退出门禁。
9. 运行项目配置的 root validation runner。只有 receipt `status: passed` 才能完成；引用 latest receipt 及 run receipt 路径。

## Questionnaire 编排

Questionnaire 的 UX、wrapper 与字段只读 [protocol/README.md](../../protocol/README.md)，不要新增协议字段或在本 skill 复制 JSON schema。

- Facts 必须先于依赖它们的 Practices。
- 只有实际声明的问题才 emit；不设置固定轮数、最少问题数或额外语义门槛。
- 每个 waiting round 遵守协议批量上限；一轮一次 pause，整轮提交后 resume。
- 输出 `needs_input` 后停止任何 repository 读写。Continuation 从保存的 phase、artifact、Claim IDs、完整 proposed statement 和 exact selected bytes/insertion anchor 继续；不要依赖旧 session 记忆。
- 用户自由文本是修正或定向复核指令，不是 evidence，也不自动成为 intent。

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

- 每个 manifest-registered claim-bearing artifact 恰有一个 sidecar；Markdown token IDs 与 sidecar item IDs 集合完全相等。
- ID 全仓唯一，namespace 与编号合法；sidecar items 和 sources 为 canonical order。
- 每条 Claim 是单一 owner 下的 atomic `observed` 或 `intent`；statement 只在 Markdown。
- 每个 observed source 安全、存在且 hash fresh；每个 intent 都有可定位的真实 `confirmed_by`。
- Adopt 中所有未选择的人写 bytes 与修改前一致；没有整份文档替换、无关重排或格式化。
- 所有 HarnessKit authoring checklist block 已删除，且 manifest-registered artifact 中不再残留对应 start/end marker。
- `AGENTS.md` 只做启动和路由；Architecture、Development、Validation 与 rules 各守 owner 边界。
- Claim verifier `passed`，root validation receipt 也为 `passed`。`not_configured`、`failed`、`skipped` 或 `not_run` 都不能报告为完成门禁通过。

## 边界

- 只处理本次 Bootstrap 或选择性 Adopt；不从已有 sidecar 反向恢复或覆盖 Markdown。
- 不实现 force overwrite，不接管未选择的人写内容。
- 不虚构 repository facts、commands、CI、branch protection、release、compatibility 或 security policy。
- 不让 agent 计算 ID、hash、JSON ordering 或 verifier 结果。
- 不用本次 init 顺手修改 runtime/protocol/schema；发现漂移时报告对应 owner。
