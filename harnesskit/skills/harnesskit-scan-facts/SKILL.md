---
name: harnesskit-scan-facts
description: 为 Context Harness 的 Bootstrap 或选择性 Adopt 扫描 repository evidence、判断 repo shape、路由 artifact candidates，并声明共享 Facts 问题；不写最终 Markdown 或 provenance sidecar。
---

# 扫描 Repository Facts

本 skill 是共享 evidence 与 Facts owner。它把最小但足够的证据和候选语义交给 artifact-specific fill skills；Markdown statement、Claim selection、`kind`、source path 和 confirmation question 由对应 owner 完成。

## 输入

从仓库根目录读取 repository-owned evidence：

- 现有 context Markdown 与 repo-local artifact manifest；
- README、产品文档，以及仓库明确声明为权威的 guidance source（若实际存在）；
- manifests、lockfiles、workspace config、源码入口和 generated-source 声明；
- tests、validation runner/config、scripts、hooks/CI 和最新 receipt。

忽略 dependency、cache、build output、editor metadata、runtime secret 与临时 workspace。模板和示例只说明结构，不能单独证明目标仓库事实。对会改变 agent 行动的候选，回到权威 source、config、test 或仓库已明确采用的 guidance owner 核对。

先用 materialize 结果标记 HarnessKit 内部资产：本轮 `created` 的 `.harnesskit/**`、`scripts/claims-verify.cjs`、`scripts/verify` 和 `scripts/verify.cjs` 只服务 init 完成门禁，不是 repository-owned evidence，也不能作为 validation entrypoint 候选。相同脚本路径只有在 `skipped_existing` 且独立仓库证据证明其为目标仓库原有入口时才可交给 owner；`.harnesskit/**` 始终不交给 Markdown owner。

## Artifact 路由

每个候选只交给一个语义 owner：

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

Project-local procedures 使用独立 skill 合同，不进入 Markdown Claim inventory。不要把完整事实复制给多个 owner；需要交叉引用时使用 owner 文档链接。

## Shared Facts question ownership

本 skill 只声明跨 artifact 共享、无法从 evidence 收敛的 Facts 问题：

- project identity、purpose 与 users；
- repo shape 与真实 part roots；
- validation entrypoint 是什么；
- 重要 source/test/docs/config/schema 的权威位置在哪里。

“X 在哪 / 是什么”属于共享 Facts；“X 之间如何约束 / agent 应如何判断”属于对应 fill skill 的 Practices。Architecture dependency boundary、validation action rule、AGENTS route 和领域 rule 不能由本 skill 代问。

把问题声明交给 `$harnesskit-init` 集中组轮；本 skill 不直接 emit `needs_input`。没有真实分叉就不声明问题，不为凑数量提问。

## 扫描流程

1. 读取 materialize 结果，区分新建 skeleton 与已有 Markdown。若已有非空 Claim inventory，报告当前 Bootstrap/Adopt 范围外并停止定义后续更新语义。
2. 根据 workspace/manifest、独立 build/test 入口与 operation boundary 判断 single project 或 monorepo。目录名、`docs/`、`scripts/`、examples、generated/vendor/cache、单 package 内分层都不能单独证明 part。
3. 对每个确认的 root/part 做 compressed scan：先读 manifest 与入口，再只在高影响分叉处下钻。保留会改变定位、行动、验证、安全或可靠性判断的候选，丢弃函数级琐碎。
4. 为每个候选记录安全的 repo-relative evidence paths、简短摘要与唯一 artifact owner。先排除 HarnessKit 内部完成门禁及其执行结果；不要提前组织最终 statement，不要手写 Claim ID、hash 或 sidecar item。
5. 对 shared Facts 中 evidence 无法收敛的内容声明问题。用户自由文本只作为定向复核线索；必须回 repository source 验证。
6. Facts 收敛后，把 evidence/candidate handoff 交给对应 fill skill。不要修改 final Markdown、Claim sidecar、namespace counter 或 confirmation record。

## Claim 语义纪律

- 候选必须能拆成一个可独立移动、确认或退休的 atomic statement；mixed observed/intent 或 mixed owner 先拆分。
- `observed` 只能由当前 repository evidence 支持；absence、exception、best-effort 与 known gap 必须写进最终 statement 的边界。
- `intent` 默认由真实用户确认。只有 repository evidence 明确建立了不同于 claim-bearing artifact 的独立、权威 confirmation source，才可复用该安全 locator；现有 target Markdown 本身不能自证 intent，也不得发明确认来源。
- Source path 是 agent 的语义选择；SHA-256、ID、JSON serialization/order 与 inventory comparison 都交给 deterministic tooling。
- Partial evidence 不得推导“全部”“永远”“完整覆盖”等无限范围结论。

## Bootstrap 与 Adopt

- Bootstrap 只向 owner 交付有足够 provenance 的 durable-guidance candidates；未决内容保持 open question 或不带 Claim ID 的 placeholder。
- Adopt 可读取已有 Markdown 以理解候选，但只交付本轮明确选择的 guidance。未选择的人写内容不进入 inventory，也不能因为缺少 sidecar item 被当作错误。
- 被选择的 mixed 人写句子要标出最小拆分边界，让 owner 只修改该范围；其余 bytes 保持不变。

## Repo shape 边界

只处理 repo-local manifest 已登记的 canonical claim-bearing artifacts。若确认的 part 需要尚未登记的 artifact，报告 registration/tooling gap；不要手工发明 namespace、sidecar mapping 或 high-water mark。

## 边界

- 不生成或更新 final Markdown、sidecar、receipt、confirmation record 或 project-local skill。
- Repo-owned README/产品文档在它们确实是 identity、purpose 或 users 的 owner 时可以作为 observed source；技术和行动性事实仍要回对应 source/config/test owner 核对。不要把 template/example、过时或冲突 guidance、用户回答或 latest receipt 单独当成 observed evidence。
- 不虚构 command、tool、URL、CI、release、branch protection、compatibility、security policy 或 runtime capability。
- 不新增 Questionnaire 字段、固定问题数或新的运行状态。
- 不把 source bytes 未变化误当成 statement 语义正确；evidence review 仍由 agent 负责。
- 不把 `.harnesskit/**`、本轮 materialize 创建的 support scripts、Claim verifier 输出或 HarnessKit receipt 当作目标仓库事实、validation entrypoint 或 observed source。
