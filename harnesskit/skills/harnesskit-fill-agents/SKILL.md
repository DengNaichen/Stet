---
name: harnesskit-fill-agents
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 中，为 manifest-registered root/part AGENTS 执行最后一份逐 artifact Markdown-first 循环：读取已封存内容定稿生成简洁启动与路由 Claims，按需声明本份轮次，并通过 deterministic tooling 封存 provenance sidecar。
---

# 生成或采用 AGENTS Claims

本 skill 是 manifest-registered root/part `AGENTS.md` 的轮次 owner。它在本次 init 计划内全部 root/part 非 AGENTS 内容 artifact 封存后，完成当前 AGENTS 的 evidence scan、Claim draft、问题声明、答案复核、最小 Markdown 写入、authoring checklist 清理、sidecar 写入与封存校验。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

AGENTS 是简洁的 agent 启动与路由入口：

- root artifact 只收会立即改变操作判断的少量项目事实、task/context 路由、全局行动 gate、source-of-truth 指针、跨 part 入口和 validation 入口；
- part artifact 只收 part-local 入口、端内路由与行动 gate，不复制 root contracts；
- companion guide、symlink 或 project-local procedure 只有在仓库证据存在时才记录。

完整仓库地图、数据与放置规则归 Architecture；本地安装、启动、配置和排障归 Development；目标仓库 checks、runner、命令、状态与结果归 Validation；编码、可靠性、安全和产品判断正文归对应 rules；产品背景归 README 或产品文档。AGENTS 只链接 owner 与说明何时读取，不复述其目录表、步骤、命令、检查矩阵、硬约束或产品正文。AGENTS 中的行动 gate 只能表达简洁的先读、先核实或路由顺序；若离开具体禁令、阈值或操作细节就无法成立，则正文留在原 owner，AGENTS 只给指针。遵守 `$harnesskit-kickoff` 的 Artifact 路由硬规则，每个候选只交给一个语义 owner。

## 已封存内容输入

只在 init 确认本次计划与 kickoff 地图 scope 内所有 manifest-registered root/part Architecture、Development、Validation 与 rule artifacts 已封存后开始任一 AGENTS 循环；任一 part-local 内容仍为 draft 都会阻断 root 与 part AGENTS。读取这些 Markdown 定稿与 kickoff 地图，使用裸 Claim ID 做必要交叉引用；sidecar 只提供 provenance，不能替代正文。若任何内容 artifact 尚未封存，停止并交回 init，不能用 draft 或 checklist 状态生成 AGENTS。

至少核对：

- 当前 root/part 的真实入口、边界与 source-of-truth 指针；
- 常见 task/context 应路由到哪个已封存 owner；
- 已确认的行动 gate、修改前必读项与 validation 入口；
- root/part、README/产品文档及 companion guide 之间的导航关系；
- 当前 `AGENTS.md` 中已有的人写启动说明与所选 Adopt bytes。

只把已封存定稿与独立 repository evidence 能直接支持的启动/路由 statement 写成 observed。定稿中的详细内容仍留在原 owner，不因 AGENTS 需要简洁摘要而复制。

## 内部资产隔离

Materialize 为本次 init 创建的 `.harnesskit/**`、`scripts/claims-verify.cjs`、`scripts/verify`、`scripts/verify.cjs`、Claim verifier 输出、HarnessKit audit/receipt 与 completion status 只服务内部完成门禁，不生成 AGENTS Claim，也不作为目标仓库事实、validation 入口、操作策略或 observed source。相同脚本路径只有在 materialize 报告为 `skipped_existing` 且独立仓库证据证明其原本属于目标仓库时，才可按其原有语义处理。

## Intent 问题发现

读取全部已封存内容定稿并完成当前 AGENTS evidence scan 后、分配任何新 ID 或写入 target 前，必须执行一次本份 intent discovery pass。先从当前 evidence 提取项目形状、build unit、part、owner 与常见任务使用的真实名称和动作，作为 repo-native anchors；推荐 statement 中的关键名词、边界与动作必须能回指这些 anchors，任何由本 skill 带入而仓库未使用的 stack 词汇都要重写或丢弃。

逐项检查：哪类任务不先读既有 owner 就会选错路径；哪个 repo shape 或 part 区分会立即改变搜索与修改方式；哪些高影响任务必须先核实真实 source of truth；content drift 应路由哪个 owner 而不是在 AGENTS 复制修复细节。这些只是发现模式，不是可直接写入的 statement。

