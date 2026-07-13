---
name: harnesskit-fill-architecture
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 中，为 manifest-registered root/part ARCHITECTURE 执行逐 artifact Markdown-first 循环：扫描仓库地图、领域模型、运行链路与依赖边界，生成或选择 Claims，按需声明本份轮次，并通过 deterministic tooling 封存 provenance sidecar。
---

# 生成或采用 Architecture Claims

本 skill 是 manifest-registered root/part `docs/ARCHITECTURE.md` 的轮次 owner。它在当前 artifact 的热上下文中完成 evidence scan、Claim draft、问题声明、答案复核、最小 Markdown 写入、authoring checklist 清理与 sidecar 封存。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Architecture 回答“代码、数据和生成源头在哪里，以及依赖应朝哪个方向”：

- root artifact 收顶层仓库地图、cross-part contracts、核心领域/数据模型、生成资产与外部状态、关键运行链路、依赖方向和全局放置规则；
- part artifact 收端内模块地图、part-local 链路、依赖方向与放置规则，不复制 root contracts；
- 只保留会改变 agent 定位或放置判断的粗粒度路径，不展开完整 API、命令、测试或 helper 清单。

本地环境归 Development；checks、runner、binding 和 receipt 归 Validation；模块内部编码、产品、安全与可靠性判断归 rules；agent 启动与行动 gate 归 AGENTS。遵守 `$harnesskit-kickoff` 的 Artifact 路由硬规则，每个候选只交给一个语义 owner。

Materialize 为本次 init 创建的 `.harnesskit/**`、support scripts、Claim verifier 输出与 HarnessKit receipt 只服务内部完成门禁，不生成 Architecture Claim，也不作为目标仓库地图、运行链路、外部状态或 observed source。相同脚本路径只有在 materialize 报告为 `skipped_existing` 且独立仓库证据证明其原本属于目标仓库时，才可作为架构来源。

## 最低扫描面

只为当前 architecture artifact 发现 evidence，至少核对：

- 仓库地图：workspace/package manifests、build graph、源码与资源根、真实 root/part 边界；
- 核心领域/数据模型：repo-owned model/schema/type 定义及其关系；
- 生成资产与外部状态：generator、template、schema/migration、持久化位置及外部系统边界；
- 关键运行链路：真实 entrypoint、orchestrator、service/data flow 与主要 side effects；
- 依赖方向：package/module declarations、imports、build config 与已确认的 boundary rules；
- 放置规则：现有目录职责、生成源头、扩展点与已确认的 owner decisions。

Kickoff 地图是 repo shape 与 part roots 的起点，不能替代本份证据核实。Architecture 在 Validation、Development 封存后处理；读取它们的已封存 Markdown 定稿做交叉引用，使用裸 Claim ID，不复制其 command、环境步骤或验证规范。Sidecar 只提供 provenance，不能替代 Markdown statement。

## Intent 问题发现

完成最低扫描后、分配任何新 ID 或写入 target 前，必须执行一次本份 intent discovery pass。先从当前 evidence 提取仓库实际使用的 build unit、模块、领域对象、生命周期动作、生成源头与 contract 名称，作为 repo-native anchors；推荐 statement 中的关键名词、边界与动作必须能回指这些 anchors，任何由本 skill 带入而仓库未使用的 stack 词汇都要重写或丢弃。

逐项检查：多个入口是否收敛到同一语义 owner 却没有明确长期边界；新增职责是否存在多个同样合理的放置位置或依赖方向；旁路是否绕过集中状态或副作用 owner；生成源头、运行时状态与可编辑输出是否容易混淆；public contract 的 ownership 或方向是否尚未裁决。这些只是发现模式，不是可直接写入的 statement。

先用当前 evidence 形成模块、链路、依赖、生成源头与 gap 的现状地图，再建立仅存在于当前热上下文的候选池；每项至少包含 `repository signal → repo-native anchors → 未决判断 → 未来影响 → semantic owner → 完整推荐 statement`。在 allocation 前逐项过滤：可由 repository 直接裁决的当前事实转为 observed draft；已有独立权威 policy locator 的约束按既有 intent 处理；会实质改变未来依赖、放置或 public contract boundary 判断且仍未决的候选进入本份问题；通用最佳实践、低影响偏好、重复问题和其他 owner 内容丢弃或路由出去。历史状态、版本迁移与兼容保证路由 Reliability。

完整推荐 statement 只能表达一个仍未裁决的未来决定；当前事实或 gap 留在 repository signal/observed draft，不能与 intent 捆绑。同一 signal 同时导出长期边界与临时补偿、迁移或验证动作时必须拆分。Evidence 只能证明风险而不能证明具体做法可行时，约束 bounded outcome，不指定未经 repository evidence 或权威 contract 核实的机制。

候选必须 atomic、bounded。当前实现恰好符合某个约束，只能触发“是否应长期保持”的问题，不能自行确认该 intent。零 pending intent 合法，但只能在逐项执行上述发现模式后得出；不设置数量配额，也不持久化候选池。

## 本份轮次

只为本份 discovery pass 过滤后仍未决的高质量 intent 声明问题，例如 module/component/layer/part 边界、dependency direction、cross-part contract 与放置规则。每个问题必须展示 tooling 已分配的 Claim ID 与完整推荐 statement，并交给 `$harnesskit-init` 立即 emit 本份轮次；本 skill 不直接 pause，也不新增 Questionnaire 字段。不得把 root、part 或其他 artifact 的问题合并。

