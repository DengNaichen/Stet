---
name: harnesskit-kickoff
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 开始时核实 repo shape、part roots 与高影响跨 artifact 信息，以 repository evidence 选择单仓 Web frontend profile，按需声明一次阻塞式 profile 问题，并把 artifact 地图与用户可读的整体计划 brief 交给 init；不生成最终 Markdown、Claim sidecar 或 artifact-specific candidates。
---

# HarnessKit Kickoff

本 skill 是 Bootstrap eligibility preflight、单仓 materialize profile 选择、artifact 地图、整体计划 brief 与预热轮的语义 owner。只读取建立这些结果所需的 repository evidence，判断 repo shape、part roots 与适用 profile，并把选择、地图和 brief 交给 `$harnesskit-init` 动态展开处理计划；init 不自行读取 evidence。Per-artifact 证据发现归各 fill，在对应 artifact 的热上下文中完成。

## Bootstrap eligibility preflight

Bootstrap 必须在 missing-only materialize 之前先做只读 preflight。读取 HarnessKit asset 中的 base 与可选 profile artifact manifest、模板目标路径与目标仓库现状，确认仓库尚未建立 HarnessKit 项目说明；profile 自动选择或回答收敛后，再检查所选 profile 将创建的每个路径及 `CLAUDE.md -> AGENTS.md` alias 是否存在不兼容形态。发现 repo-local HarnessKit manifest、tracked inventory、已建立的 HarnessKit 项目说明或任一目标路径冲突时立即停止并用自然语言说明；不得先创建目录、skeleton、support file、run-state 或任何临时文件。Preflight 通过只表示 Bootstrap 输入安全，不代替 materialize 后的 repo-shape 与整体计划扫描。Adopt 跳过本节，保持既有行为。

## 单仓 Web frontend profile 识别

本节只适用于 Bootstrap 与选择性 Adopt 中 repository evidence 已能建立为 `single project` 的单仓。两种模式都在 materialize 前完成这一道只读 profile routing，因为 materializer 首次调用就必须选择 base 或 overlay；选择性 Adopt 的首次 target mutation、artifact evidence scan、人工内容选择与写入仍从 materialize 后开始，因此保持既有 materialize-first 内容工作流。Evidence 已建立 monorepo，或 single project / monorepo 尚未收敛时，保持 base materialize 且不发 Web profile 问题；后续仍走既有 repo-shape/registration gap 处理，不得把 base 解释为已覆盖 frontend artifacts。Monorepo、part 与 mixed profile routing 在当前范围外：不要为其中某个 part 自动选择或询问 `web-frontend`，也不要声称其 Design System 或 Interaction Design 已被覆盖。

在 materialize 前先读 repository evidence，再选择 profile。只读取足以建立应用表面的 repo-owned identity、package/workspace manifest、build/serve scripts 与 config、browser entrypoint、页面或路由入口及相应测试；generated、vendor、dependency、example、storybook-only 或 cache 内容不能单独决定 profile。分类使用以下可核查 fixture：

- **明确命中**：同一个 single-project scope 同时存在可运行的 browser UI entrypoint、与它可追踪关联的对应 build 或 serve 入口，以及 repo-owned 页面、路由或 UI test evidence；选择 `Web frontend` / `web-frontend`。静态站点可以用其实际发布入口代替长期运行的 server，但仍必须能把入口与 repo-owned UI surface 连起来。
- **明确不命中**：repo-owned identity 与实际 executable target 一致证明该单仓是 native app、CLI、backend service 或 library，且目标 scope 没有另一个 browser UI target；选择 `base`。单纯 absence、目录名或未发现某个文件不能形成 negative 结论。
- **模糊**：只有 framework marker、`package.json`、browser dependency、UI-looking directory、example/story，入口与 build/serve target 无法关联，或 Web/native/backend signal 证据互相冲突；不得猜测 profile。

React、Vue、Svelte、Next、Vite 等 framework marker 只能帮助判断 repo 类型，不能证明任何 artifact 内容；即使明确选择了 `web-frontend`，也只改变 artifact 集合，不能为 `docs/DESIGN_SYSTEM.md`、`docs/INTERACTION_DESIGN.md` 或任何 Claim 提供内容 evidence。

明确命中时自动选择 `web-frontend`；明确不命中时自动选择 `base`。证据不足或冲突且仍确认是 single project 时，只声明一次会改变 artifact 集合的显式 profile 问题，说明接受 `Web frontend profile` 会新增 `docs/DESIGN_SYSTEM.md` 与 `docs/INTERACTION_DESIGN.md`，否则保持 base 集合。问题沿用现有 `single_choice`、`accept` 与自由文本修改入口；既有 `sources[].path` 保留造成分歧的安全 repo-relative evidence path，`summary` / `rationale` 简述 entrypoint、build/serve target 与 UI surface 之间为何能或不能关联，不放原始内容。它不是 Claim、intent confirmation 或 repository fact。把声明交给 init emit 后停止；不得为同一次选择声明第二道 profile 问题。

## 输入与 evidence 边界

从仓库根目录按需读取：

