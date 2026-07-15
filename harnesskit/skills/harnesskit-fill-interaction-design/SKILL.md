---
name: harnesskit-fill-interaction-design
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 中，为 manifest-registered docs/INTERACTION_DESIGN.md 执行独立 Markdown-first 循环：只扫描仓库可证明的跨功能复用或单页高影响用户行为与交互转换，生成或选择 atomic Claims，按需声明本份轮次，并通过 deterministic tooling 封存 provenance sidecar。
---

# 生成或采用 Interaction Design Claims

本 skill 只处理 manifest 已登记的唯一 artifact `docs/INTERACTION_DESIGN.md`，其 namespace `INTERACTION-DESIGN` 与 sidecar `.harnesskit/audit/claims/docs-INTERACTION_DESIGN.json` 必须直接取自 repo-local artifact manifest。它在当前 artifact 的热上下文中完成 evidence scan、Claim draft、问题声明、答案复核、最小 Markdown 写入、authoring checklist 清理与 sidecar 封存。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Interaction Design 只回答“仓库已经采用或明确决定采用哪些跨功能复用或单页高影响用户行为与交互转换”：

- 收 navigation、back、transitions 与 context preservation；
- 收 form validation、submission、dirty state 与 leave protection；
- 收 overlay 的 enter、exit、focus 与 close 行为；
- 收 loading、empty、error、success 与 progress 的用户可见反馈；
- 收用户可见 retry 入口、cancel 动作、recovery 路径与反馈；
- 收 optimistic、undo 与 destructive confirmation 行为；
- 收 keyboard、pointer、touch、focus 与 responsive behavior changes。

token、theme、component variant、size、state 与 visual primitive 归 Design System；Design System 只负责视觉外观，不记录行为触发、转换或结果。路径、依赖与数据流归 Architecture；实现约定归 Coding；产品理由归 Product Sense；用户可见 retry 入口、cancel 动作、recovery 路径与反馈归 Interaction Design，retry/cancel 背后的内部幂等、副作用、cleanup、cache 与 state consistency policy 归 Reliability；表单、keyboard、pointer input 与用户可见反馈归 Interaction Design，trust boundary、不可信或外部 input、敏感数据、文件或外部 output confinement 归 Security；checks 归 Validation。相同页面、组件或状态同时产生多类 signal 时，把每个候选交给唯一 semantic owner，不复制其他 owner 的正文。

本次 HarnessKit 创建的内部状态、support tooling、verifier 输出与 receipt 不能作为目标仓库的 Interaction Design evidence。当前 target Markdown 与其 sidecar 也不能自证其中的 statement 或 intent。

## 最低扫描面

只为当前 Interaction Design artifact 发现仓库可证明的跨功能复用或单页高影响用户行为，至少核对：

- **navigation、back、transitions 与 context preservation**：路由配置、页面壳、history/state 处理、用户流程测试与产品文档中的入口、返回、转场顺序及上下文保留；不把模块路径或数据流写成 Interaction Claim；
- **form validation、submission、dirty 与 leave protection**：表单实现、校验触发、提交状态、未保存变更提示、离开保护及相应测试；只记录用户可见行为，不扩展为 input trust 或实现约定；
- **overlay enter、exit、focus 与 close**：dialog、sheet、drawer、popover 等实现与测试中的打开入口、焦点移动或返回、关闭手段和退出结果；外观、尺寸与 motion primitive 路由 Design System；
- **loading、empty、error、success 与 progress**：异步视图、状态渲染与交互测试中的反馈时机、可用操作和状态转换，包括用户可见 retry 入口、cancel 动作、recovery 路径与反馈；不推导这些动作背后的内部幂等、副作用、cleanup、cache 或 consistency policy；
- **optimistic、undo 与 destructive confirmation**：用户动作、确认界面、可逆窗口、呈现结果与测试；不把内部副作用恢复或缓存策略纳入本 artifact；
- **keyboard、pointer、touch 与 focus**：快捷操作、焦点顺序或回退、等价输入路径及相关 accessibility 实现；
- **responsive behavior changes**：视口、输入方式或设备能力真正改变步骤、控件可用性或交互顺序的边界；breakpoint、layout primitive 与纯视觉适配归 Design System。

只选择能直接支持 statement 的最小安全 repo-relative sources。单个页面实例只能证明其自身行为，不能自行证明跨功能契约，但能证明本页会改变任务完成、未保存上下文、破坏性结果或可访问性的高影响交互。只有行为已跨功能复用或属于这种单页高影响边界时才进入本 artifact。Kickoff 地图只可帮助定位，不能替代本份 evidence 核实。

## Intent 问题发现

完成最低扫描后、分配任何新 ID 或写入 target 前，执行一次仅属于本 artifact 的 intent discovery pass。先从 evidence 提取真实 route、task、field、overlay、state、action、input mode 与 viewport 名称作为 repo-native anchors；推荐 statement 的关键名词、边界和值必须能回指这些 anchors。