零 intent 时不停顿，完成 draft 后直接清理并封存。用户答案能回 repository 验证时，复核为 `observed` 并记录安全 source paths；repository evidence 无法裁决时，当场按 `intent` 确认。用户自由文本只是修正或定向复核指令，不直接成为 evidence 或 durable guidance。

## Markdown-first workflow

1. 从 init 计划与 repo-local artifact manifest 取得当前 root/part target，读取 materialize 结果、kickoff 地图、当前 target Markdown，以及已封存的 Validation/Development 定稿；只处理 manifest 已登记的 canonical artifact，并执行上述最低扫描面。
2. 先执行本份 intent discovery pass，再起草或选择 tracked Claims。Bootstrap 时生成最少但足够的架构地图；Adopt 时只选择本轮明确采用的既有 guidance，不把整份人工文档自动 atomize。把被选择内容拆成单一 Architecture owner 下的 atomic statement，并判断 `observed | intent`：
   - observed 选择支持路径、模块、领域模型、生成边界、链路或依赖现状的安全 repo-relative sources；
   - intent 默认进入本份真实用户确认；只有当前 artifact owner 核实已存在、独立且权威的 repository confirmation locator 时才复用；
   - 路径现状与依赖/放置规则混在一句时拆成 observed 与 intent，不能用 catch-all statement 捆绑多个 section。
3. 对每条新 Claim 调用 tooling 分配 ID，例如：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/ARCHITECTURE.md" --count 1
   ```

   只使用 allocation 输出。Observed 与已有有效 repository confirmation locator 的 intent 立即在语义对应 section 执行最小 Markdown 写入；其余 intent 只保存 pending draft，不得提前写入 target。把 pending intent 的 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor 交给 init 存入 run-state；serialization 与 resume interface 归 init，本 skill 不定义 schema 或直接写 state。不要手写、猜测或复用 ID；普通交叉引用使用裸 ID，非规范示例使用 `[ARCHITECTURE-NNNN]` 这类不匹配真实编号的占位符。
4. 若没有 pending intent，跳过 pause 直接进入 section 完整性检查。否则把按 ID 的 question declarations 返回 init，由 init 立即 emit 仅属于当前 root/part artifact 的轮次；输出 `needs_input` 后停止 repository 读写。
5. Continuation 只从 init 写入 run-state 的本份 pending context 恢复。先核对 target 与 exact selected bytes/anchor 仍一致；不一致时停止并重新声明。用户同意 intent 后，先由 init 以本 batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再由本 owner 在语义对应 section 最小写入。自定义修正交回本 owner 复核：能由 repository evidence 支持时改为 observed；证据仍无法裁决时更新 intent draft 并重新确认。Statement 语义变化时丢弃未写入的旧 ID、不回退 manifest high-water mark 且永不复用，再调用 allocation 取得新 ID。这里的退休没有单独命令：保留已消耗编号，且永不把该 ID 写入 Markdown 或 sidecar。未确认或被拒绝时同样丢弃 draft 并退休 allocated ID，target 保持未改。
6. 核对每条 statement 位于语义对应的 section。放置与依赖判断必须分别落在放置规则与依赖方向 section；表格或列表均可。不得保留空模板表，再把这些判断捆绑成其他 section 的 catch-all statement。Claim 不绑定固定表格/列表形状，但不能脱离自己的语义 owner section。
7. 检查仓库地图、核心领域/数据模型、生成资产与外部状态、关键运行链路、依赖方向、放置规则等每个 template section 的三态：填充、删除，或明确写明无证据/待确认。不得静默留空；只有表头的空表格也属于未满足三态的空表。Adopt 中不得借此删除或改写未选择的人写内容。
8. 删除当前 artifact 中由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；不得删除其他 HTML comment 或人写内容，marker 缺对时停止并报告冲突。准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后按 manifest 中当前 artifact 的实际 path 调用：

   ```sh
   mkdir -p .harnesskit/audit/evidence
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/ARCHITECTURE.md" --input ".harnesskit/audit/evidence/architecture-sidecar-input.json"
   ```

   Tooling 计算 whole-file SHA-256、canonical order，并整份替换 sidecar；不能只提交本轮新增项。空 inventory 写空 `items`。写入成功后进入本 artifact 的封存校验；verifier 通过前不得交给后续 artifact 读取。
9. 运行 `node scripts/claims-verify.cjs verify --json`，按本 artifact、ID 或 source 修正语义输入并重跑到 `passed`。只有此时才把本 artifact 标记为已封存，并交回 init 进入下一 artifact。

Part artifact 始终使用 manifest 中的实际 path、namespace 与 sidecar mapping，不套用 root 示例 path 或 ID。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只追踪 provenance 能完成的 durable guidance；heading、导航、解释性 prose、示例和未决 placeholder 保持无 ID。
- Adopt 中未选择的人写 bytes 必须逐字保持。只在被选择项范围内做最小 atomic split、必要措辞调整和 token 插入。
- Claim 不由表格、列表或列位置决定 inventory，但必须留在对应语义 section。
- 任何 claim-bearing Markdown 都不能自证其中的 intent；没有明确、独立的 confirmation locator 时必须真实询问用户，不得发明确认来源或要求新增决策文档。

## 边界

- Agent 只负责 statement、Claim 边界、`kind`、source path 与本份问题。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当作正文来源。
- 不把 Architecture 写成验证规范、本地开发指南、rules 合集、工作流指南或完整文件清单。
- 不修改已封存 Validation/Development、未选择的人写内容、receipt 或其他 owner 文档；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不为已有 tracked inventory 定义后续更新行为。