- Bootstrap preflight 中的 HarnessKit asset manifest、模板目标路径与现有 context 路径形态；
- materialize 前用于单仓 profile 识别的 repo-owned identity、package/workspace manifest、build/serve config、browser entrypoint、页面/路由入口与 UI tests；
- preflight 通过后的 materialize 结果、现有 context Markdown 与 repo-local artifact manifest；
- README、产品文档及仓库明确声明为权威的 identity source；
- workspace/package manifests、lockfiles、源码入口、generated-source 声明与 operation boundary；
- validation runner/config、scripts、hooks/CI 与 tests 中能证明真实 validation entrypoint 的最小证据。

忽略 dependency、cache、build output、editor metadata、runtime secret 与临时 workspace。模板和示例只说明结构，不能单独证明目标仓库事实。目录名、`docs/`、`scripts/`、examples、generated/vendor/cache 或单 package 内分层也不能单独证明 part。

先用 materialize 结果标记 HarnessKit 内部资产：本轮 `created` 的 `.harnesskit/**`、`scripts/claims-verify.cjs`、`scripts/verify` 和 `scripts/verify.cjs`，以及 Claim verifier 输出与 HarnessKit receipt，都只服务 init 完成门禁，不是目标仓库事实、validation entrypoint、observed source 或目标验证结果。相同脚本路径只有在 `skipped_existing` 且独立仓库证据证明其为目标仓库原有入口时才能用于地图判断；`.harnesskit/**`、Claim verifier 输出与 HarnessKit receipt 始终排除。

## Artifact 路由（全局硬规则）

每个候选只能有一个语义 owner。各 fill 必须引用并遵守本表；kickoff 保持边界但不为全部 artifact 扫描或枚举 candidates。

| Artifact | Owner |
| --- | --- |
| `AGENTS.md` / part AGENTS | agent 启动、任务路由、行动 gate |
| `docs/ARCHITECTURE.md` / part Architecture | 模块与数据位置、依赖方向、主链路、放置规则 |
| `docs/DESIGN_SYSTEM.md` | semantic token、视觉基础、共享组件外观与视觉状态 |
| `docs/DEVELOPMENT.md` | 本地安装、启动/停止、配置、端口与排障 |
| `docs/INTERACTION_DESIGN.md` | 跨功能复用或单页高影响的用户行为、转换与反馈 |
| `docs/VALIDATION.md` | checks、runner、binding、side effect 与 receipt |
| `docs/rules/CODING.md` | 编码组织、生成源头、测试邻接与注释判断 |
| `docs/rules/PRODUCT_SENSE.md` | 用户承诺、体验取舍与产品反模式 |
| `docs/rules/RELIABILITY.md` | failure、recovery、cleanup、retry 与状态一致性 |
| `docs/rules/SECURITY.md` | trust boundary、auth、input、secret、output 与外部执行 |

Project-local procedures 使用独立 skill 合同，不进入 Markdown Claim inventory。不要把完整内容复制给多个 owner；需要交叉引用时使用 owner 文档链接。

## 预热轮

只在 repository evidence 无法收敛会改变整个 artifact 计划的高影响跨 artifact 信息时声明问题：

- single project / monorepo 与真实 part roots；
- project identity；
- 真实 validation entrypoint。

Evidence 已收敛时为零轮。Kickoff 拥有问题内容与答案复核，init 只负责 emit、pause/resume 和继续编排；不询问阶段批准、写入许可或流程同意，也不为凑数量提问。

用户答案能回 repository 验证时，复核后纳入地图；repository evidence 无法裁决时，把内容路由给对应 artifact owner，在本份轮次内按 intent 处理。用户自由文本只是修正或定向复核指令，不直接成为 evidence 或 durable guidance。

## 整体计划 brief

地图收敛后，向 init 返回一份仅供本次用户说明使用的 brief：使用项目自然名称，按实际 artifact 地图给出用户可理解的有序主题，并说明只有需要核对仓库理解或决定长期做法时才会邀请用户参与。选择 `web-frontend` 时，artifact 地图必须包含 `docs/DESIGN_SYSTEM.md` 与 `docs/INTERACTION_DESIGN.md` 的 manifest registration，brief 必须各用一个用户可理解的主题说明共享视觉系统与高影响交互行为；base 单仓不加入这两个主题。主题名称来自本次地图，不展示内部文件分类、协议字段、tooling 或固定模板术语；不要求用户批准计划，也不持久化 brief。

## Kickoff 流程

