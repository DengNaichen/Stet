---
name: harnesskit-fill-rules
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 中，为 manifest-registered root/part CODING、RELIABILITY、SECURITY 与 PRODUCT_SENSE 逐份执行 Markdown-first 循环：只扫描本份规则证据，生成或选择 atomic Claims，按需声明本份轮次，并通过 deterministic tooling 独立封存 provenance sidecar。
---

# 生成或采用 Rule Claims

本 skill 是 manifest-registered root/part `docs/rules/*.md` 的轮次 owner。它按 init 计划逐份完成 evidence scan、Claim draft、问题声明、答案复核、最小 Markdown 写入、authoring checklist 清理、sidecar 写入与封存校验。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Rules 是项目实践判断层：

- `CODING.md` 收模块内部代码组织、命名与风格、错误处理、测试邻接、注释与文档、生成资产编辑方式；
- `RELIABILITY.md` 收 failure、recovery、cleanup、retry/replay、compatibility、状态一致性与高风险改动判断；
- `SECURITY.md` 收 trust boundary、authentication/authorization、input、secret、file/output 与外部执行 confinement；
- `PRODUCT_SENSE.md` 收产品身份、目标用户、价值取舍、核心体验和产品反模式。

CODING、RELIABILITY 和 SECURITY 可在有真实 provenance 时记录本领域硬约束；PRODUCT_SENSE 不补造技术硬约束。模块、数据和生成源头的位置及放置规则归 Architecture；本地环境归 Development；checks、runner、binding、命令与 receipt 归 Validation；agent 启动与路由归 AGENTS。遵守 `$harnesskit-kickoff` 的 Artifact 路由硬规则，每个候选只交给一个语义 owner。

Rules 在 Validation、Development 与 Architecture 封存后处理。每份都读取这些已封存 Markdown 定稿；RELIABILITY、SECURITY 与 PRODUCT_SENSE 还读取本次顺序中此前已封存的 rule 定稿，用裸 Claim ID 做必要交叉引用，不复制其他 owner 的正文。Sidecar 只提供 provenance，不能替代 Markdown statement。

Materialize 为本次 init 创建的 `.harnesskit/**`、support scripts、Claim verifier 输出与 HarnessKit receipt 只服务内部完成门禁，不生成 Rule Claim，也不作为目标仓库实践、observed source 或验证结果。相同脚本路径只有在 materialize 报告为 `skipped_existing` 且独立仓库证据证明其原本属于目标仓库时，才可作为规则来源。

## 四份独立循环

在同一 root/part scope 内按 `CODING → RELIABILITY → SECURITY → PRODUCT_SENSE` 依次处理。四份各自走一个完整 artifact 循环，当前份通过封存校验前不得扫描或起草下一份；不得把 rules 当成一个合并批次。

有 pending intent 时四份各自一轮；零 intent 的份不停顿，完成 draft、section 检查和封存后直接流过。单份轮次超过协议 8 题上限时，按语义边界把剩余问题顺延到本份溢出轮；不跨份合并，不为凑题数把其他 artifact 借入，也不在题数边界腰斩一个领域。

## 最低扫描面

只为当前 rule artifact 发现 evidence，至少核对：

- **CODING**：代表性源码与测试、repo-owned build/format/lint/codegen 配置、已有 review 或编码 guidance；核实模块内部组织、命名与风格、错误处理、测试约定、注释文档和生成资产编辑方式。使用已封存 Architecture/Validation 排除放置规则与验证命令。
- **RELIABILITY**：failure/recovery/cleanup 路径、retry/replay、兼容性标记、生成输出、持久数据/schema/migration、tests/hooks/CI/release 与已有可靠性 guidance；只把 Validation 定稿作为检查能力引用，不复制 command、runner 或 gate。
- **SECURITY**：源码、配置、脚本、部署与依赖声明中的 trust boundary、认证授权、敏感数据与 secret、文件写入与输出、外部输入、调度/执行和外部系统边界，以及 Validation 定稿中的真实安全检查状态；不得虚构 policy、SLA、scan 或 gate。
- **PRODUCT_SENSE**：README、产品文档、真实用户入口、repo-owned 用户反馈或已采用的团队决策；核实产品身份、目标用户、产品原则、核心体验路径和反模式。代码只能证明当前行为，不能单独证明规范性产品判断。

Kickoff 地图只是 repo shape 与 part roots 的起点，不能替代本份证据核实。不要为后续 rule 预扫或保存全局候选池。

## Intent 问题发现

完成当前份最低扫描后、分配任何新 ID 或写入 target 前，必须执行一次仅属于当前 rule 的 intent discovery pass。先从当前 evidence 提取真实 identifier、状态、生命周期动作、数据边界、用户对象与产品反馈词汇，作为 repo-native anchors；推荐 statement 中的关键名词、边界与动作必须能回指这些 anchors，任何由本 skill 带入而仓库未使用的 stack 词汇都要重写或丢弃。不得预扫后续三份 rule。

