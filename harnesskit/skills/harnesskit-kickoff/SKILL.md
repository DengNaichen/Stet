---
name: harnesskit-kickoff
description: 在 Context Harness 的 Bootstrap 或选择性 Adopt 开始时核实 repo shape、part roots 与高影响跨 artifact 信息，按需声明预热轮问题，并把基于 repo-local manifest 的 artifact 地图交给 init；不生成最终 Markdown、Claim sidecar 或 artifact-specific candidates。
---

# HarnessKit Kickoff

本 skill 是 artifact 地图与预热轮的语义 owner。只读取建立地图所需的 repository evidence，判断 repo shape 与 part roots，并把地图交给 `$harnesskit-init` 动态展开处理计划；init 不自行读取 evidence。Per-artifact 证据发现归各 fill，在对应 artifact 的热上下文中完成。

## 输入与 evidence 边界

从仓库根目录按需读取：

- materialize 结果、现有 context Markdown 与 repo-local artifact manifest；
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
| `docs/DEVELOPMENT.md` | 本地安装、启动/停止、配置、端口与排障 |
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

## Kickoff 流程

1. 读取 materialize 结果与 repo-local manifest，区分新建 skeleton、已有 Markdown 与 HarnessKit 内部资产。若已有非空 tracked inventory，报告当前 Bootstrap/Adopt 范围外，不自行定义更新语义。
2. 只为地图做 compressed scan：先看 workspace/manifest 与真实 build/test/operation entrypoint，再在 repo-shape、part roots、identity 或 validation entrypoint 的高影响分叉处下钻。
3. 综合独立证据判断 single project 或 monorepo，生成包含 repo shape、root/part roots、project identity、validation entrypoint 与 manifest artifact scope 的地图。若确认的 part 需要尚未登记的 artifact，报告 registration/tooling gap；不得发明 namespace、sidecar mapping 或 high-water mark。
4. 对仍无法收敛的高影响跨 artifact 信息声明预热轮问题，交给 init emit。Continuation 后重新核实答案，不重做已完成且未受影响的判断。
5. 把当前运行的地图交给 init 展开计划，不创建额外的持久 handoff 文件。到此停止；不得继续扫描 artifact-specific evidence、组织最终 statement 或向各 fill 一次性交付 candidates。

## Claim 语义纪律

以下规则供各 fill 发现 artifact 内容时共同遵守；kickoff 不接管它们的本份轮次：

- 候选必须能拆成一个可独立移动、确认或退休的 atomic statement；mixed observed/intent 或 mixed owner 先拆分。
- `observed` 只能由当前 repository evidence 支持；absence、exception、best-effort 与 known gap 必须写进最终 statement 的边界。
- `intent` 默认由真实用户确认。只有 repository evidence 明确建立了不同于 claim-bearing artifact 的独立、权威 confirmation source，才可复用该安全 locator；现有 target Markdown 本身不能自证 intent，也不得发明确认来源。
- Source path 是 agent 的语义选择；SHA-256、ID、JSON serialization/order 与 inventory comparison 都交给 deterministic tooling。
- Partial evidence 不得推导“全部”“永远”“完整覆盖”等无限范围结论。

## Bootstrap 与 Adopt

- Bootstrap 中，新建 skeleton 和 HarnessKit support assets 不证明目标仓库事实；kickoff 只建立地图，不选择 durable guidance。
- Adopt 中，已有 Markdown 可帮助判断 identity 与边界，但未选择的人写内容不自动进入 Claim inventory，也不自动成为地图证据。

## 边界

- 不生成或更新 final Markdown、Claim sidecar、receipt、confirmation record、namespace counter 或 project-local skill。
- 不执行 per-artifact evidence discovery，不生成 candidate handoff，不替各 fill 判断 statement、`kind`、source path 或本份问题。
- 不让 init 回读 evidence；地图是 kickoff 对本次编排的 handoff。
- 不创建 `facts.md` 或任何额外持久 handoff 文件。
- 不虚构 command、tool、URL、CI、release、branch protection、compatibility、security policy 或 runtime capability。
- 不新增 Questionnaire 字段、固定问题数或新的运行状态。
- 不把 source bytes 未变化误当成 statement 语义正确；evidence review 仍由 agent 负责。
- 不把 `.harnesskit/**`、本轮 materialize 创建的 support scripts、Claim verifier 输出或 HarnessKit receipt 当作目标仓库事实、validation entrypoint、observed source 或目标验证结果。
