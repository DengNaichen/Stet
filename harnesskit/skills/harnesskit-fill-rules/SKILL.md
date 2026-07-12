---
name: harnesskit-fill-rules
description: 在 Bootstrap 或选择性 Adopt 中生成或选择 root/part rules 的 Markdown-first Claims，拥有 coding/product/security/reliability 问题，并通过 deterministic tooling 建立 provenance。
---

# 生成或采用 Rule Claims

本 skill 直接维护 manifest-registered root/part `docs/rules/*.md` 中被明确追踪的 durable guidance。Markdown 保存 statement；artifact-aligned sidecar 只保存 provenance。

## Owner

Rules 是项目实践判断层：

- `CODING.md` 收命名、代码组织、错误处理、注释、生成资产编辑方式和测试邻接判断；
- `PRODUCT_SENSE.md` 收产品身份、目标用户、价值取舍、核心体验和产品反模式；
- `RELIABILITY.md` 收 failure、recovery、cleanup、retry/replay、compatibility 与状态一致性判断；
- `SECURITY.md` 收 trust boundary、authentication/authorization、input、secret、output 与外部执行 confinement。

CODING、RELIABILITY 和 SECURITY 可在有真实 provenance 时记录本领域硬约束；PRODUCT_SENSE 不强制补造“硬约束”段。模块/数据位置与放置规则归 Architecture；本地环境归 Development；checks 与 receipt 归 Validation；agent 启动与路由归 AGENTS。

## Question ownership

本 skill 只声明 rule-owned intent questions：coding、product、security、reliability guidance 与 hard constraints。Project identity、repo shape、validation entrypoint 和 source-of-truth 位置等共享 Facts 由 `$harnesskit-scan-facts` 声明；不要把代码惯例自动升级为团队 intent。

问题必须展示 tooling 已分配的 Claim ID、所属 rule artifact 与完整推荐 statement，并交给 `$harnesskit-init` 在 Practices 阶段集中 emit。本 skill 不直接 pause，也不新增 Questionnaire 字段。

## Markdown-first workflow

1. 读取 repo-local artifact manifest、materialize 结果、当前 target Markdown 与 scan handoff。Target basename 必须是 manifest 已登记的 rule artifact。
2. Bootstrap 时生成最少但足够的领域 guidance；Adopt 时只选择本轮明确采用的既有 guidance，不把整份人工 policy 自动转成 Claims。
3. 把被选择内容拆成单一 rule owner 下的 atomic statement，并判断 `observed | intent`：
   - observed 只记录 repository evidence 能直接支持的当前行为、边界或 gap，并选择最小安全 source paths；
   - intent 默认声明真实用户 confirmation question；只有 scan handoff 明确提供已存在、独立且权威的 repository confirmation locator 时才复用；
   - 同一句中的当前实现与规范要求必须拆成 observed 与 intent；跨 rule 领域也必须拆分。
4. 对每条新 Claim 调用 tooling 分配 ID，例如：

   ```sh
   node scripts/claims-verify.cjs allocate --artifact "docs/rules/CODING.md" --count 1
   ```

   只使用 allocation 输出。Observed 与 scan handoff 已证明存在有效 repository confirmation 的 intent 可把 `[CODING-0001]` token 与 statement 写入 Markdown；默认 intent 等待用户确认且不得先改 target。为 pending intent 保存 artifact、ID、完整 statement，以及 Adopt exact selected bytes 或 Bootstrap insertion anchor。实际 namespace 由 artifact manifest 决定；不要手写、猜测或复用 ID，普通交叉引用使用裸 ID，非规范示例使用 `[CODING-NNNN]` 这类不匹配真实编号的占位符。
5. 对 pending intent 向 init 返回按 ID 的 question declaration。用户同意后，先由 init 以本 batch 唯一且 immutable 的 `confirm-user` ref 记录确认，再核对 target 与保存的 selected bytes/anchor 仍一致并执行最小写入。自定义修正若改变语义，退休旧 ID、更新 draft 并重新确认。未确认或被拒绝时丢弃 draft，target Markdown 保持未改，allocated ID 退休且不复用。
6. 为每个 rule artifact 分别准备当前 Markdown 的**完整 tracked inventory**，包括此前保留项与本轮新增项；每项只含 `id`、agent 判断的 `kind`、observed source path 列表或已成立 `confirmed_by`，然后调用：

   ```sh
   mkdir -p .harnesskit/audit/evidence
   node scripts/claims-verify.cjs write-sidecar --artifact "docs/rules/CODING.md" --input ".harnesskit/audit/evidence/coding-sidecar-input.json"
   ```

   Tooling 计算 whole-file SHA-256、canonical order，并整份替换最终 sidecar；不能只提交本轮新增项。每个 artifact 独立写入；空 inventory 写空 `items`。
7. 运行 `node scripts/claims-verify.cjs verify --json`，按具体 rule artifact、ID 或 source 修正语义输入并重跑到 `passed`。

Part artifact 使用 manifest 中的实际 path、namespace 与 sidecar mapping，不套用 root 示例 ID。

## Bootstrap / Adopt 写入纪律

- Bootstrap 只追踪 provenance 能完成的 durable guidance；heading、导航、解释性 prose、示例和未决 placeholder 保持无 ID。
- Adopt 中未选择的人写 bytes 必须逐字保持。只在被选择项范围内做最小 atomic split、必要措辞调整和 token 插入。
- Claim 不绑定固定 heading、列表、列或 template section；不要新增整套结构来包围人工内容。
- 现有 target Markdown 不能自证其中的 intent；没有明确、独立的 confirmation locator 时必须真实询问用户，不得发明确认来源或要求新增决策文档。

## 边界

- Agent 只负责 statement、Claim 边界、`kind`、source path 与 confirmation question。
- 不计算 ID、SHA-256、JSON ordering，不手写最终 sidecar，也不把 provenance metadata 当作正文来源。
- 没有具体行为、违规形态或真实 intent 时，不把通用建议升级为 rule。
- 不复制 validation 命令/状态或 architecture 放置规则；只保留本领域判断并链接 owner。
- 不修改未选择的人写内容、receipt 或其他 owner 文档；不得手工编辑 artifact manifest counter，只有 allocation tooling 可以更新它。
- 不为已有 tracked inventory 定义后续更新行为。
