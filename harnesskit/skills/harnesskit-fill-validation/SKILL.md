---
name: harnesskit-fill-validation
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 中，为 docs/VALIDATION.md 执行逐 artifact Markdown-first 循环：扫描真实 checks、runner 与 bindings，生成或选择 Claims，按需声明本份轮次，并通过 deterministic tooling 封存 provenance sidecar。
---

# 生成或采用 Validation Claims

本 skill 是 manifest-registered `docs/VALIDATION.md` 的轮次 owner。它在当前 artifact 的热上下文中完成 evidence scan、Claim draft、问题声明、答案复核、最小 Markdown 写入、authoring checklist 清理与 sidecar 封存。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Validation 只收目标仓库自身的验证能力与执行证据：

- checks 及其真实命令、状态、前提和副作用；
- runner、config、trigger 与 binding；
- receipt 路径、状态语义和结果报告要求；
- 何时、以何种已确认方式运行验证的 action rules。

本地环境归 Development；模块地图、依赖方向和运行链路归 Architecture；编码、产品、安全和可靠性判断归 rules；AGENTS 只链接验证入口。遵守 `$harnesskit-kickoff` 的 Artifact 路由硬规则，每个候选只交给一个语义 owner。本 skill 记录已有 runner/config，不修改 validation config、script、hook 或 CI。

HarnessKit 为本次 init 创建的 `.harnesskit/**`、`scripts/claims-verify.cjs`、`scripts/verify`、`scripts/verify.cjs`，以及 Claim verifier 输出与 HarnessKit receipt，都属于内部完成门禁，不进入目标 `docs/VALIDATION.md`，不生成 Validation Claim，也不作为目标仓库事实、validation entrypoint、observed source 或目标验证结果。相同脚本路径只有在 materialize 报告为 `skipped_existing` 且独立仓库证据证明其原本属于目标仓库时，才可按目标验证入口处理。

## 最低扫描面

只为当前 validation artifact 发现 evidence，至少核对：

- 目标仓库真实 checks、对应 command、状态、前提与副作用；
- runner 与 config 的执行入口、参数和聚合关系；
- hook/CI binding、trigger、path filter 与实际调用链；
- result、report、receipt 的路径、状态语义和结果报告要求。

Kickoff 地图中的 validation entrypoint 只是扫描起点，不能替代本份证据核实。优先读取真实 config、script、manifest、workflow、test 与仓库已采用的 guidance owner；候选命令、模板、示例、latest receipt 或单次成功结果不能单独证明已配置能力。

## 本份轮次

只为当前 validation artifact 中 evidence 无法裁决的 intent 声明问题。每个问题必须展示 tooling 已分配的 Claim ID 与完整推荐 statement，并交给 `$harnesskit-init` 立即 emit 本份轮次；本 skill 不直接 pause，也不新增 Questionnaire 字段。不得把问题并入其他 artifact 的轮次。

零 intent 时不停顿，完成 draft 后直接清理并封存。用户答案能回 repository 验证时，复核为 `observed` 并记录安全 source paths；repository evidence 无法裁决时，当场按 `intent` 确认。用户自由文本只是修正或定向复核指令，不直接成为 evidence 或 durable guidance。

## Markdown-first workflow

1. 读取 repo-local artifact manifest、materialize 结果、kickoff 地图与当前 `docs/VALIDATION.md`，执行上述最低扫描面；先排除 HarnessKit 内部完成门禁。
2. Bootstrap 时生成最少但足够的 validation spec；Adopt 时只选择本轮明确采用的既有 guidance。把被选择内容拆成单一 Validation owner 下的 atomic statement，并判断 `observed | intent`：
   - observed 选择目标仓库真实 command/config/runner/hook/workflow/result 等安全 repo-relative sources；不得选择 `.harnesskit/**`、本轮 materialize 创建的 support script、Claim sidecar/transcript、Claim verifier 输出或 HarnessKit receipt；
   - intent 默认进入本份真实用户确认；只有当前 artifact owner 核实已存在、独立且权威的 repository confirmation locator 时才复用；
   - configured、manual、absent、unknown 与 not-yet-bound 必须按 evidence 准确表达，不能把候选命令写成现有 check。
