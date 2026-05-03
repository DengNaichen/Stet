# 键盘按钮重构方案

## 根本问题

现在有两条并行的状态轨道：

- **View**：每 0.25s 直接读 `SharedDictationManager`，不知道 session 是否属于自己
- **VC**：每 0.5s 读，有 `pendingSessionId`，知道 ownership

两条轨道出现分歧时就产生 bug。所有修补都是在打补丁，治标不治本。

## 方案：VC 作为唯一数据源

**一句话**：VC 是唯一读 `SharedDictationManager` 的地方，算出 `buttonState` 后发布给 View。View 只渲染，不读全局状态。

---

### Step 1：定义 ButtonState

```swift
enum KeyboardButtonState: Equatable {
    case idle
    case pending      // requestStart / launching / warming
    case recording    // recording
    case processing   // requestStop / transcribing / ready
}
```

---

### Step 2：VC 改为 ObservableObject

```swift
class KeyboardViewController: KeyboardInputViewController, ObservableObject {
    @Published var buttonState: KeyboardButtonState = .idle
    @Published var processingStartDate: Date? = nil

    private var pendingSessionId: String?
    private var lastProcessedSessionId: String?
    private var isWakingMainApp = false
    private var pollTimer: Timer?
}
```

---

### Step 3：合并为单一 tick 循环（0.25s）

两个 timer 合并为一个。ownership 检查放在最前面：如果 session 不是我们的，直接返回 idle，不用再打任何补丁。

```swift
private func tick() {
    guard let session = SharedDictationManager.shared.getSession(),
          session.sessionId == pendingSessionId else {
        // 不是我们的 session，或没有 session，直接 idle
        publishState(.idle)
        return
    }

    switch session.state {
    case .idle:
        publishState(.idle)

    case .requestStart, .launching, .warming:
        publishState(.pending)

    case .recording:
        publishState(.recording)

    case .requestStop, .transcribing:
        let appDead = !SharedDictationManager.shared.mainAppAlive(within: 2.0)
        let stale   = Date().timeIntervalSince(session.updatedAt) > 10.0
        if appDead || stale {
            cancelSession()
        } else {
            publishState(.processing)
        }

    case .ready:
        if session.sessionId != lastProcessedSessionId {
            insertText(session)
        }
        publishState(.idle)

    case .inserted, .cancelled, .failed, .timeout:
        cleanupSession()
        publishState(.idle)
    }
}

private func publishState(_ state: KeyboardButtonState) {
    if state == .processing && buttonState != .processing {
        processingStartDate = Date()
    } else if state != .processing {
        processingStartDate = nil
    }
    buttonState = state
}
```

---

### Step 4：View 简化

View 改用 `@ObservedObject`，删掉所有直接读 SharedDictationManager 的代码。

```swift
struct StetKeyboardView: View {
    @ObservedObject var controller: KeyboardViewController
    // 删掉：sessionPoll timer
    // 删掉：sessionState、isPending、isRecording、isProcessing、isActive、isSpeaking

    var body: some View {
        KeyboardView(...)
        // 删掉：.onReceive(sessionPoll)
        // 删掉：.onChange(of: isProcessing)
    }

    private var micToolbar: some View {
        Button(action: toggleRecording) {
            // 直接用 controller.buttonState 和 controller.processingStartDate
        }
        .disabled(controller.buttonState == .processing)
    }
}
```

---

### Step 5：viewDidAppear / viewWillDisappear 清理

有了 ownership check 在 tick 里，这两个地方的逻辑大幅简化：

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    isWakingMainApp = false

    // 恢复我们自己的 session（如果有）
    pendingSessionId = SharedDictationManager.shared.getPendingKeyboardSessionId()

    startPolling() // tick 会自动处理 stale/dead 判断
}

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopPolling()

    // 只有不是主动去录音，才 cancel
    if !isWakingMainApp, let session = SharedDictationManager.shared.getSession(),
       session.sessionId == pendingSessionId {
        switch session.state {
        case .requestStart, .launching, .warming, .recording, .requestStop, .transcribing:
            cancelSession()
        default: break
        }
    }
}
```

---

## 对比

| | 现在 | 重构后 |
|---|---|---|
| 读 SharedDictationManager | View（0.25s）+ VC（0.5s） | 只有 VC（0.25s） |
| Ownership 检查 | 散落在多处补丁里 | tick 第一行，统一处理 |
| Stale/dead 检测 | viewDidAppear + checkForNewTranscription 两处 | tick 里一处 |
| 清理逻辑 | viewDidAppear / viewWillDisappear / checkForNewTranscription 三处 | cancelSession() 一个函数 |
| View 和 VC 状态分歧 | 随时可能发生 | 不可能，View 只读 VC 的值 |

## 改动范围

- `KeyboardViewController.swift`：加 `ObservableObject`，加 `@Published`，合并 timer，重写 `checkForNewTranscription` 为 `tick()`
- `KeyboardView.swift`：`unowned let` 改为 `@ObservedObject`，删 `sessionPoll`，删所有 computed 状态属性，直接用 `controller.buttonState`
- 不涉及 `SharedDictationManager` 或主 app 任何改动
