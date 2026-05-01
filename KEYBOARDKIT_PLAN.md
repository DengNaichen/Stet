# KeyboardKit 集成方案：完整键盘 + 语音输入按钮

## 背景

当前 StetKeyboard 只有一个 mic 按钮 + 少量辅助键，不是完整键盘。目标是用 KeyboardKit 提供标准 QWERTY 布局，在右上角保留现有语音输入按钮，录音/转写逻辑完全不动。

KeyboardKit 10.4.1 已在本地 `/Users/nd/Developer/testvoice/KeyboardKit/`，只是尚未接入 Xcode 项目。

---

## 需要改动的文件

| 文件 | 改动内容 |
|------|----------|
| `StetKeyboard/KeyboardViewController.swift` | 改继承 `KeyboardInputViewController`，删 `viewDidLoad` 手动 view 拼装，新增 `viewWillSetupKeyboard`，其余所有 dictation 方法原样保留 |
| `StetKeyboard/KeyboardView.swift` | 全部替换为 `StetKeyboardView`（包裹 `SystemKeyboard` + 顶部 toolbar） |
| `testvoice.xcodeproj`（Xcode GUI 操作） | 添加 local package + StetKeyboard target 链接 KeyboardKit |

**完全不动**：entitlements、Info.plist、主 App 所有文件、SharedDictationManager / DictationSession / DictationState（原样保留在 KeyboardViewController.swift 底部）

---

## Step 1：Xcode 接入 local package（GUI 操作）

1. Xcode → File → Add Package Dependencies → Add Local…
2. 选择 `/Users/nd/Developer/testvoice/KeyboardKit/`
3. "Add to Target" 只勾 **StetKeyboard**（不加 testvoice 主 App）
4. 确认 StetKeyboard Build Phases → Link Binary With Libraries 出现 `KeyboardKit`
5. 若 Xcode 未自动 embed，手动在 StetKeyboard Build Phases 加 "Embed Frameworks" phase，放入 KeyboardKit.xcframework

---

## Step 2：改写 StetKeyboard/KeyboardViewController.swift

```swift
import UIKit
import KeyboardKit

class KeyboardViewController: KeyboardInputViewController {

    private var pollTimer: Timer?
    private var lastProcessedSessionId: String?
    private var pendingSessionId: String?

    override func viewWillSetupKeyboard() {
        super.viewWillSetupKeyboard()

        // 明确高度，防止 iOS 首次 launch 拒绝显示
        let h = view.heightAnchor.constraint(equalToConstant: 300)
        h.priority = .required - 1
        h.isActive = true

        setup { [weak self] controller in
            StetKeyboardView(controller: controller as! KeyboardViewController)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startPolling()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPolling()
    }

    // ---- 以下方法原样保留，一字不改 ----
    // handleMicDown()
    // handleMicUp()
    // openMainApp(sessionId:)
    // startPolling() / stopPolling()
    // checkForNewTranscription()
    // insertFinalResult()
}

// SharedDictationManager / DictationSession / DictationState 原样留在文件底部
```

> `handleMicDown` / `handleMicUp` 需从 `private` 改为 `internal`（去掉 private），供 StetKeyboardView 调用。

---

## Step 3：替换 StetKeyboard/KeyboardView.swift

```swift
import SwiftUI
import KeyboardKit

struct StetKeyboardView: View {
    unowned let controller: KeyboardViewController

    @EnvironmentObject private var keyboardContext: KeyboardContext

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            SystemKeyboard(
                state: controller.state,
                services: controller.services
            )
        }
    }

    private var toolbar: some View {
        HStack {
            Spacer()
            MicButton(
                onDown: controller.handleMicDown,
                onUp:   controller.handleMicUp
            )
            .padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(Color(.systemGray5))
    }
}

struct MicButton: View {
    let onDown: () -> Void
    let onUp: () -> Void

    @State private var isPressing = false

    var body: some View {
        Image(systemName: isPressing ? "mic.fill" : "mic")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 80, height: 34)
            .background(isPressing ? Color.red : Color.black)
            .clipShape(Capsule())
            .scaleEffect(isPressing ? 1.08 : 1.0)
            .animation(.spring(response: 0.2), value: isPressing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressing { isPressing = true; onDown() }
                    }
                    .onEnded { _ in
                        isPressing = false
                        onUp()
                    }
            )
    }
}
```

---

## 关键 API 说明（KeyboardKit v10）

- `KeyboardInputViewController` — 替代 `UIInputViewController`，提供 `state`、`services` 属性和 `setup { controller in ... }` 方法
- `controller.state` — `KeyboardState`，包含 context / feedback / settings
- `controller.services` — `KeyboardServices`，包含 actionHandler / layoutProvider / styleProvider
- `SystemKeyboard(state:services:)` — 渲染完整 QWERTY，支持多语言，自动处理高度
- EnvironmentObject 由 `setup` 闭包自动注入，不需要手动注入

如果 API 签名与上面略有出入，以 `KeyboardKit/Sources/KeyboardKit/` 源码为准做最小调整。

---

## 可能遇到的问题

| 问题 | 处理 |
|------|------|
| binary embed 失败 | 手动加 Embed Frameworks build phase |
| `controller.state` 名称不对 | 查 `KeyboardInputViewController+Setup.swift` |
| `@EnvironmentObject` crash | 确保在 `setup { }` 闭包内构造 view（框架会自动注入） |
| `handleMicDown` private 访问报错 | 去掉 `private` 关键字 |

---

## 验证步骤

1. Build 无报错
2. 真机调出 StetKeyboard，确认 QWERTY 正常显示并能输入
3. 右上角 mic 按钮存在，按住变红
4. testvoice 主 App 后台运行 → 按住 mic 说话 → 松开 → 文字插入光标处
5. Globe 切换键盘正常
6. 首次切换不再反复失败
