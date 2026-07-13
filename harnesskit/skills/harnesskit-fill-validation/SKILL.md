---
name: harnesskit-fill-validation
description: 在 Bootstrap 或选择性 Adopt 中生成或选择 docs/VALIDATION.md 的 Markdown-first Claims，拥有 validation action-rule 问题，并通过 deterministic tooling 建立 provenance。
---

# 生成或采用 Validation Claims

本 skill 直接维护 manifest-registered `docs/VALIDATION.md` 中被明确追踪的 durable guidance。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Validation 只收目标仓库自身的验证能力与执行证据：

- checks 及其真实命令、状态、前提和副作用；
- runner、config、trigger 与 binding；
- receipt 路径、状态语义和报告口径；
- 何时、以何种已确认方式运行验证的 action rules。

本地环境归 Development；模块地图、依赖方向和运行链路归 Architecture；编码、产品、安全和可靠性判断归 rules；AGENTS 只链接验证入口。本 skill 记录已有 runner/config，不修改 validation config、script、hook 或 CI。

HarnessKit 为本次 init 创建的 `.harnesskit/**`、`scripts/claims-verify.cjs`、`scripts/verify`、`scripts/verify.cjs` 及其输出属于内部完成门禁，不进入目标 `docs/VALIDATION.md`，不生成 Validation Claim，也不作为 observed source。相同脚本路径只有在 materialize 报告为 `skipped_existing` 且独立仓库证据证明其原本属于目标仓库时，才可按目标验证入口处理。

## Question ownership

本 skill 只声明 validation-owned action-rule intent questions，例如哪些变更必须运行何种已存在的检查。Validation entrypoint 是什么、真实 runner/command 在哪里等定位 Facts 由 `$harnesskit-scan-facts` 声明。

问题必须展示 tooling 已分配的 Claim ID 与完整推荐 statement，并交给 `$harnesskit-init` 在 Practices 阶段集中 emit。本 skill 不直接 pause，也不新增 Questionnaire 字段。

## Markdown-first workflow

1. 读取 repo-local artifact manifest、materialize 结果、当前 `docs/VALIDATION.md`、scan handoff，以及目标仓库真实的 config/runner/binding/result sources；先排除上述 HarnessKit 内部完成门禁。
2. Bootstrap 时生成最少但足够的 validation spec；Adopt 时只选择本轮明确采用的既有 guidance。
3. 把被选择内容拆成单一 Validation owner 下的 atomic statement，并判断 `observed | intent`：
   - observed 选择目标仓库真实 command/config/runner/hook/workflow/result 等安全 repo-relative sources；不得选择 `.harnesskit/**`、本轮 materialize 创建的 support script、Claim sidecar/transcript 或 HarnessKit receipt；
   - intent 默认声明真实用户 confirmation question；只有 scan handoff 明确提供已存在、独立且权威的 repository confirmation locator 时才复用；
   - configured、manual、absent、unknown 与 not-yet-bound 必须按 evidence 准确表达，不能把候选命令写成现有 check。
4. 对每条新 Claim 调用：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/VALIDATION.md" --count 1
   ```

   只使用 allocation 输出。Observed 与 scan handoff 已证明存在有效 repository confirmation 的 intent 可把 `[VALIDATION-0001]` token 与 statement 写入 Markdown；默认 intent 等待用户确认且不得先改 target。为 pending intent 保存 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor。不要手写、猜测或复用 ID；普通交叉引用使用裸 ID，非规范示例使用 `[VALIDATION-NNNN]` 这类不匹配真实编号的占位符。
5. 对 pending intent 向 init 返回按 ID 的 question declaration。用户同意后，先由 init 以本 batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再核对 target 与保存的 selected bytes/anchor 仍一致并执行最小写入。自定义修正若改变语义，退休旧 ID、更新 draft 并重新确认。未确认或被拒绝时丢弃 draft，target Markdown 保持未改，allocated ID 退休且不复用。
6. 删除当前 artifact 中由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；不得删除其他 HTML comment 或人写内容，marker 缺对时停止并报告冲突。再准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后调用：

   ```sh
   mkdir -p .harnesskit/audit/evidence
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/VALIDATION.md" --input ".harnesskit/audit/evidence/validation-sidecar-input.json"
   ```

   Tooling 计算 whole-file SHA-256、canonical order，并整份替换最终 sidecar；不能只提交本轮新增项。空 inventory 写空 `items`。
7. 运行 `node scripts/claims-verify.cjs verify --json`，按本 artifact、ID 或 source 修正语义输入并重跑到 `passed`。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只追踪 provenance 能完成的 durable guidance；heading、导航、解释性 prose、示例和未决 placeholder 保持无 ID。
- Adopt 中未选择的人写 bytes 必须逐字保持。只在被选择项范围内做最小 atomic split、必要措辞调整和 token 插入。
- Claim 不绑定固定 heading、列表、列或 template section。
- 任何 claim-bearing Markdown 都不能自证 intent；没有明确、独立的 confirmation locator 时必须真实询问用户，不得发明确认来源或要求新增决策文档。

## 边界

- Agent 只负责 statement、Claim 边界、`kind`、source path 与 confirmation question。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当作正文来源。
- 不修改 `.harnesskit/validation.json`、runner、hook、CI、receipt 或其他 owner 文档；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不虚构 coverage、security scan、release gate、platform setting 或 check result。
- 不把单个 check 成功、runner 存在或 `not_configured` 描述为完整 validation 通过。
- 不把 HarnessKit 内部 verifier、runner、audit、receipt 或 completion status 写成目标仓库验证内容或验证结果。
- 不为已有 tracked inventory 定义后续更新行为。