先形成项目形状、owner pointers、常见任务路由与 drift 的现状地图，再建立仅存在于当前热上下文的候选池；每项至少包含 `repository signal → repo-native anchors → 未决行动 gate → 未来影响 → semantic owner → 完整推荐 statement`。在 allocation 前逐项过滤：当前项目事实和 pointer 归 observed；已有独立权威 guidance 的 gate 按既有 intent 处理；会立即改变 agent 读取、核实或路由顺序且仍未决的候选进入本份问题；详细禁令、阈值、命令和其他 owner 正文丢弃或仅保留链接。对剩余候选执行 **通用性测试**：若某条规范放到任何同类项目都成立，该规范不得成为 Claim；“同类项目”以目标项目的语言与生态为参照，生态内普遍成立同样属于通用工程常识。有 repository evidence 支持的现状行为仍可按 `observed` 记录，但其规范性影子不追踪、不提问。

完整推荐 statement 只能表达一个仍未裁决的未来决定；当前事实或 gap 留在 repository signal/observed draft，不能与 intent 捆绑。同一 signal 同时导出长期 gate 与临时补偿、迁移或验证动作时必须拆分。Evidence 只能证明风险而不能证明具体做法可行时，约束 bounded outcome，不指定未经 repository evidence 或权威 contract 核实的机制。

问题必须 atomic、bounded，压缩后仍能独立改变操作判断；不能为了“方便”复制 Architecture、Development、Validation 或 rules 内容。零 pending intent 合法，但只能在逐项执行上述发现模式后得出；不设置问题配额，也不持久化候选池。

## 本份轮次

只为本份 discovery pass 过滤后仍未决的高质量路由或行动 gate intent 声明问题。每个问题必须展示 tooling 已分配的 Claim ID 与完整推荐 statement，并交给 `$harnesskit-init` 立即 emit 本份轮次；本 skill 不直接 pause，也不新增 Questionnaire 字段。不得把问题并入相邻 artifact 或 kickoff 轮次。

零 intent 时不停顿，完成 observed 写入、section 检查和封存后直接流过。单轮超过协议 8 题上限时按语义边界顺延本份溢出轮，不跨 artifact 合并，也不在题数边界腰斩一个领域。

用户答案能回 repository 验证时，复核为 `observed` 并记录安全 source paths；repository evidence 无法裁决时，当场按 `intent` 确认。用户自由文本只是修正或定向复核指令，不直接成为 evidence 或 durable guidance。

## Markdown-first workflow

1. 从 init 计划与 repo-local artifact manifest 取得当前 root/part target、namespace 与 sidecar mapping，读取 materialize 结果、kickoff 地图、当前 target Markdown，以及当前 scope 全部已封存内容 artifact 的 Markdown 定稿；只处理 manifest 已登记的 canonical AGENTS artifact。
2. 先执行本份 intent discovery pass，再起草或选择 tracked Claims。Bootstrap 时把 skeleton 预填正文视为候选而非 evidence：heading、导航与解释性 prose 可保持无 ID；规范性路由、行动 gate 或项目 statement 只有在取证或确认后才保留为 tracked Claim，否则删除或按 section 三态明确说明。Adopt 时只选择本轮明确采用的既有 guidance，不把整份人工文档自动 atomize。把内容拆成单一 AGENTS owner 下的 atomic statement，并判断 `observed | intent`：
   - observed 选择直接支持当前项目事实、route、pointer 或 gate 的最小安全 repo-relative sources；
   - intent 默认进入本份真实用户确认；只有当前 artifact owner 核实已存在、独立且权威的 repository confirmation locator 时才复用；
   - mixed observed/intent、mixed owner 或一句中的多个路由判断必须拆分，其他 owner 的正文只保留链接。