只按当前 artifact 逐项检查以下结构模式；模式用于找 signal，不是可复制规则：

- **CODING**：同一职责是否反复出现多个组织、错误、并发或替身做法；常见形状是否只是局部实现却可能被外推全仓；生成输出与可编辑 source of truth 是否容易混淆。
- **RELIABILITY**：不同 terminal path 是否留下不同 cleanup 或恢复状态；retry、replay、cancel 是否可能重复 side effect；fallback 是否属于必须保持的行为；历史状态、迁移或 release layout 是否缺少兼容决定。
- **SECURITY**：同一敏感数据或权限边界是否存在旁路；日志、文件、网络或外部执行是否暴露仓库真实处理的数据；known gap 是否需要禁止、补偿控制或人工 review gate；外部来源是否缺少身份或完整性判断。
- **PRODUCT_SENSE**：当前能力服务谁、核心任务与价值取舍是否仍未决；waiting、failure、empty 或 rejected 状态是否缺少一致用户保证；看似增强的行为是否会改变用户原意或产品定位。

先用当前 evidence 形成行为、边界、gap 与现有 guidance 的本份地图，再建立仅存在于当前热上下文的候选池；每项至少包含 `repository signal → repo-native anchors → 未决判断 → 未来影响 → semantic owner → 完整推荐 statement`。

在 allocation 前逐项过滤：当前行为或 gap 归 observed；已有独立权威 policy locator 的约束按既有 intent 处理；会实质改变未来实现、评审或风险处理且仍未决的候选进入本份问题；通用最佳实践、低影响偏好、无具体违规形态、重复问题和其他 owner 内容丢弃或路由出去。

完整推荐 statement 只能表达一个仍未裁决的未来决定；当前行为或 gap 留在 repository signal/observed draft，不能与 intent 捆绑。同一 signal 同时导出长期规则与临时补偿、迁移或验证动作时必须拆分。Evidence 只能证明风险而不能证明具体做法可行时，约束 bounded outcome，不指定未经 repository evidence 或权威 contract 核实的机制。

问题必须 atomic、bounded。零 pending intent 合法，但只能在逐项执行当前 artifact 的上述发现模式后得出；不设置问题配额，也不持久化候选池。

## 原子性与 section 归位

- 每条 Claim 只表达一个 owner 下的一个判断。同句混合当前实现与规范要求时拆成 observed 与 intent；混合多个判断时即使同属一份也继续拆分；跨 rule 或跨 artifact 内容交给各自 owner。共享同一 sink、文件、runner 或风险标签不代表同一判断；不同数据类别、生命周期条件、失败结果或用户承诺必须继续拆分。
- 存在多个独立 intent 时生成多条小而完整的 proposed statements，不为减少停顿捆绑成末位 catch-all；不把固定 intent 数量当作质量要求。
- 每条 statement 写入语义对应 section。CODING、RELIABILITY、SECURITY 的强制性 statement 必须进入本份 `硬约束` section；PRODUCT_SENSE 不新增技术硬约束 section。路径放置、验证命令或本地环境内容不能塞进 rule 的 catch-all。
- 表格或列表只是表达形式，不决定 inventory；不得保留空模板 section 或空表，再把其判断集中放到别处。

## 本份轮次

只为当前 rule 的 discovery pass 过滤后仍未决的高质量 intent 声明问题。每个问题必须展示 tooling 已分配的 Claim ID、当前 artifact 与完整推荐 statement，并交给 `$harnesskit-init` 立即 emit 本份轮次；本 skill 不直接 pause，也不新增 Questionnaire 字段。

用户答案能回 repository 验证时，复核为 `observed` 并记录安全 source paths；repository evidence 无法裁决时，当场按 `intent` 确认。用户自由文本只是修正或定向复核指令，不直接成为 evidence 或 durable guidance。

## Markdown-first workflow

对 init 计划中的每个 rule artifact 重复以下流程：

1. 从 repo-local artifact manifest 取得当前 root/part target、namespace 与 sidecar mapping，读取 materialize 结果、kickoff 地图、当前 target Markdown、已封存的 Validation/Development/Architecture 定稿，以及顺序中此前已封存的 rule 定稿；只执行当前份的最低扫描面。
2. 先执行当前份 intent discovery pass，再起草或选择 tracked Claims。Bootstrap 时生成最少但足够的领域 guidance；Adopt 时只选择本轮明确采用的既有 guidance，不把整份人工 policy 自动 atomize。按上述原子性与归位规则拆分 statement，并判断 `observed | intent`：
   - observed 选择能直接支持当前行为、边界或 gap 的最小安全 repo-relative sources；
   - intent 默认进入本份真实用户确认；只有当前 artifact owner 核实已存在、独立且权威的 repository confirmation locator 时才复用；
   - repository 里常见但未明文采用的做法不能自动升级为规范或硬约束。
