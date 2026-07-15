---
name: harnesskit-update
description: 编排用户主动触发、基于既有有效 baseline 的 Context Harness Update：pending-first 恢复、确定性影响路由、逐 artifact Refresh、有限 fixpoint、最终门禁与原子 baseline 推进。仅用于已完成 Bootstrap 的 base profile Git 仓库。
---

# Harness Update

把 Update 作为用户显式调用的独立编排。只合并 deterministic report、owner map 与 sealed owner outcome；不要判断 Claim 语义、代写问题或替 artifact owner 修改 Markdown/sidecar。

## 入口与版本边界

- 只在用户主动调用 `$harnesskit-update` 时开始；不要自动触发、注册 CI、定时任务或后台监控。
- 只开放已有有效 baseline 的 base profile Update v1。若 baseline 缺失或无效，停止并说明需先完成合格 Bootstrap；不要 baselineless scan。
- Web frontend 与 backend Update 尚未开放，直接返回 `blocked`。Web frontend Bootstrap 仍可建立首个 baseline，但不能据此进入 Update v1。
- 只支持 Git target。Fresh run 必须从干净 worktree 开始，并把 `HEAD^{commit}` 的完整 object ID 冻结为本次唯一 `frozen full HEAD`；不要缩写、改写或在运行中换基准。

## Canonical run-state gate 与 pending-first

在任何 `discover`、`checkpoint-build` 或其他 repository write 前，先用已 materialized `scripts/harness-update.cjs` 导出的 `parseRunStateBytes` canonical-read `.harnesskit/audit/state/run-state.json` 整份 v2 bytes；不要用宽松 JSON parse 绕过 schema、exact keys 或 canonical bytes 检查。按 canonical state 分流：

- 任意 `status: pending` 且 `workflow: update`：依序运行 `checkpoint-read` 与 `checkpoint-compare`，进入下述恢复流程。
- 任意 `status: pending` 且 workflow 不是 `update`，包括合法的 `workflow: bootstrap_or_adopt` pending：立即返回 `blocked`；不得运行 `discover`、不得写 Update checkpoint，也不得接管另一 workflow。
- 只有 canonical v2 `status: idle | complete | completed` 才确认不存在任何 pending，并可继续 fresh preflight。
- Run-state 缺失、legacy v1、invalid/non-canonical v2 或未知 workflow/status 一律 fail-closed 为 `blocked`；不得迁移、重写或猜测恢复。

Update pending 依序运行：

```sh
node scripts/harness-update.cjs checkpoint-read
node scripts/harness-update.cjs checkpoint-compare
```

不要在 pending run 上重跑 `discover`。按 compare report 处理：

- `matched`：只恢复 checkpoint 中 hash 完全匹配的 exact run-local writes、当前 round 与 owner context；保留已封存 outcomes 和 confirmations。
- `invalidated`：只废弃 `invalidation_plan` 指定的当前 pending round，保留 report 明示的 sealed outcomes 和 confirmations，再交回当前 owner 定向重建；不要退回全仓 discovery。
- `blocked` 或任何 tooling dependency drift：返回 `blocked`，保持旧 baseline 与 checkpoint，不覆盖、迁移或猜测修复。

## Fresh discovery 与三类路由

只有 canonical v2 run-state 已确认不存在任何 pending（`idle | complete | completed`）时，才从目标仓库根目录运行：

```sh
node scripts/harness-update.cjs discover
```

只消费 canonical report。以 report 的 `frozen_head` 固定本次 full HEAD；helper 已负责有效 baseline、ancestor、干净 Git worktree 与 HEAD race preflight。`status: blocked`，或 topology、tooling、Claim ID namespace、semantic owner 任一 blocker，直接返回 `blocked`；不要 full scan、baseline migration 或 topology migration。

按以下三类生成 artifact reasons：

1. **Existing Claim impacts**：只用 `claim_impacts` 的 reverse-index `claim_ids` 与 `artifacts` 路由现有 Claims；合并对应 Git/freshness diagnostics。
2. **Unindexed/new paths**：把 `unindexed_changes` 交给已封存 kickoff owner map；只有唯一 owner 才入队，缺失或冲突 owner 返回局部 blocker。`markdown_review_seeds` 只形成对应 artifact 的 Markdown drift reason。
3. **High-impact surfaces**：workspace/project manifest、CI binding、README/project identity、build-test-operation entrypoint、repo shape 或 part roots 变化时调用 `$harnesskit-kickoff Refresh` 做 compressed kickoff，把刷新后的 artifact map、plan brief 与直接受影响 owners 合入队列；其他路径不得触发 kickoff scan。

只规范化、合并并稳定排序 reasons。不要把 report token 当 statement，不要分类 Claim 语义，也不要创建 Questionnaire 文案。

## Deterministic queue 与有限 fixpoint

按 manifest owner 依赖建立 deterministic affected-artifact queue；同一 artifact 的 paths、Claim IDs、diagnostics、Markdown drift 与 upstream outcomes 都按 canonical code-point order 去重。内容 owners 收敛后才处理 rules；rules 固定按 `CODING → RELIABILITY → SECURITY → PRODUCT_SENSE` 一份一份处理；`AGENTS.md` 永远最后。