3. 对每条新 Claim 调用：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/VALIDATION.md" --count 1
   ```

   只使用 allocation 输出。Observed 与已有有效 repository confirmation locator 的 intent 立即执行最小 Markdown 写入；其余 intent 只保存 pending draft，不得提前写入 target。把 pending intent 的 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor 交给 init 存入 run-state；serialization 与 resume interface 归 init，本 skill 不定义 schema 或直接写 state。不要手写、猜测或复用 ID；普通交叉引用使用裸 ID，非规范示例使用 `[VALIDATION-NNNN]` 这类不匹配真实编号的占位符。
4. 若没有 pending intent，跳过 pause 直接进入 section 完整性检查。否则把按 ID 的 question declarations 返回 init，由 init 立即 emit 仅属于本 artifact 的轮次；输出 `needs_input` 后停止 repository 读写。
5. Continuation 只从 init 写入 run-state 的本份 pending context 恢复。先核对 target 与 exact selected bytes/anchor 仍一致；不一致时停止并重新声明。用户同意 intent 后，先由 init 以本 batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再由本 owner 最小写入。自定义修正交回本 owner 复核：能由 repository evidence 支持时改为 observed；证据仍无法裁决时更新 intent draft 并重新确认。Statement 语义变化时丢弃未写入的旧 ID、不回退 manifest high-water mark 且永不复用，再调用 allocation 取得新 ID。这里的退休没有单独命令：保留已消耗编号，且永不把该 ID 写入 Markdown 或 sidecar。未确认或被拒绝时同样丢弃 draft 并退休 allocated ID，target 保持未改。
6. 检查每个 template section 的三态：填充、删除，或明确写明无证据/待确认。不得静默留空；只有表头的空表格也属于留空。Adopt 中不得借此删除或改写未选择的人写内容。
7. 删除当前 artifact 中由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；不得删除其他 HTML comment 或人写内容，marker 缺对时停止并报告冲突。准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后调用：

   ```sh
   mkdir -p .harnesskit/audit/evidence
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/VALIDATION.md" --input ".harnesskit/audit/evidence/validation-sidecar-input.json"
   ```

   Tooling 计算 whole-file SHA-256、canonical order，并整份替换最终 sidecar；不能只提交本轮新增项。空 inventory 写空 `items`。写入成功即封存本 artifact，后续 artifact 只读取该定稿。
8. 运行 `node scripts/claims-verify.cjs verify --json`，按本 artifact、ID 或 source 修正语义输入并重跑到 `passed`，再把已封存结果交回 init 进入下一 artifact。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只追踪 provenance 能完成的 durable guidance；heading、导航、解释性 prose、示例和未决 placeholder 保持无 ID。
- Adopt 中未选择的人写 bytes 必须逐字保持。只在被选择项范围内做最小 atomic split、必要措辞调整和 token 插入。
- Claim 不绑定固定 heading、列表、列或 template section。
- 任何 claim-bearing Markdown 都不能自证 intent；没有明确、独立的 confirmation locator 时必须真实询问用户，不得发明确认来源或要求新增决策文档。

## 边界

- Agent 只负责 statement、Claim 边界、`kind`、source path 与本份问题。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当作正文来源。
- 不修改 `.harnesskit/validation.json`、runner、hook、CI、receipt 或其他 owner 文档；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不虚构 coverage、security scan、release gate、platform setting 或 check result。
- 不把单个 check 成功、runner 存在或 `not_configured` 描述为完整 validation 通过。
- 不把 HarnessKit 内部 verifier、runner、audit、receipt 或 completion status 写成目标仓库验证内容或验证结果。
- 不为已有 tracked inventory 定义后续更新行为。
