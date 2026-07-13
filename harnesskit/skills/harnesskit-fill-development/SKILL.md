---
name: harnesskit-fill-development
description: 在 Bootstrap 或选择性 Adopt 中生成或选择 docs/DEVELOPMENT.md 的 Markdown-first Claims，拥有本地开发实践问题，并通过 deterministic tooling 建立 provenance。
---

# 生成或采用 Development Claims

本 skill 直接维护 manifest-registered `docs/DEVELOPMENT.md` 中被明确追踪的 durable guidance。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Development 只收本地开发环境信息：

- 需要安装的 runtime、包管理器、容器工具与版本来源；
- 本地启动、就绪确认、停止、重启与安全清理；
- 配置来源、覆盖顺序、可提交示例与 secret 的受控读取方式；
- 本地端口、依赖服务、冲突处理、诊断与恢复步骤。

Checks、runner、binding、side effect 与 receipt 归 Validation；模块地图、依赖方向、部署拓扑与生产链路归 Architecture；生产发布、安全和可靠性 policy 归对应 rules。

## Question ownership

本 skill 只声明 Development-owned intent questions，例如推荐的本地启动顺序、配置覆盖或安全清理实践。Runtime/manifest 存在什么、validation entrypoint 是什么等定位 Facts 由 `$harnesskit-scan-facts` 声明。

问题必须展示 tooling 已分配的 Claim ID 与完整推荐 statement，并交给 `$harnesskit-init` 在 Practices 阶段集中 emit。本 skill 不直接 pause，也不新增 Questionnaire 字段。

## Markdown-first workflow

1. 读取 repo-local artifact manifest、materialize 结果、当前 `docs/DEVELOPMENT.md` 与 scan handoff。
2. Bootstrap 时生成最少但足够的本地开发 guidance；Adopt 时只选择本轮明确采用的既有 guidance。
3. 把被选择内容拆成单一 Development owner 下的 atomic statement，并判断 `observed | intent`：
   - observed 选择真实 manifest、script、config、example 或 local entrypoint 等 repo-relative sources；
   - intent 默认声明真实用户 confirmation question；只有 scan handoff 明确提供已存在、独立且权威的 repository confirmation locator 时才复用；
   - 不把未运行的命令结果、个人环境或生产行为写成 repository fact。
4. 对每条新 Claim 调用：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/DEVELOPMENT.md" --count 1
   ```

   只使用 allocation 输出。Observed 与 scan handoff 已证明存在有效 repository confirmation 的 intent 可把 `[DEVELOPMENT-0001]` token 与 statement 写入 Markdown；默认 intent 等待用户确认且不得先改 target。为 pending intent 保存 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor。不要手写、猜测或复用 ID；普通交叉引用使用裸 ID，非规范示例使用 `[DEVELOPMENT-NNNN]` 这类不匹配真实编号的占位符。
5. 对 pending intent 向 init 返回按 ID 的 question declaration。用户同意后，先由 init 以本 batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再核对 target 与保存的 selected bytes/anchor 仍一致并执行最小写入。自定义修正若改变语义，退休旧 ID、更新 draft 并重新确认。未确认或被拒绝时丢弃 draft，target Markdown 保持未改，allocated ID 退休且不复用。
6. 删除当前 artifact 中由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；不得删除其他 HTML comment 或人写内容，marker 缺对时停止并报告冲突。再准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后调用：

   ```sh
   mkdir -p .harnesskit/audit/evidence
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/DEVELOPMENT.md" --input ".harnesskit/audit/evidence/development-sidecar-input.json"
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
- 不把 test matrix、quality gate、runner/receipt、模块地图、生产拓扑或发布操作写进 Development。
- 不执行 destructive cleanup，不记录真实 credential、private URL 或个人绝对路径。
- 不修改未选择的人写内容、receipt 或其他 owner 文档；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不为已有 tracked inventory 定义后续更新行为。
