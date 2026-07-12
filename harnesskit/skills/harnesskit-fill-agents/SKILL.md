---
name: harnesskit-fill-agents
description: 在 Bootstrap 或选择性 Adopt 中生成或选择 root/part AGENTS 的 Markdown-first Claims，拥有 AGENTS 路由问题，并通过 deterministic tooling 建立 provenance。
---

# 生成或采用 AGENTS Claims

本 skill 直接维护 manifest-registered root/part `AGENTS.md` 中被明确追踪的 durable guidance。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

AGENTS 是简洁的 agent 启动入口：

- root artifact 只收会立即改变操作判断的项目事实、task/context 路由、全局行动 gate、source-of-truth 指针、跨 part 入口和 validation 入口；
- part artifact 只收 part-local 入口、端内路由与行动 gate，不复制 root contracts；
- companion guide、symlink 或 project-local procedure 只有在仓库证据存在时才记录。

完整仓库地图归 Architecture；本地安装、启动、配置和排障归 Development；checks 与 receipt 归 Validation；领域判断和硬约束正文归 rules；产品背景归 README 或产品文档。

## Question ownership

本 skill 只声明 AGENTS-owned intent questions，例如任务应路由到哪个 owner、哪些操作前必须先读某份规范或满足何种行动 gate。Project identity、repo shape、validation entrypoint 和 source-of-truth 位置等共享 Facts 由 `$harnesskit-scan-facts` 声明。

问题必须展示 tooling 已分配的 Claim ID 与完整推荐 statement，并交给 `$harnesskit-init` 在 Practices 阶段集中 emit。本 skill 不直接 pause，也不新增 Questionnaire 字段。

## Markdown-first workflow

1. 读取 repo-local artifact manifest、materialize 结果、当前 target Markdown 与 scan handoff。只处理 manifest 已登记的 canonical artifact。
2. Bootstrap 时生成最少但足够的 AGENTS guidance；Adopt 时只选择本轮明确采用的既有 guidance。不要把整份人工文档自动转成 Claims。
3. 把被选择内容拆成单一 AGENTS owner 下的 atomic statement，并判断 `observed | intent`：
   - observed 选择真正支持 statement 的安全 repo-relative source paths；
   - intent 默认声明真实用户 confirmation question；只有 scan handoff 明确提供已存在、独立且权威的 repository confirmation locator 时才复用；
   - mixed observed/intent 或 mixed owner 必须先拆分。
4. 对每条新 Claim 调用 tooling 分配 ID，例如：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "AGENTS.md" --count 1
   ```

   只使用命令输出的 ID。Observed 与 scan handoff 已证明存在有效 repository confirmation 的 intent 可把 `[AGENT-0001]` token 与 statement 写入 Markdown；默认 intent 等待用户确认且不得先改 target。为 pending intent 保存 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor。不要手写、猜测或复用 ID；普通交叉引用使用裸 ID，非规范示例使用 `[AGENT-NNNN]` 这类不匹配真实编号的占位符。
5. 对 pending intent 向 init 返回按 ID 的 question declaration。用户同意后，先由 init 以本 batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再核对 target 与保存的 selected bytes/anchor 仍一致并执行最小写入。自定义修正若改变语义，退休旧 ID、更新 draft 并重新确认。未确认或被拒绝时丢弃 draft，target Markdown 保持未改，allocated ID 退休且不复用。
6. 为本 artifact 准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后调用：

   ```sh
   mkdir -p .harnesskit/audit/evidence
   node scripts/claims-verify.cjs write-sidecar --artifact "AGENTS.md" --input ".harnesskit/audit/evidence/agents-sidecar-input.json"
   ```

   Tooling 计算 whole-file SHA-256、canonical order，并整份替换最终 sidecar；不能只提交本轮新增项。空 inventory 写空 `items`。
7. 从仓库根运行 `node scripts/claims-verify.cjs verify --json`。只修正报告指向本 artifact 的 statement/provenance 输入，再重跑到 `passed`。

Part artifact 使用 manifest 中的实际 path、namespace 与 sidecar mapping，不套用 root 示例 ID。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只给 provenance 能完成的 durable guidance 分配 token；heading、导航、解释性 prose、示例和未决 placeholder 不需要 Claim ID。
- Adopt 中未选择的人写 bytes 必须逐字保持。只允许在被选择项范围内做 atomic split、必要措辞调整和 token 插入；禁止整文件替换、重排或格式化。
- Claim 可位于任意 Markdown 结构；不要要求固定 heading、列表、列位置或 template section。
- 现有 target Markdown 不能自证其中的 intent；没有明确、独立的 confirmation locator 时必须真实询问用户，不得发明确认来源或要求新增决策文档。

## 边界

- Agent 只负责 statement、Claim 边界、`kind`、source path 与 confirmation question。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当作正文来源。
- 不编辑 `CLAUDE.md`、`.infcode/skills/**`、receipt 或其他 owner 文档；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不把 runtime-only built-in skill、template placeholder 或候选 procedure 写成目标仓库事实。
- 不为已有 tracked inventory 定义后续更新行为。
