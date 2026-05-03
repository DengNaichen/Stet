# 键盘录音按钮：现状与问题

## 架构概览

两个文件，两条独立的状态轨道，这是所有 bug 的根源。

### KeyboardView.swift（SwiftUI）
- 每 0.25 秒轮询 `SharedDictationManager`，读取**全局** session 状态
- 根据状态计算 `isPending / isRecording / isProcessing / isActive`，驱动 UI
- **不知道当前 session 是否是自己发起的**

### KeyboardViewController.swift（UIKit）
- 持有 `pendingSessionId`：只有匹配这个 ID 的 session 才是"我们的"
- 每 0.5 秒轮询，只在 session 匹配时插文字或执行 cancel
- 负责生命周期清理（`viewWillDisappear` / `viewDidAppear`）

**核心问题**：View 看全局状态，VC 看自己的 `pendingSessionId`。AppGroup 里任何一个 active 状态的旧 session，都会让 View 显示 processing，哪怕 VC 知道那不是自己的。

---

## 状态机

```
idle
 └─[点击]→ requestStart → launching → warming → recording
                                                    └─[点击]→ requestStop → transcribing → ready → inserted → idle
                                                                                ↓（app 被杀 / 超时 / stale）
                                                                            cancelled / failed / timeout
```

| 计算属性 | 覆盖的状态 | 表现 |
|---|---|---|
| `isActive` | requestStart, launching, warming, recording | 红色按钮 |
| `isProcessing` | requestStop, transcribing, ready | 进度条，按钮禁用 |

---

## Bug 状态

### Bug 1：打开键盘直接显示 processing
**状态**：部分修复，仍有边界情况。

**当前清理逻辑**（`viewDidAppear`）：
```swift
let appDead = !mainAppAlive(within: 2.0)
let stale = Date().timeIntervalSince(session.updatedAt) > 10.0
if pendingSessionId == nil || appDead || stale { cancel() }
```
`stale` 检查解决了"主 app 活着但不认识旧 session"的情况。
剩余边界情况：主 app 刚启动（< 2 秒）且 session 很新（< 10 秒），清理仍会跳过。

---

### Bug 2：主 app 死后/假死后按钮卡在 processing

**状态**：修复。

`checkForNewTranscription` 现在用两个条件 OR 判断是否 cancel：
```swift
let appDead = !mainAppAlive(within: 2.0)
let stale = Date().timeIntervalSince(session.updatedAt) > 10.0
if appDead || stale { cancel() }
```
- `appDead`：主 app 心跳超时（被杀）
- `stale`：主 app 活着但不更新 session（重启后不认识旧 session）

**前提**：主 app 在 `transcribing` 阶段必须持续更新 `session.updatedAt`，否则 10 秒阈值会误 cancel 正常转写。需确认主 app 行为。

---

### Bug 3：viewWillDisappear 缺少 requestStop

**状态**：未修复。

键盘在 `requestStop` 状态被关掉时，session 不会被 cancel：

```swift
// KeyboardViewController.swift viewWillDisappear
case .requestStart, .launching, .warming, .recording, .transcribing:
// ↑ 缺少 .requestStop
```

---

### Bug 4：触觉反馈
**状态**：已搁置。

`UIImpactFeedbackGenerator` 在 keyboard extension 里只有第一次能响。Generator 已移至 VC 作为 class 属性，`prepare()` 在 `viewDidAppear` 和按下时都有调用，但问题未解决。怀疑是 extension 沙盒对触觉引擎的限制，需要进一步调查。

---

## 根本修法（未实施）

View 不应自己读全局 session 状态。应由 VC 综合 `pendingSessionId` + session 状态 + 主 app 心跳，计算出一个简单的 enum 暴露给 View：

```swift
enum KeyboardButtonState {
    case idle
    case pending    // requestStart / launching / warming
    case recording
    case processing // requestStop / transcribing / ready
}
```

VC 作为唯一数据源，View 只管渲染。彻底消灭"View 看到不属于自己的 session"的问题。

重构步骤：

1. VC 里计算 `@Published var buttonState: KeyboardButtonState`
2. View 监听 VC 的 `buttonState`，删除自己的 `sessionPoll` timer
3. 删除 View 里所有直接读 `SharedDictationManager` 的代码
