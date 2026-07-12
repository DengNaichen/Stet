# [PROJECT_NAME] 验证

本文件是当前仓库的验证规范：说明有哪些验证项、证据来源、runner 绑定、触发状态和 receipt 行为。硬约束分布在各实践文件和 [ARCHITECTURE.md](ARCHITECTURE.md) 的"硬约束"段，操作入口放在 [AGENTS.md](../AGENTS.md)。

不要假设仓库使用 Git、SVN、pre-commit、CI 或平台 gate。只有从真实配置、脚本、清单、runner、receipt 或团队确认中核对过的检查，才能写成已配置 validation。

<!-- harnesskit:todo-checklist:start -->
补全本文件前请确认：

- 每个验证项都有证据路径或团队确认来源。
- 未绑定的检查标记为 `unknown`、`absent` 或 `manual`，不要写成强制完成条件。
- Runner 只执行已经确认的质量保障命令；不要从模板示例推断目标仓库支持 lint、test、build 或 coverage。
- 触发入口 / 绑定只记录已经配置的入口；第一版默认只有本地手动 runner，不默认 agent skill、hook、CI 或 platform gate。
<!-- harnesskit:todo-checklist:end -->

## 模型

- **验证项**：需要检查什么，例如 format、lint、typecheck、test、build、docs 或 security checks。
- **Runner**：实际执行 validation 的命令或脚本，例如 [`scripts/verify`](../scripts/verify)。
- **Runner config**：runner 读取的动态配置，例如 [`.harnesskit/validation.json`](../.harnesskit/validation.json)。
- **触发入口 / 绑定**：谁触发 runner，例如 agent skill、人工本地命令、hook、CI 或 platform gate。
- **Receipt**：runner 写出的执行证据，例如 `.harnesskit/receipts/latest.json`。

## 验证项

| 项目 | 状态 | 命令 / 来源 | 证据 | 备注 |
| --- | --- | --- | --- | --- |
| Claim provenance | configured | `node scripts/claims-verify.cjs --json` | `scripts/claims-verify.cjs`, `.harnesskit/audit/artifact-manifest.json`, `.harnesskit/audit/claims/*.json`, canonical Markdown | 校验 literal Claim token inventory 与 sidecar ID 集合一致，并校验 schema、ID、source freshness 和 intent confirmation；任一 violation 返回非零。 |

## Runner

主 runner 是 [`scripts/verify`](../scripts/verify)，由 [`scripts/verify.cjs`](../scripts/verify.cjs) 支撑。

Runner 配置是 [`.harnesskit/validation.json`](../.harnesskit/validation.json)。默认只注册随 harness 下发、并由 canonical Markdown 中的 literal Claim token inventory 与 provenance sidecars 提供仓库证据的 `claims-verify` check；目标仓库的 lint、test、build 等命令仍只能在找到真实仓库证据后加入。

Runner 要求：

- 只执行已由仓库证据确认的验证命令。
- 从 runner 配置读取 checks；不要根据仓库类型、包管理器、VCS 或模板示例推断命令。
- 将 receipt 写入 `.harnesskit/receipts/latest.json` 和 `.harnesskit/receipts/runs/<run_id>.json`。
- 只有所有已配置 check 都通过时才返回 `passed`。
- 只有已配置命令返回非零退出码时才返回 `failed`。
- 没有配置 runner 或 checks 时返回 `not_configured`。
- 只有触发入口明确跳过验证并记录原因时才返回 `skipped`。
- `claims-verify` 对 manifest/sidecar schema、Claim ID inventory 对应与唯一性、source safety/freshness、intent confirmation、canonical order 或路径违规返回非零。

## 触发入口 / 绑定

| 触发入口 | 状态 | 命令 / 行为 | 证据 |
| --- | --- | --- | --- |
| 本地手动 | configured | 在仓库根目录运行 `scripts/verify` 或 `node scripts/verify.cjs`。 | `scripts/verify`, `scripts/verify.cjs`, `scripts/claims-verify.cjs`, `.harnesskit/validation.json` |

## Receipts

最新 receipt 预期路径：`.harnesskit/receipts/latest.json`

历史 receipt 预期路径：`.harnesskit/receipts/runs/<run_id>.json`

默认模板已经配置 `claims-verify`；fresh template 的 Markdown inventory 与空 sidecar items 一致，因此该 check 通过并写出 `passed` receipt。后续任何 inventory、schema 或 provenance violation 都会让 check 返回非零并写出 `failed` receipt。若目标仓库后来移除 runner 或全部 checks，`not_configured` 仍只表示缺少已确认配置，不是验证通过。

Receipt 最小字段：

```json
{
  "schema_version": 1,
  "run_id": "...",
  "trigger": "manual",
  "mode": "full",
  "status": "passed",
  "config_path": ".harnesskit/validation.json",
  "started_at": "...",
  "finished_at": "...",
  "checks": [
    {
      "name": "<confirmed-check-name>",
      "command": "<confirmed validation command>",
      "status": "passed",
      "exit_code": 0
    }
  ]
}
```

## 递归防护

- Hook 绑定不能调用会递归触发同一 hook 的命令。
- 完整验证不能依赖 hook 副作用，除非该 hook 明确属于被验证的 runner。
- 运行验证后应报告 runner mode 和 receipt 路径，不能根据计划运行的命令推断成功。

## 报告口径

报告验证状态时必须区分：

- `passed`：已配置 checks 已运行且通过。
- `failed`：已配置 checks 已运行，且至少一个失败。
- `not_configured`：runner 或 checks 缺失；这不是质量失败。
- `skipped`：验证被有意跳过，并记录了原因。
- `not_run`：验证适用但未执行。