为每次调用计算 impact signature：artifact path 加五类冻结输入及其已合并 reason keys。相同 signature 只处理一次。Owner 返回新的 direct downstream reason 时，把 reason 合入目标 artifact；即使该 artifact 已处理，只要累计 reason set 严格增长就按依赖顺序重新入队。Reason 只能来自本次有限的 discovery report、compressed kickoff 与 sealed owner outcomes；不得合成开放式 reason。队列为空且没有新的唯一 signature 时达到 fixpoint；重复 signature 直接丢弃，因此循环必须终止。

## Owner Refresh loop

逐 artifact 调用现有 owner 的显式 Refresh invocation：

- `docs/VALIDATION.md` → `$harnesskit-fill-validation Refresh`
- `docs/DEVELOPMENT.md` → `$harnesskit-fill-development Refresh`
- root/part `ARCHITECTURE.md` → `$harnesskit-fill-architecture Refresh`
- 每份 registered rule → `$harnesskit-fill-rules Refresh`
- root/part `AGENTS.md` → `$harnesskit-fill-agents Refresh`

每次只传当前 artifact 的冻结 `changed paths`、`affected Claim IDs`、`verifier diagnostics`、`Markdown drift classification` 与 `sealed upstream outcomes`。消费 owner 返回的 sealed outcome 和 `direct semantic downstream impacts`，再由队列合并；不要接管 owner 的四类语义 admission、Questionnaire、问题措辞、Claim ID、confirmation 或 sidecar 写入。

Owner 返回 blocker 时，把它记录为当前 artifact 的局部 blocker，保留已封存 outcomes 和旧 baseline，终止为 `blocked`；不要扩大成全仓 scan 或迁移。

Owner 声明问题时，先把完整 round、current artifact、relevant inputs、exact accepted writes、confirmations 与 sealed outcomes 通过 stdin 原子保存：

```sh
node scripts/harness-update.cjs checkpoint-build --stdin
```

只有 checkpoint 成功后才 emit `needs_input`，随后立即停止全部 repository 读写。Checkpoint 保存失败时不得 emit `needs_input`；保持现有 run-state 与旧 baseline，并返回 `failed`。问题内容与 continuation 仍归当前 owner；恢复时回到“Canonical run-state gate 与 pending-first”。

## No-impact

若 canonical discovery 没有 impact，不提问，也不修改任何 Claim-bearing Markdown、sidecar 或 confirmation。仍执行全部 final gates，并用同一 frozen full HEAD 原子推进 baseline；把结果总结为 `completed` 的 no-impact 情形。

## Final gates 与 baseline 推进

严格按以下顺序完成，不得并行、跳过或交换：

1. 确认 queue 已达 fixpoint、全部受影响 artifact 已 sealed，且没有 pending round 或 unresolved item。
2. 运行 `node scripts/claims-verify.cjs verify --final --json`，要求 `valid: true` 且 `status: passed`。
3. 运行目标仓库 root validation runner，要求 latest 与本次 run receipt 均为 `status: passed`。
4. 再读取 `HEAD^{commit}`，要求仍等于本次 `frozen full HEAD`。
5. 只在以上门禁全部通过后运行：

   ```sh
   node scripts/harness-update.cjs finalize --source-commit <frozen-full-HEAD>
   ```

6. 只有 finalize 原子成功后才输出 summary，并把状态设为 `completed`。

任一 verifier、receipt、HEAD recheck gate 或 finalize 失败都必须保留旧 baseline，且不得报告成功；把执行或验证失败总结为 `failed`。Topology/tooling/ID/owner/profile blocker 使用 `blocked`。

## 终态 summary

每个终态都简洁总结 `scope`、`results`、`unresolved items` 与 `validation`：

- `completed`：只用于 finalize 成功；no-impact 是其中一种结果。
- `needs_input`：只用于 checkpoint 已保存且 owner 问题已 emit；列出当前 artifact 与待答 round。
- `blocked`：列出局部 blocker、受影响 scope 与保持不变的 baseline。
- `failed`：列出失败门禁或执行错误、未完成项与已通过验证。

只有 finalize 成功的 `completed` 可以称为成功。

## 边界

- 本 skill 只留在 Stet canonical assets；只引用已 materialize 的 target scripts、manifest、sidecars、run-state 与 receipts。不要把 `harnesskit-update` skill 目录或 metadata 复制进目标 repo，也不要建立 catalog。
- 不新增 update-specific owner；不改变 TOK-461–TOK-464 的 baseline/discovery/checkpoint/owner deterministic contracts。
- 不做 full-scan、baselineless、topology migration、force overwrite、自动触发、CI、定时任务、非 Git adapter 或 Web/backend Update。
- 不替 owner 读取全域 evidence、判断语义、生成问题或写 Claim-bearing assets；不替 deterministic tooling 计算 ID、hash、serialization、checkpoint 或 baseline。
