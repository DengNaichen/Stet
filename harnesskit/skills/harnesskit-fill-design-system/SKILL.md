---
name: harnesskit-fill-design-system
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 中，为 manifest-registered docs/DESIGN_SYSTEM.md 执行独立 Markdown-first 循环：只扫描仓库可证明的视觉系统与共享组件外观契约，生成或选择 atomic Claims，按需声明本份轮次，并通过 deterministic tooling 封存 provenance sidecar。
---

# 生成或采用 Design System Claims

本 skill 只处理 manifest 已登记的唯一 artifact `docs/DESIGN_SYSTEM.md`，其 namespace `DESIGN-SYSTEM` 与 sidecar `.harnesskit/audit/claims/docs-DESIGN_SYSTEM.json` 必须直接取自 repo-local artifact manifest。它在当前 artifact 的热上下文中完成 evidence scan、Claim draft、问题声明、答案复核、最小 Markdown 写入、authoring checklist 清理与 sidecar 封存。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Design System 只回答“仓库已经采用或明确决定采用哪套可复用视觉语言与共享组件外观契约”：

- 收 semantic token、排版、色彩、间距、布局、主题与 responsive primitive；
- 收共享组件的视觉职责、variants、sizes、states、composition，及 icons、motion 与组件级 accessibility invariant；
- 视觉状态只记录外观契约，不记录触发、转换或恢复行为。

路径、依赖方向与数据流归 Architecture；实现约定归 Coding；产品理由归 Product Sense；失败与恢复归 Reliability；trust boundary 归 Security；检查命令归 Validation；导航、表单、overlay 与反馈行为归 Interaction Design。相同组件、状态或文件同时产生多类 signal 时，把每个候选交给唯一 semantic owner，不复制其他 owner 的正文。

本次 HarnessKit 创建的内部状态、support tooling、verifier 输出与 receipt 不能作为目标仓库的 Design System evidence。当前 target Markdown 与其 sidecar 也不能自证其中的 statement 或 intent。

## 最低扫描面

只为当前 Design System artifact 发现仓库可证明的 evidence，至少核对：

- **semantic tokens**：repo-owned token definitions、CSS variables、theme maps、style configuration 与消费点；核实语义角色和真实映射，不从零散 literal 推导未来 token policy；
- **排版、色彩、间距、布局与主题**：font/style sources、palette、spacing/layout scales、elevation/radius、theme modes 及其真实使用；
- **responsive primitives**：已实现的 breakpoint、container、grid、layout primitive 与适配边界，只记录视觉布局规则；
- **共享组件**：组件源码、样式、stories/examples 与组件测试中已存在的 variants、sizes、states 与 composition 边界；
- **icons 与 motion**：repo-owned icon assets/registry、animation primitives、duration/easing tokens 与 reduced-motion 外观替代；
- **组件级 accessibility invariants**：共享组件自身的 semantic/label contract、focus appearance、contrast or scaling behavior 及对应实现或测试，不扩展成页面流程约定。

只选择能直接支持 statement 的最小安全 repo-relative sources。截图、snapshot 或单个页面实例只能证明其覆盖的当前呈现，不能自行证明跨组件规范或未来要求。Kickoff 地图只可帮助定位，不能替代本份 evidence 核实；不要扫描导航、表单提交、overlay 生命周期或反馈恢复行为。

## Intent 问题发现

完成最低扫描后、分配任何新 ID 或写入 target 前，执行一次仅属于本 artifact 的 intent discovery pass。先从 evidence 提取真实 token、theme、component、variant、size、state、composition、icon、motion 与 accessibility 名称作为 repo-native anchors；推荐 statement 的关键名词、边界和值必须能回指这些 anchors。

逐项检查：相同语义角色是否存在多套未裁决映射；共享组件是否存在多个同样合理的 variant、size、state 或 composition contract；主题或响应式 primitive 是否暴露尚未裁决的视觉边界；icon、motion 或组件级 accessibility invariants 是否出现会影响未来复用的明确 gap。这些只是发现 signal，不是可直接复制的设计建议。

