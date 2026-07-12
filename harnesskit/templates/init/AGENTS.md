# [PROJECT_NAME] 贡献者指南

本文件是当前仓库的 agent 启动入口：保留少量会影响操作判断的事实，并把 agent 路由到架构地图、实践指导和验证入口。它不是项目知识库；完整目录职责放在 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，产品背景放在 `README.md`、`docs/` 或外部文档中。

## AI Coding 原则

- 先澄清再实现：目标、范围、输入输出、验收标准或高影响取舍不清楚时，先说明假设和选项。
- 简单优先：只做当前任务需要的最小改动，不添加未要求的功能、抽象、配置项或未来扩展。
- 外科手术式改动：只改相关文件，匹配现有风格，不顺手重构、重排、格式化或清理无关代码。
- 先核实再判断：涉及运行时行为、配置、依赖、安全边界、模块职责或验证入口时，必须回到源码、配置、脚本、构建清单或命令结果。
- 依据可追溯：项目事实、规则判断和风险判断必须来自真实文件、命令结果或用户确认。
- 目标驱动，小步验证：多步骤任务先给简短计划；修 bug 先复现再修复；复杂任务拆成独立步骤，每步后运行最相关、成本最低的验证。
- 验证真实：清楚区分已通过、失败、未运行、无法运行和缺失检查；不得伪造测试、构建、Lint、CI、覆盖率或安全扫描结果。
- 高风险先确认：权限、认证、会话、数据库、生产配置、敏感文件、依赖、CI、生成模板、coverage threshold、hard gate 或正式规则变更前必须确认。

## 项目事实和现状

<!-- harnesskit:todo-checklist:start -->
补全本节前请确认：

- 只保留会改变 agent 当下操作判断的少量事实。
- 完整目录地图、模块职责和长期设计背景不要写在这里。
- 只记录已确认的事实；无法确认时留空，不要从示例项目套用。
<!-- harnesskit:todo-checklist:end -->

## 工作策略

<!-- harnesskit:todo-checklist:start -->
补全本节前请确认：

- 路由到真实存在的文件；未配置的入口写成未配置或待确认。
- 只写本仓库真实采用或明确希望 agent 遵守的策略。
- 不要在本文件复制完整规则目录、架构地图或 skill 正文。
<!-- harnesskit:todo-checklist:end -->

- 涉及路径职责、模块边界、依赖方向、生成资产或运行链路时读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，再核对相关源码、配置或构建清单。
- 涉及本地开发环境启动、配置或排障时读 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。
- 涉及编码风格、产品体验、安全或可靠性时按需读 [docs/rules/](docs/rules/) 下的对应文件；CODING、RELIABILITY 和 SECURITY 的"硬约束"段包含不能违反的规则，PRODUCT_SENSE 用于产品判断。
- 需要产品定位、功能说明或用户文档时读 `README.md` 和相关文档目录；不要从其他同名/分支项目套用能力。
- 修改用户可见行为、权限、配置默认值、SQL/schema、生成模板或运行脚本前，先明确兼容性边界和影响范围。
- 影响运行时代码、模板、SQL、测试、构建/验证配置或用户可见输出的变更，在完成前按 [docs/VALIDATION.md](docs/VALIDATION.md) 运行已配置验证。
- 发现可复用约定、硬约束候选或待确认事项时，按职责记录到 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、[docs/rules/](docs/rules/) 或 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 验证入口

当前默认配置 claim contract 验证 check；其他项目验证只在找到仓库证据后加入。配置、runner 和 receipt 细节见 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 漂移处理

如果 [AGENTS.md](AGENTS.md)、[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)、[docs/rules/](docs/rules/)、[docs/VALIDATION.md](docs/VALIDATION.md) 或真实仓库状态互相冲突，不要静默选择一边；先核对真实文件，再同步修复漂移的 context 文件。

文档职责保持分离：[AGENTS.md](AGENTS.md) 讲 agent 如何开始和路由，[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 讲仓库地图和架构约束，[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) 讲本地开发环境启动、配置和排障，[docs/rules/](docs/rules/) 讲编码、产品、安全等实践指导和硬约束，[docs/VALIDATION.md](docs/VALIDATION.md) 讲验证配置，`README.md` 和 `docs/` 讲产品与用户背景。