3. 对每条新 Claim 调用 tooling 分配 ID，例如：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "AGENTS.md" --count 1
   ```

   只使用 allocation 输出。Observed 与已有有效 repository confirmation locator 的 intent 立即在语义对应 section 执行最小 Markdown 写入；其余 intent 只保存 pending draft，不得提前写入 target。把 pending intent 的 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor 交给 init 存入 run-state；serialization 与 resume interface 归 init，本 skill 不定义 schema 或直接写 state。不要手写、猜测或复用 ID；普通交叉引用使用裸 ID，非规范示例使用 `[AGENT-NNNN]` 这类不匹配真实编号的占位符。
4. 若没有 pending intent，跳过 pause 直接进入 section 完整性检查。否则按语义边界把本份 declarations 组织为至多 8 题的轮次，由 init 逐轮 emit；每次输出 `needs_input` 后停止 repository 读写。未用满的题位保持为空，不能加入其他 artifact 的问题。
5. Continuation 只从 init 写入 run-state 的本份 pending context 恢复。先核对 target 与 exact selected bytes/anchor 仍一致；不一致时停止并重新声明。整轮提交后逐题处理：
   - 用户同意 intent 时，先由 init 以本 confirmation batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再由本 owner 在语义对应 section 最小写入；
   - 自定义修正交回本 owner 复核；能由 repository evidence 支持时改为 observed，证据仍无法裁决时更新 intent draft 并重新确认；
   - statement 语义变化时丢弃未写入的旧 ID、不回退 manifest high-water mark 且永不复用，再调用 allocation 取得新 ID；退休没有单独命令，旧 ID 不得写入 Markdown 或 sidecar；
   - 未确认或被拒绝时同样丢弃 draft 并退休 allocated ID，target 保持未改。

   本份还有溢出轮时继续保存并 emit 本份 pending context；全部轮次处理完才进入下一步。
6. 仅当前 draft 与已封存定稿不一致、却没有新 evidence 或答案支持时，丢弃或退休 current draft，不回退有效上游 Claim。若当前 evidence 或答案与已封存 Claim 矛盾，停止本份封存，从最早受影响的 artifact 重新进入其 owner 循环，按 retire → 重新分配 → 重新核实或确认 → 重新封存处理；然后重新读取全部内容定稿并重建受影响的 AGENTS drafts。不得静默保留冲突或整份改写人工文档。
7. 检查当前 template 的每个 section 三态：填充、删除，或明确写明无证据/待确认。不得静默留空；只有 heading、模板提示或表头的空表也属于留空。Template authoring 提示即使允许留空，也不能覆盖本三态合同。每条 statement 必须位于语义对应 section；Adopt 中不得借此删除或改写未选择的人写内容。
8. 删除当前 artifact 中每个由精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；不得删除其他 HTML comment 或人写内容，任何 marker 缺对时停止并报告冲突。准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后按 manifest 中当前 artifact 的实际 path 调用：

   ```sh
   node scripts/claims-verify.cjs write-sidecar --artifact "AGENTS.md" --stdin <<'JSON'
   {
     "items": []
   }
   JSON
   ```

   示例 `items` 只表示 direct inventory 形状；仅当当前 Markdown 没有 tracked Claim 时才保持为空，否则把完整 inventory 直接放入 stdin。不要把 payload 落盘为临时 inventory 传输文件。Tooling 计算 whole-file SHA-256、canonical order，并整份替换当前 artifact 的 sidecar；不能只提交本轮新增项。写入成功后进入本份封存校验；verifier 通过前不得交给 init 收尾。
9. 从仓库根运行 `node scripts/claims-verify.cjs verify --json`，按当前 artifact、ID 或 source 修正语义输入并重跑到 `passed`。只有此时才把 AGENTS 标记为已封存，并交回 init 执行 coverage review、`verify --final` 与内部 validation runner。

Part artifact 始终使用 manifest 中的实际 path、namespace 与 sidecar mapping，不套用 root 示例 path 或 ID。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只给 provenance 能完成的 durable guidance 分配 token；template 本身不证明其预填规范。Heading、导航、解释性 prose、示例和未决 placeholder 可保持无 ID，未取证或未确认的规范性预填句不得自动保留。
- Adopt 中未选择的人写 bytes 必须逐字保持。只允许在被选择项范围内做 atomic split、必要措辞调整和 token 插入；禁止整文件替换、重排或格式化。
- Markdown 结构不决定 inventory，但 statement 必须留在对应语义 section。
- 任何 claim-bearing Markdown 都不能自证其中的 intent；没有明确、独立的 confirmation locator 时必须真实询问用户，不得发明确认来源或要求新增决策文档。

## 边界

- Agent 只负责 statement、Claim 边界、`kind`、source path 与本份问题。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当作正文来源。
- 不编辑 `CLAUDE.md`、`.infcode/skills/**`、已封存内容 artifact、receipt 或其他 owner 文档，除非按跨 artifact 冲突路径交回原 owner；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不把 runtime-only built-in skill、template placeholder、candidate procedure 或未封存内容写成目标仓库事实。
- 不把 HarnessKit 内部 verifier、runner、audit、receipt 或 completion status 写成目标仓库事实、验证入口或操作策略。
- 不为已有 tracked inventory 定义后续更新行为。