先形成当前 token、visual foundation、shared component 与 gap 地图，再建立仅存在于当前热上下文的候选池；每项至少包含 `repository signal → repo-native anchors → 未决判断 → 未来影响 → semantic owner → 完整推荐 statement`。在 allocation 前逐项过滤：当前实现或 gap 转为 observed draft；已有独立权威 design policy locator 的约束按既有 intent 处理；会实质改变未来共享视觉契约且仍未决的候选进入本份问题；局部页面偏好、重复项和其他 owner 内容丢弃或路由出去。对剩余候选执行通用性测试：若一条规范放到任何同类 Web 前端都成立，就不得成为 Claim；有 repository evidence 的当前行为仍可按 `observed` 记录，但不追踪或询问它的通用规范性影子。

完整推荐 statement 只表达一个仍未裁决的未来决定。当前事实与规范要求拆开；不同 token role、component、variant、size、state、composition、theme、responsive、icon、motion 或 accessibility 判断即使共享来源也继续拆分。候选必须 atomic、bounded。当前实现恰好符合某个约束，只能触发“是否长期保持”的问题，不能自行确认该 intent。

## 证据不足

证据不足时不补造 Claim；Bootstrap 对相应语义 section 删除未支持的模板提示，或以不带 Claim ID 的 `unknown` 明确当前未知。只有 repo-native signal 已证明未来复用判断确有必要时，才只询问本 artifact 必要确认；不得用通用前端建议补白，也不得要求用户凭空设计 token、breakpoint、component API 或 accessibility policy。零 observed 或零 intent 都合法，但只能在逐项执行本份 discovery pass 后得出；不设置 Claim 数量、问题数量或篇幅配额。

## 本份轮次

只声明属于 `docs/DESIGN_SYSTEM.md` 的问题。每个 intent 问题展示 tooling 已分配的 Claim ID、当前 artifact 与完整推荐 statement；每轮至多 8 题，超过上限时按语义边界进入本份溢出轮，不得混入其他 artifact 或为凑题数制造问题。把 declaration 交给现有调用方按 questionnaire protocol emit；输出 `needs_input` 后停止 repository 读写。

用户答案能回 repository 核实时，改按 `observed` 并记录安全 source paths；repository evidence 无法裁决时，才按 `intent` 建立 confirmation。用户自由文本只作为修正或定向复核指令，不直接成为 evidence 或 durable guidance。

## Bootstrap 扫描核对

仅在 Bootstrap 中，完成本 artifact 扫描并形成 observed drafts 后、发射 intent 轮次前，按需返回至多一道扫描核对声明。它沿用普通 `single_choice` question：自然语言 prompt、`accept` 与自由文本修改入口，并把多条结论放入 `claim.rows[].value`。只选择仓库已明确支持，且修正后会改变最终 artifact 或后续实现判断的结论；过滤通用常识、重复或低价值细节、HarnessKit 内部机制、其他 owner 内容与所有 intent。

接受整组只表示核对通过，各项仍是 repository sources 支持的 `observed`，不得写 `confirm-user` 或改成用户制定的 intent。局部修正时保留未指出的 rows，只重新核实指出项及其直接影响，且不把回答当 evidence；statement 语义变化时退休旧 ID 并重新分配。整组被否定时丢弃当前 artifact 本次尚未封存的全部 observed drafts、退休这些 IDs，并重扫整个当前 artifact；同一 artifact 不再发第二道扫描核对。扫描核对解决或跳过后再写入 observed 并处理 pending intent。

## Markdown-first workflow

1. 从 repo-local artifact manifest 核对 `docs/DESIGN_SYSTEM.md`、`DESIGN-SYSTEM` 与 `.harnesskit/audit/claims/docs-DESIGN_SYSTEM.json` 的完整 mapping，读取当前 target Markdown；mapping 缺失或不一致时停止，不自行注册、materialize 或替换 artifact。
2. 只执行本份最低扫描面与 intent discovery pass，再起草或选择 tracked Claims。Bootstrap 生成最少但足够的 guidance；Adopt 只选择本轮明确采用的既有 guidance，不自动 atomize 整份人工文档。按上述 owner 与 atomic 边界判断 `observed | intent`：
   - observed 只记录当前可证明的视觉系统、共享组件外观或明确 gap，并选择最小安全 repo-relative sources；
   - intent 需要独立且权威的 repository confirmation locator，或者进入真实用户确认；常见做法与当前实现不能自动升级成规范。
