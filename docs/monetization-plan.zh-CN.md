# 付费逻辑方案 (Monetization Plan)

## 核心设计
针对 **BYOK (Bring Your Own Key)** 模式，付费逻辑的核心是软件的功能授权。

## 试用机制
1. **100 次免费额度**：
   - 用户可以免费进行 100 次成功的听写或重写操作。
   - 计数器记录在本地 `UserDefaults` (`mac.usageCount`)。

## 增加摩擦 (Nagware)
当用户使用次数超过 100 次后，系统不硬性拦截，但会增加“使用摩擦”：
1. **强行弹窗**：每次操作完成后，复用现有的 `ErrorSurface` 机制弹出一个提醒弹窗。
2. **提醒内容**：展示文案：“你已免费使用 Stet {usageCount} 次，如果它提高了你的效率，请考虑支持作者 ❤️”。
3. **手动解除**：用户必须手动点击弹窗上的按钮（如“OK”或“Dismiss”）才能关闭界面。
4. **功能保留**：用户依然可以使用自己的 API Key 进行工作，但每次都会伴随这个提醒弹窗。

## 技术实现点
- **状态机扩展**：在 `DictationFailure` 中增加 `.trialNotice(usageCount: Int)`。
- **UI 路由**：在 `MacDictationPanelView` 中捕获该状态并渲染现有的错误 Surface。
- **逻辑切入**：在 `MacDictationCaptureCoordinator` 完成输出后，检查计数并决定是否返回该状态。
