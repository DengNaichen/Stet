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

---

## 去掉订阅制 / Relay

### 方向

全面转向一次买断 + BYOK + Apple Intelligence，关闭 relay 托管服务。

### 动因

- 订阅制和目标用户错配：在意所有权、不想把内容交给云端的人恰恰最反感订阅
- 产品主张是"这是你的文字"，订阅制隐含"你在租用我们的服务"，逻辑矛盾
- Relay 的运营负担（服务器、监控、账单、客服）与小众产品规模不匹配
- Apple Intelligence 让无 API key 用户也有本地出路，转变在技术上可行

### 现实目标

产品做不大，接受这个天花板。最有价值的结果是：深度整合 Apple Intelligence、界面干净、去掉订阅复杂度，符合 Apple 编辑推荐的选品逻辑。

### 改动范围

- 删 `RelayTextRewriteService`、`RelayDictationTranscriptionService`
- 删 `AIExecutionMode.managed` 及所有分支
- 删 Supabase / 认证流程
- 清理 Settings、Onboarding 中的托管模式入口
- 约 1-2 天工作量，注意清理散落的 `.managed` 判断