逐项检查：返回或转场是否丢失用户上下文；同类表单是否在校验、提交、dirty 或离开保护上存在多个未裁决行为；overlay 的进入、退出、焦点或关闭路径是否冲突；反馈状态的触发、用户可见 retry/cancel/recovery 与下一步是否不一致；optimistic、undo 或 destructive confirmation 是否暴露未裁决的可逆边界；keyboard、pointer、touch、focus 或 responsive behavior 是否改变同一任务的可达路径。这些只是发现 signal，不是可直接复制的交互建议。

先形成当前任务、转换、输入方式与 gap 地图，再建立仅存在于当前热上下文的候选池；每项至少包含 `repository signal → repo-native anchors → 未决判断 → 未来影响 → semantic owner → 完整推荐 statement`。在 allocation 前逐项过滤：当前实现或 gap 转为 observed draft；已有独立权威 interaction policy locator 的约束按既有 intent 处理；会实质改变未来跨功能复用或单页高影响行为且仍未决的候选进入本份问题；低影响页面局部偏好、重复项和其他 owner 内容丢弃或路由出去。对剩余候选执行通用性测试：若一条规范放到任何同类 Web 前端都成立，就不得成为 Claim；有 repository evidence 的当前行为仍可按 `observed` 记录，但不追踪或询问它的通用规范性影子。

完整推荐 statement 只表达一个仍未裁决的未来决定。当前事实与规范要求拆开；navigation、form、overlay、feedback、optimistic/undo/confirmation、input modality、focus 或 responsive behavior 的不同判断即使共享来源也继续拆分。候选必须 atomic、bounded。当前实现恰好符合某个约束，只能触发“是否长期保持”的问题，不能自行确认该 intent。

## 证据不足

证据不足时不补造 Claim；Bootstrap 对相应语义 section 删除未支持的模板提示，或以不带 Claim ID 的 `unknown` 明确当前未知。只有 repo-native signal 已证明未来交互判断确有必要时，才只询问本 artifact 必要确认；不得用通用前端建议补白，也不得要求用户凭空设计导航、表单、overlay、feedback、input modality 或 responsive policy。零 observed 或零 intent 都合法，但只能在逐项执行本份 discovery pass 后得出；不设置 Claim 数量、问题数量或篇幅配额。

## 本份轮次

只声明属于 `docs/INTERACTION_DESIGN.md` 的问题。每个 intent 问题展示 tooling 已分配的 Claim ID、当前 artifact 与完整推荐 statement；每轮至多 8 题，超过上限时按语义边界进入本份溢出轮，不得混入其他 artifact 或为凑题数制造问题。把 declaration 交给现有调用方按 questionnaire protocol emit；输出 `needs_input` 后停止 repository 读写。

用户答案能回 repository 核实时，改按 `observed` 并记录安全 source paths；repository evidence 无法裁决时，才按 `intent` 建立 confirmation。用户自由文本只作为修正或定向复核指令，不直接成为 evidence 或 durable guidance。

## Bootstrap 扫描核对

仅在 Bootstrap 中，完成本 artifact 扫描并形成 observed drafts 后、发射 intent 轮次前，按需返回至多一道扫描核对声明。它沿用普通 `single_choice` question：自然语言 prompt、`accept` 与自由文本修改入口，并把多条结论放入 `claim.rows[].value`。只选择仓库已明确支持，且修正后会改变最终 artifact 或后续实现判断的结论；过滤通用常识、重复或低价值细节、HarnessKit 内部机制、其他 owner 内容与所有 intent。

接受整组只表示核对通过，各项仍是 repository sources 支持的 `observed`，不得写 `confirm-user` 或改成用户制定的 intent。局部修正时保留未指出的 rows，只重新核实指出项及其直接影响，且不把回答当 evidence；statement 语义变化时退休旧 ID 并重新分配。整组被否定时丢弃当前 artifact 本次尚未封存的全部 observed drafts、退休这些 IDs，并重扫整个当前 artifact；同一 artifact 不再发第二道扫描核对。扫描核对解决或跳过后再写入 observed 并处理 pending intent。

## Markdown-first workflow

1. 从 repo-local artifact manifest 核对 `docs/INTERACTION_DESIGN.md`、`INTERACTION-DESIGN` 与 `.harnesskit/audit/claims/docs-INTERACTION_DESIGN.json` 的完整 mapping，读取当前 target Markdown；mapping 缺失或不一致时停止，不自行注册、materialize 或替换 artifact。
2. 只执行本份最低扫描面与 intent discovery pass，再起草或选择 tracked Claims。Bootstrap 生成最少但足够的 guidance；Adopt 只选择本轮明确采用的既有 guidance，不自动 atomize 整份人工文档。按上述 owner 与 atomic 边界判断 `observed | intent`：
   - observed 只记录当前可证明的跨功能复用或单页高影响用户行为、转换或明确 gap，并选择最小安全 repo-relative sources；
   - intent 需要独立且权威的 repository confirmation locator，或者进入真实用户确认；常见做法与当前实现不能自动升级成规范。