3. 对每条新 Claim 调用 tooling 分配 ID，例如：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/rules/CODING.md" --count 1
   ```

   只使用 allocation 输出。Observed 与已有有效 repository confirmation locator 的 intent 立即在语义对应 section 执行最小 Markdown 写入；其余 intent 只保存 pending draft，不得提前写入 target。把 pending intent 的 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor 交给 init 存入 run-state；serialization 与 resume interface 归 init，本 skill 不定义 schema 或直接写 state。不要手写、猜测或复用 ID；普通交叉引用使用裸 ID，非规范示例使用 `[CODING-NNNN]` 这类不匹配真实编号的占位符。
4. 若没有 pending intent，跳过 pause 直接进入 section 完整性检查。否则按语义边界把本份 declarations 组织为至多 8 题的轮次，由 init 逐轮 emit；每次输出 `needs_input` 后停止 repository 读写。未用满的题位保持为空，不能加入另一份问题。
5. Continuation 只从 init 写入 run-state 的本份 pending context 恢复。先核对 target 与 exact selected bytes/anchor 仍一致；不一致时停止并重新声明。整轮提交后逐题处理：
   - 用户同意 intent 时，先由 init 以本 confirmation batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再由本 owner 在语义对应 section 最小写入；
   - 自定义修正交回本 owner 复核；能由 repository evidence 支持时改为 observed，证据仍无法裁决时更新 intent draft 并重新确认；
   - statement 语义变化时丢弃未写入的旧 ID、不回退 manifest high-water mark 且永不复用，再调用 allocation 取得新 ID；退休没有单独命令，旧 ID 不得写入 Markdown 或 sidecar；
   - 未确认或被拒绝时同样丢弃 draft 并退休 allocated ID，target 保持未改。

   本份还有溢出轮时继续保存并 emit 本份 pending context；全部轮次处理完才进入下一步。
6. 仅当前 draft 与已封存内容不一致、却没有新 evidence 或答案支持时，丢弃或退休 current draft，不回退有效上游 Claim。若当前 evidence 或答案与已封存的 Validation、Development、Architecture 或此前 rule Claim 矛盾，停止当前份封存，从最早受影响的 artifact 重新进入其 owner 循环：退休受影响 ID、重新分配、重新核实；repository evidence 仍无法裁决时重新确认，再最小更新 Markdown、整份重写 sidecar 并通过 verifier 重新封存。回到当前份后重新读取定稿；语义受影响的 current drafts 同样退休并重新分配。不得静默保留冲突或整份改写人工文档。
7. 检查当前 template 的每个 section 或语义 subsection 三态：填充、删除，或明确写明无证据/待确认。不得静默留空；只有 heading、模板提示或表头的空表也属于留空。Template authoring 提示即使允许留空，也不能覆盖本三态合同。CODING、RELIABILITY、SECURITY 的 `硬约束` section 同样适用。Adopt 中不得借此删除或改写未选择的人写内容。
8. 删除当前 artifact 中由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；不得删除其他 HTML comment 或人写内容，marker 缺对时停止并报告冲突。准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后按 manifest 中当前 artifact 的实际 path 调用：

   ```sh
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/rules/CODING.md" --stdin <<'JSON'
   {
     "items": []
   }
   JSON
   ```

   示例 `items` 只表示 direct inventory 形状；仅当当前 Markdown 没有 tracked Claim 时才保持为空，否则把完整 inventory 直接放入 stdin。不要把 payload 落盘为临时 inventory 传输文件。Tooling 计算 whole-file SHA-256、canonical order，并整份替换当前 artifact 的 sidecar；不能只提交本轮新增项，也不能合并四份 inventory。写入成功后进入本份封存校验；verifier 通过前不得交给下一份读取。
9. 运行 `node scripts/claims-verify.cjs verify --json`，按当前 artifact、ID 或 source 修正语义输入并重跑到 `passed`。只有此时才把本份标记为已封存，并交回 init 按顺序进入下一份。

Root/part 与四种 rule artifact 始终使用 manifest 中的实际 path、namespace 与 sidecar mapping，不套用 CODING 示例 path 或 ID。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只追踪 provenance 能完成的 durable guidance；heading、导航、解释性 prose、示例和未决 placeholder 保持无 ID。
- Adopt 中未选择的人写 bytes 必须逐字保持。只在被选择项范围内做最小 atomic split、必要措辞调整和 token 插入。
- 任何 claim-bearing Markdown 都不能自证其中的 intent；没有明确、独立的 confirmation locator 时必须真实询问用户，不得发明确认来源或要求新增决策文档。

## 边界

- Agent 只负责 statement、Claim 边界、`kind`、source path 与本份问题。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当作正文来源。
- 没有具体行为、违规形态或真实 intent 时，不把通用建议升级为 rule；不以 intent 数量、轮次数或篇幅作为完成标准。
- 不复制 validation 命令/状态、development 步骤或 architecture 放置规则；只保留本领域判断并链接 owner。
- 不修改已封存上游 artifact、未选择的人写内容、receipt 或其他 owner 文档，除非按跨 artifact 冲突路径交回原 owner；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不为已有 tracked inventory 定义后续更新行为。
