---
name: harnesskit-fill-development
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 中，为 docs/DEVELOPMENT.md 执行逐 artifact Markdown-first 循环：扫描真实安装、启动、配置与排障来源，生成或选择 Claims，按需声明本份轮次，并通过 deterministic tooling 封存 provenance sidecar。
---

# 生成或采用 Development Claims

本 skill 是 manifest-registered `docs/DEVELOPMENT.md` 的轮次 owner。它在当前 artifact 的热上下文中完成 evidence scan、Claim draft、问题声明、答案复核、最小 Markdown 写入、authoring checklist 清理与 sidecar 封存。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Development 只收本地开发环境信息：

- 需要安装的 runtime、包管理器、容器工具与版本来源；
- 本地启动、就绪确认、停止、重启与安全清理；
- 配置来源、覆盖顺序、可提交示例与 secret 的受控读取方式；
- 本地端口、依赖服务、冲突处理、诊断与恢复步骤。

Checks、runner、binding、side effect 与 receipt 归 Validation；模块地图、依赖方向、部署拓扑与生产链路归 Architecture；生产发布、安全和可靠性 policy 归对应 rules。遵守 `$harnesskit-kickoff` 的 Artifact 路由硬规则，每个候选只交给一个语义 owner。

Materialize 为本次 init 创建的 `.harnesskit/**`、`scripts/claims-verify.cjs`、`scripts/verify`、`scripts/verify.cjs` 及其输出只服务 HarnessKit 内部完成门禁，不生成 Development Claim，也不作为目标仓库本地开发入口或 observed source。相同脚本路径只有在 materialize 报告为 `skipped_existing` 且独立仓库证据证明其原本属于目标仓库时，才可按本地开发来源处理。

## 最低扫描面

只为当前 development artifact 发现 evidence，至少核对：

- 安装：真实 manifests、lockfiles、tool-version 文件、setup/bootstrap scripts 与容器清单；
- 启动/停止：Make/package/task commands、scripts、compose/service definitions、就绪探测与清理入口；
- 本地配置：repo-owned config、可提交 example config、环境变量名称、覆盖顺序与 secret 引用边界；
- 端口与依赖服务：真实清单、脚本或配置中的 bind/listen 信息、冲突处理与依赖关系；
- 排障：仓库已有 troubleshooting guidance、诊断脚本、日志入口和可恢复失败路径。

Kickoff 地图只提供 repo shape、part roots 与共享入口，不能替代本份证据核实。优先使用真实 script、manifest、config 与仓库已采用的 guidance owner；example config 只能证明其明确声明的 key、shape 或示例值，不能证明 secret、个人环境或当前 runtime 状态。

## Intent 问题发现

完成最低扫描后、分配任何新 ID 或写入 target 前，必须执行一次本份 intent discovery pass。先从当前 evidence 提取仓库真实的安装入口、运行入口、配置名称、依赖服务、就绪信号与恢复动作，作为 repo-native anchors；推荐 statement 中的关键名词、边界与动作必须能回指这些 anchors，任何由本 skill 带入而仓库未使用的 stack 词汇都要重写或丢弃。

逐项检查：多个可运行入口是否缺少 canonical path；文档、版本来源与真实 manifest 是否给出冲突支持边界；required 与 optional 工具是否容易混淆；配置覆盖、secret 读取或本地依赖关系是否未决；失败恢复或清理是否可能破坏数据、凭据或个人环境。不存在相应 surface 时跳过，不为覆盖模式制造问题。

先用当前 evidence 形成安装、启动、配置、依赖服务、恢复路径与 gap 的现状地图，再建立仅存在于当前热上下文的候选池；每项至少包含 `repository signal → repo-native anchors → 未决判断 → 未来影响 → semantic owner → 完整推荐 statement`。在 allocation 前逐项过滤：当前默认值、命令或 absence 归 observed；已有独立权威 guidance 的策略按既有 intent 处理；会改变可重复启动、配置一致性或安全恢复且仍未决的候选进入本份问题；个人环境、一次运行结果和其他 owner 内容丢弃或路由出去。对剩余候选执行 **通用性测试**：若某条规范放到任何同类项目都成立，该规范不得成为 Claim；“同类项目”以目标项目的语言与生态为参照，生态内普遍成立同样属于通用工程常识。有 repository evidence 支持的现状行为仍可按 `observed` 记录，但其规范性影子不追踪、不提问。

完整推荐 statement 只能表达一个仍未裁决的未来决定；当前事实或 gap 留在 repository signal/observed draft，不能与 intent 捆绑。同一 signal 同时导出长期入口或配置边界与临时 workaround、迁移或验证动作时必须拆分。Evidence 只能证明风险而不能证明具体做法可行时，约束 bounded outcome，不指定未经 repository evidence 或权威 contract 核实的机制。

问题必须 atomic、bounded。零 pending intent 合法，但只能在逐项执行上述发现模式后得出；不设置问题配额，也不持久化候选池。

## 本份轮次