3. 对每条新 Claim 调用 tooling 分配 ID，只使用 allocation 输出：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/DESIGN_SYSTEM.md" --count 1
   ```

   Bootstrap 先保留 observed 与已有有效 locator 的 intent drafts，扫描核对解决或跳过前不得写入 target。Adopt 保持原流程：observed 与已有有效 locator 的 intent 立即最小写入，其他 intent 保持 pending；Adopt 跳过此步的扫描核对。保存 ID、完整 statement 与 exact selected bytes 或 insertion anchor；不要手写、猜测或复用 ID。
4. 仅 Bootstrap：按上节返回至多一道扫描核对 declaration。需要输入时先保存本份 pending context，再 emit 并停止读写；解决前不得发射 intent 问题。
5. 扫描核对解决或跳过后，最小写入 Bootstrap observed 与已有有效 locator 的 intent。没有 pending intent 时直接检查 section；否则按本份轮次 emit，未用满的题位保持为空。
6. Continuation 只从调用方保存的本份 pending context 恢复，并先核对 target 与 exact bytes/anchor 仍一致。用户同意 intent 时，先由调用方以本 confirmation batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再最小写入。用户自由文本不直接成为 evidence；先回 repository 复核。Statement 语义变化、拒绝或未确认时退休未写入 ID 且永不复用；语义变化后重新 allocation，不能回退 manifest high-water mark。
7. 把每条 Claim 放入视觉基础与设计令牌、组件与变体、状态视觉、响应式与主题或可访问性对应 section，不用 catch-all 捆绑。状态视觉只保留 presentation；行为路由 Interaction Design。模板中的更新提醒不产生 Design System Claim，也不能携带实现约定或检查命令。
8. 检查上述每个语义 section 的三态：填充、删除，或以不带 Claim ID 的 `unknown` 明确证据不足；只有 heading、模板提示或空表属于静默留空。Adopt 不得借此删除或改写未选择的人写内容。
9. 删除精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；marker 缺对时停止，不删除其他 comment 或人写内容。准备当前 Markdown 的完整 tracked inventory，包含此前保留项与本轮新增项；每项只含 `id`、`kind` 与 observed `sources` 或已成立的 `confirmed_by`，然后把 direct inventory 通过 stdin 交给 tooling：

   ```sh
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/DESIGN_SYSTEM.md" --stdin
   ```

   Tooling 计算 whole-file SHA-256、canonical ordering 并整份替换 manifest-mapped sidecar；不要只提交本轮新增项，也不要把 inventory 落盘为中间文件。
10. 运行 `node scripts/claims-verify.cjs verify --json`，按当前 artifact、ID、source 或 confirmation 修正语义输入并重跑到 `passed`。只有此时才把本 artifact 标记为已封存。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只追踪 provenance 能完成的 durable guidance；heading、导航、解释性 prose 与 `unknown` 保持无 ID。
- Adopt 中未选择的人写 bytes 必须逐字保持，只在明确选择项范围内做最小 atomic split、措辞调整与 token 插入。
- 任何 claim-bearing Markdown 都不能自证其中的 observed 或 intent；没有独立 evidence 或 confirmation locator 时不得伪造来源。

## 边界

- 只负责 Design System statement、Claim 边界、`kind`、source paths 与本份问题；不实现 Interaction Design owner 或其他 artifact owner。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当正文来源。
- 不创建或修改 profile materialize，不处理 root/part，不把本 artifact 提升为 canonical；不修改 kickoff、init、artifact registration、manifest counter、receipt 或其他 owner 文档。
- 不吸收路径、依赖、数据流、实现约定、产品理由、失败恢复、trust boundary、检查命令或交互行为；只保留本份视觉与共享组件外观判断。
- 不为已有 tracked inventory 定义后续更新行为。
