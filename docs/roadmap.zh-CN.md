# 产品方向

## AI Agent 语音确认层

### 核心想法

当 Codex、Claude Code 等 AI coding agent 完成一个任务时，Stet 自动弹出悬浮层，展示任务摘要和选项，用户直接说一句话完成确认，无需切换窗口。

### 示例交互

> Codex 完成了：重构 auth 模块，新增 3 个文件，修改 5 个文件。
> 选项：1. 批准并提交  2. 查看变更  3. 回退

用户说"可以"或"批了"→ 映射到选项 1，继续执行。

### 技术路径

- Agent 侧：Claude Code hook 或 MCP tool，任务完成时通过本地 IPC 通知 Stet
- Stet 侧：监听本地 socket/URL scheme，弹出确认面板
- 意图识别：转录结果 + 选项列表送入 LLM（优先 Apple Intelligence，本地、零延迟）做 zero-shot 分类，无法判断时返回 unclear 再次提示

### 为什么有意思

- AI agent 越来越多、确认步骤越来越频繁，语音是最低摩擦的人在回路方式
- 和产品核心主张一致：用最小摩擦保持对 AI 的掌控
- Apple Intelligence 做意图分类 = 本地、免费、符合隐私定位