只为本份 discovery pass 过滤后仍未决的高质量 intent 声明问题。每个问题必须展示 tooling 已分配的 Claim ID 与完整推荐 statement，并交给 `$harnesskit-init` 立即 emit 本份轮次；本 skill 不直接 pause，也不新增 Questionnaire 字段。不得把问题并入其他 artifact 的轮次。

零 intent 时不停顿，完成 draft 后直接清理并封存。用户答案能回 repository 验证时，复核为 `observed` 并记录安全 source paths；repository evidence 无法裁决时，当场按 `intent` 确认。用户自由文本只是修正或定向复核指令，不直接成为 evidence 或 durable guidance。

## Markdown-first workflow

1. 读取 repo-local artifact manifest、materialize 结果、kickoff 地图与当前 `docs/DEVELOPMENT.md`，执行上述最低扫描面；先排除 HarnessKit 内部完成门禁。
2. 先执行本份 intent discovery pass，再起草或选择 tracked Claims。Bootstrap 时生成最少但足够的本地开发 guidance；Adopt 时只选择本轮明确采用的既有 guidance。把被选择内容拆成单一 Development owner 下的 atomic statement，并判断 `observed | intent`：
   - observed 选择真实 manifest、script、config、example 或 local entrypoint 等安全 repo-relative sources；
   - intent 默认进入本份真实用户确认；只有当前 artifact owner 核实已存在、独立且权威的 repository confirmation locator 时才复用；
   - 不把未运行的命令结果、个人环境、runtime secret 或生产行为写成 repository evidence。
3. 对每条新 Claim 调用：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/DEVELOPMENT.md" --count 1
   ```

   只使用 allocation 输出。Observed 与已有有效 repository confirmation locator 的 intent 立即执行最小 Markdown 写入；其余 intent 只保存 pending draft，不得提前写入 target。把 pending intent 的 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor 交给 init 存入 run-state；serialization 与 resume interface 归 init，本 skill 不定义 schema 或直接写 state。不要手写、猜测或复用 ID；普通交叉引用使用裸 ID，非规范示例使用 `[DEVELOPMENT-NNNN]` 这类不匹配真实编号的占位符。
4. 若没有 pending intent，跳过 pause 直接进入 section 完整性检查。否则把按 ID 的 question declarations 返回 init，由 init 立即 emit 仅属于本 artifact 的轮次；输出 `needs_input` 后停止 repository 读写。
5. Continuation 只从 init 写入 run-state 的本份 pending context 恢复。先核对 target 与 exact selected bytes/anchor 仍一致；不一致时停止并重新声明。用户同意 intent 后，先由 init 以本 batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再由本 owner 最小写入。自定义修正交回本 owner 复核：能由 repository evidence 支持时改为 observed；证据仍无法裁决时更新 intent draft 并重新确认。Statement 语义变化时丢弃未写入的旧 ID、不回退 manifest high-water mark 且永不复用，再调用 allocation 取得新 ID。这里的退休没有单独命令：保留已消耗编号，且永不把该 ID 写入 Markdown 或 sidecar。未确认或被拒绝时同样丢弃 draft 并退休 allocated ID，target 保持未改。
6. 检查每个 template section 的三态：填充、删除，或明确写明无证据/待确认。不得静默留空；只有表头的空表格也属于留空。Adopt 中不得借此删除或改写未选择的人写内容。
7. 删除当前 artifact 中由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；不得删除其他 HTML comment 或人写内容，marker 缺对时停止并报告冲突。准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后调用：

   ```sh
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/DEVELOPMENT.md" --stdin <<'JSON'
   {
     "items": []
   }
   JSON
   ```

   示例 `items` 只表示 direct inventory 形状；仅当当前 Markdown 没有 tracked Claim 时才保持为空，否则把完整 inventory 直接放入 stdin。不要把 payload 落盘为临时 inventory 传输文件。Tooling 计算 whole-file SHA-256、canonical order，并整份替换最终 sidecar；不能只提交本轮新增项。写入成功即封存本 artifact，后续 artifact 只读取该定稿。
8. 运行 `node scripts/claims-verify.cjs verify --json`，按本 artifact、ID 或 source 修正语义输入并重跑到 `passed`，再把已封存结果交回 init 进入下一 artifact。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只追踪 provenance 能完成的 durable guidance；heading、导航、解释性 prose、示例和未决 placeholder 保持无 ID。
- Adopt 中未选择的人写 bytes 必须逐字保持。只在被选择项范围内做最小 atomic split、必要措辞调整和 token 插入。
- Claim 不绑定固定 heading、列表、列或 template section。
- 任何 claim-bearing Markdown 都不能自证 intent；没有明确、独立的 confirmation locator 时必须真实询问用户，不得发明确认来源或要求新增决策文档。

## 边界

- Agent 只负责 statement、Claim 边界、`kind`、source path 与本份问题。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当作正文来源。
- 不把 test matrix、quality gate、runner/receipt、模块地图、生产拓扑或发布操作写进 Development。
- 不执行 destructive cleanup，不记录真实 credential、private URL 或个人绝对路径。
- 不修改未选择的人写内容、receipt 或其他 owner 文档；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不为已有 tracked inventory 定义后续更新行为。