1. Bootstrap 与选择性 Adopt 都先用本节的正、负、模糊 fixture，只读选择 single-project materialize profile；Bootstrap 同时执行上述 eligibility preflight，自动收敛后检查所选完整目标集合，路径不安全时零写入退出。选择性 Adopt 此时不扫描或选择现有 artifact 内容。证据不足或冲突时把唯一 profile 问题交给 init emit，并在它 pause 后停止全部 repository 读写，当前运行零写入退出。
2. Profile continuation 只消费现有 paused segment 中已提交的答案，在已完成的 profile boundary 上恢复；明确接受则选择 `web-frontend`，明确要求保持基础集合则选择 `base`。Bootstrap 只完成尚未执行的所选目标路径 safety check；选择性 Adopt 直接交给 materializer 的原子 preflight。两种模式都不重复 evidence scan、已完成轮次或 profile 问题；自由文本仍未给出两者之一时停止并说明，不能猜测或再问一次。
3. Init 按选择运行一次 missing-only materialize。`web-frontend` overlay 遇到已存在的人写 Design System 或 Interaction Design Markdown 时按 `skipped_existing` 保留；若 repo-local manifest 只有 base registration，沿用 materializer conflict 并零部分写入停止，不升级或改写 manifest。读取 materialize 结果与 repo-local manifest，逐 artifact 区分 `created` skeleton、`skipped_existing` Markdown 与 HarnessKit 内部资产；profile 两份 artifact 的结果可以不同，不能把整个运行一律归为 Bootstrap 或 Adopt。若已有非空 tracked inventory，报告当前 Bootstrap/Adopt 范围外，不自行定义更新语义。
4. 只为地图做 compressed scan：复用 materialize 前已收敛的 repo-shape/profile 结论，不重复 profile scan；先看仍未核实的 workspace/manifest 与真实 build/test/operation entrypoint，再只在 part roots、identity 或 validation entrypoint 的高影响分叉处下钻。
5. 综合独立证据判断 single project 或 monorepo，生成包含 repo shape、root/part roots、project identity、validation entrypoint、已选 materialize profile 与 manifest artifact scope 的地图。`web-frontend` 地图只使用 repo-local manifest 已登记的两个附加 artifact；若确认的 part 需要尚未登记的 artifact，报告 registration/tooling gap；不得发明 namespace、sidecar mapping 或 high-water mark。
6. 对仍无法收敛的高影响跨 artifact 信息声明预热轮问题，交给 init emit。Continuation 后重新核实答案，不重做已完成且未受影响的判断。
7. 把当前运行的地图与整体计划 brief 交给 init 展开并展示计划，不创建额外的持久 handoff 文件。到此停止；不得继续扫描 artifact-specific evidence、组织最终 statement 或向各 fill 一次性交付 candidates。

## Claim 语义纪律

以下规则供各 fill 发现 artifact 内容时共同遵守；kickoff 不接管它们的本份轮次：

- 候选必须能拆成一个可独立移动、确认或退休的 atomic statement；mixed observed/intent 或 mixed owner 先拆分。
- `observed` 只能由当前 repository evidence 支持；absence、exception、best-effort 与 known gap 必须写进最终 statement 的边界。
- `intent` 默认由真实用户确认。只有 repository evidence 明确建立了不同于 claim-bearing artifact 的独立、权威 confirmation source，才可复用该安全 locator；现有 target Markdown 本身不能自证 intent，也不得发明确认来源。
- **通用性测试**：若某条规范放到任何同类项目都成立，该规范不得成为 Claim；“同类项目”以目标项目的语言与生态为参照，生态内普遍成立同样属于通用工程常识。有 repository evidence 支持的现状行为仍可按 `observed` 记录，但其规范性影子不追踪、不提问。
- Source path 是 agent 的语义选择；SHA-256、ID、JSON serialization/order 与 inventory comparison 都交给 deterministic tooling。
- Partial evidence 不得推导“全部”“永远”“完整覆盖”等无限范围结论。

## Bootstrap 与 Adopt

- Bootstrap 中，新建 skeleton 和 HarnessKit support assets 不证明目标仓库事实；kickoff 只建立地图，不选择 durable guidance。
- Adopt 中，已有 Markdown 可帮助判断 identity 与边界，但未选择的人写内容不自动进入 Claim inventory，也不自动成为地图证据。

## 边界

- 不生成或更新 final Markdown、Claim sidecar、receipt、confirmation record、namespace counter 或 project-local skill；整体计划 brief 只用于过程说明。
- Bootstrap eligibility preflight 只读，不用“先 materialize 再检查”替代，也不为了保存 preflight 结果写 run-state 或临时文件。
- Bootstrap 与选择性 Adopt 的单仓 profile 选择只决定 base 或现有 `web-frontend` artifact 集合；不新增第三份 artifact，不为 monorepo/part/mixed profile 定义 materialize 或展开规则。
- 不改变 Questionnaire schema、Claim/confirmation/provenance 语义、missing-only 规则、Adopt 对未选择人写 bytes 的保护或 canonical artifact 身份。
- 不执行 per-artifact evidence discovery，不生成 candidate handoff，不替各 fill 判断 statement、`kind`、source path 或本份问题。
- 不让 init 回读 evidence；地图是 kickoff 对本次编排的 handoff。
- 不创建 `facts.md` 或任何额外持久 handoff 文件。
- 不虚构 command、tool、URL、CI、release、branch protection、compatibility、security policy 或 runtime capability。
- 不新增 Questionnaire 字段、固定问题数或新的运行状态。
- 不把 source bytes 未变化误当成 statement 语义正确；evidence review 仍由 agent 负责。
- 不把 `.harnesskit/**`、本轮 materialize 创建的 support scripts、Claim verifier 输出或 HarnessKit receipt 当作目标仓库事实、validation entrypoint、observed source 或目标验证结果。