3. 对每条新 Claim 调用 tooling 分配 ID，只使用 allocation 输出：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/INTERACTION_DESIGN.md" --count 1
   ```

   Bootstrap 先保留 observed 与已有有效 locator 的 intent drafts，扫描核对解决或跳过前不得写入 target。Adopt 保持原流程：observed 与已有有效 locator 的 intent 立即最小写入，其他 intent 保持 pending；Adopt 跳过此步的扫描核对。保存 ID、完整 statement 与 exact selected bytes 或 insertion anchor；不要手写、猜测或复用 ID。
4. 仅 Bootstrap：按上节返回至多一道扫描核对 declaration。需要输入时先保存本份 pending context，再 emit 并停止读写；解决前不得发射 intent 问题。
5. 扫描核对解决或跳过后，最小写入 Bootstrap observed 与已有有效 locator 的 intent。没有 pending intent 时直接检查 section；否则按本份轮次 emit，未用满的题位保持为空。
6. Continuation 只从调用方保存的本份 pending context 恢复，并先核对 target 与 exact bytes/anchor 仍一致。用户同意 intent 时，先由调用方以本 confirmation batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再最小写入。用户自由文本不直接成为 evidence；先回 repository 复核。Statement 语义变化、拒绝或未确认时退休未写入 ID 且永不复用；语义变化后重新 allocation，不能回退 manifest high-water mark。
7. 把每条 Claim 放入关键任务与用户流程、交互状态与转换、反馈错误与用户下一步、输入与操作约定、响应式与跨设备行为或可访问性对应 section，不用 catch-all 捆绑。只保留用户可见行为；视觉、实现、产品理由、可靠性、安全与验证内容路由各自 owner。
8. 检查上述每个语义 section 的三态：填充、删除，或以不带 Claim ID 的 `unknown` 明确证据不足；只有 heading、模板提示或空表属于静默留空。Adopt 不得借此删除或改写未选择的人写内容。
9. 删除精确 `harnesskit:todo-checklist:start` / `end` marker 包围的完整 authoring checklist block；marker 缺对时停止，不删除其他 comment 或人写内容。准备当前 Markdown 的完整 tracked inventory，包含此前保留项与本轮新增项；每项只含 `id`、`kind` 与 observed `sources` 或已成立的 `confirmed_by`，然后把 direct inventory 通过 stdin 交给 tooling：

   ```sh
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/INTERACTION_DESIGN.md" --stdin <<'JSON'
   {
     "items": []
   }
   JSON
   ```

   示例 payload 只表示 direct inventory envelope；仅当当前 Markdown 没有 tracked Claim 时才使用空 `items`，否则提交完整 inventory。Tooling 计算 whole-file SHA-256、canonical ordering 并整份替换 manifest-mapped sidecar；不要只提交本轮新增项，也不要把 inventory 落盘为中间文件。
10. 运行 `node scripts/claims-verify.cjs verify --json`，按当前 artifact、ID、source 或 confirmation 修正语义输入并重跑到 `passed`。只有此时才把本 artifact 标记为已封存。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只追踪 provenance 能完成的 durable guidance；heading、导航、解释性 prose 与 `unknown` 保持无 ID。
- Adopt 中未选择的人写 bytes 必须逐字保持，只在明确选择项范围内做最小 atomic split、措辞调整与 token 插入。
- 任何 claim-bearing Markdown 都不能自证其中的 observed 或 intent；没有独立 evidence 或 confirmation locator 时不得伪造来源。

## 边界

- 只负责 Interaction Design statement、Claim 边界、`kind`、source paths 与本份问题；不实现 Design System owner 或其他 artifact owner。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当正文来源。
- 不创建或修改 profile materialize，不处理 root/part，不把本 artifact 提升为 canonical；不修改 kickoff、init、artifact registration、receipt 或其他 owner 文档；不得手工编辑 manifest counter，只有 allocation tooling 可更新。
- 不吸收 Design System 的 token/theme/component variant/size/state/visual primitive、Architecture 路径/依赖/数据流、Coding 实现约定、Product Sense 理由、Reliability 的内部幂等/副作用/cleanup/cache/state consistency policy、Security 的 trust boundary/不可信或外部 input/敏感数据/文件或外部 output confinement，或 Validation checks；用户可见 retry/cancel/recovery、表单与 keyboard/pointer input、用户可见反馈仍由本 owner 负责。
- 不为已有 tracked inventory 定义后续更新行为。
