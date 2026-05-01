# iOS 集成计划：接入 StetEngine 共享包

## 架构概览

```
Stet/ (monorepo root)
├── Stet.xcodeproj                    ← macOS app (不动)
├── Packages/StetEngine/              ← 共享包 (已完成)
│   ├── StetCore    → 模型枚举、Provider、RewriteModel
│   ├── StetAI      → OpenAI/Anthropic/Google 服务、API Key 验证
│   └── StetRewrite → TextRewriteService 协议、prompt 工程
└── StetMobile/
    ├── StetMobile.xcodeproj           ← iOS app
    │   └── 添加 ../Packages/StetEngine 为 local package
    └── StetMobile/
        ├── Core/Engine/              ← SenseVoice 引擎 (保留不动)
        ├── Core/Settings/            ← 新增：RewriteSettingsStore
        ├── Features/Dictation/       ← 改造：接入 rewrite 管线
        └── Features/Settings/        ← 新增：AI Provider 设置 UI
```

---

## 现状

| 能力 | macOS ✅ | iOS ❌ |
|---|---|---|
| 本地转写 (SenseVoice) | ✅ | ✅ (已有) |
| AI Rewrite (transcript cleanup) | ✅ via StetAI | ❌ 无 |
| AI Provider 管理 (API key, model) | ✅ Keychain + UI | ❌ 无 |
| Provider 验证 (validateCredential) | ✅ via StetAI | ❌ 无 |

## 目标

1. iOS 端接入 `StetEngine` 共享包
2. 转写后自动走 AI rewrite（可选开关）
3. iOS 端有自己的 Settings UI 管理 API key + model 选择
4. 不涉及 iCloud 同步，两端独立存储

---

## Phase 1：链接 StetEngine 包 ✅ DONE

**做什么**：在 `StetMobile.xcodeproj` 中添加 `../Packages/StetEngine` 作为 local Swift package dependency。

**步骤**：
1. Xcode → StetMobile.xcodeproj → Project Settings → Package Dependencies → Add Local → 选择 `Packages/StetEngine`
2. 给 `StetMobile` target 添加 framework 依赖：`StetCore`, `StetAI`, `StetRewrite`
3. 如果 `StetKeyboard` extension 也需要 rewrite 能力，同样添加依赖

**验证**：在任意 iOS 文件中写 `import StetCore; import StetAI; import StetRewrite` 并编译通过。

> StetEngine 已验证无 `#if os(macOS)` 和 UI imports，iOS 直接可用。

---

## Phase 2：Rewrite 管线 ✅ DONE

### 2.1 新增 `RewriteSettingsStore`

iOS 端的 credential 和偏好存储，独立于 macOS 的 `DictationSettingsStore`。

```
StetMobile/Core/Settings/RewriteSettingsStore.swift
```

**职责**：
- 存取 API key（Keychain，按 provider 分 account）
- 存取 rewrite 开关（UserDefaults）
- 存取选中的 provider 和 model（UserDefaults）
- 构建 `RewriteProviderConfiguration`

**依赖**：`import StetCore`, `import StetAI`

**关键类型复用**：
- `DictationProvider` — 枚举已有 openAI/groq/deepSeek/google/anthropic
- `DictationProviderConfigurationResolver.rewriteConfiguration(...)` — 直接调用
- `ProviderCredentialValidationService` — API key 验证

### 2.2 改造 `SenseVoiceViewModel` 的 finalize 流程

现在的流程：
```
录音 → VAD 分段 → SenseVoice decode → 拼接 → 显示
```

改造后：
```
录音 → VAD 分段 → SenseVoice decode → 拼接 → [Rewrite] → 显示
                                                  ↑
                                          TextRewriteService
                                          (来自 StetAI 包)
```

**关键**：Rewrite 失败时 **永远 fallback 到原始转写**，不丢文本。

---

## Phase 3：Settings UI ✅ DONE

### 3.1 新增 Settings 页面

```
StetMobile/Features/Settings/
├── Views/
│   └── RewriteSettingsView.swift
└── ViewModels/
    └── RewriteSettingsViewModel.swift
```

**UI 内容**：

| 控件 | 绑定 |
|---|---|
| Toggle: "Transcript Improvement" | rewrite 开关 |
| Picker: Provider | openAI / google / anthropic / groq |
| SecureField: API Key | 当前 provider 的 key |
| Picker: Model | 当前 provider 可用模型列表 |
| Button: "Validate" | 调用 `ProviderCredentialValidationService` |
| 状态文本 | 验证结果 / 错误信息 |

### 3.2 接入 ContentView

在 TabView 中添加 Settings tab。

---

### Execution Notes (Phase 1-3)

**Phase 1 完成项**：
- 修改 `StetMobile.xcodeproj/project.pbxproj` 添加 `XCLocalSwiftPackageReference` 指向 `../Packages/StetEngine`
- 添加 `StetCore`, `StetAI`, `StetRewrite` 三个 `XCSwiftPackageProductDependency` 到 StetMobile target
- 添加三个 framework 到 Frameworks build phase

**Phase 2 完成项**：
- 新建 `StetMobile/Core/Settings/RewriteSettingsStore.swift` — Keychain API key 存取、UserDefaults 偏好、service factory
- 修改 `SenseVoiceViewModel.swift` — 注入 `RewriteSettingsStore`，finalize 中插入 rewrite pipeline，失败时 fallback 到原始文本

**Phase 3 完成项**：
- 新建 `StetMobile/Features/Settings/ViewModels/RewriteSettingsViewModel.swift`
- 新建 `StetMobile/Features/Settings/Views/RewriteSettingsView.swift`
- 修改 `ContentView.swift` — 添加 Settings tab，接收共享 `RewriteSettingsStore`
- 修改 `StetMobileApp.swift` — 在 App 根创建共享 `RewriteSettingsStore`，传入 ViewModel 和 ContentView

**验收状态**：代码编写完成，待 Xcode 编译验证（需要在 Xcode 中打开 StetMobile.xcodeproj 解析包依赖后构建）。

---

## Phase 4：Dictionary 共享

### 现状

- **macOS**：`DictionaryModel` + `DictionaryViewModel` — 完整实现（UserDefaults 持久化、词条解析、增删清空）
- **iOS**：纯 mock — 硬编码词表、`addNewWord()` 为空实现

### 4.1 迁移 `DictionaryModel` 到 StetEngine

把 `Stet/Shared/Models/DictionaryModel.swift` 移入 `Packages/StetEngine/Sources/StetCore/`，加 `public` 访问控制。

`DictionaryModel` 是纯 Foundation 代码（UserDefaults 读写 + String 解析），无平台依赖，可以直接迁移。

### 4.2 iOS 端接入

替换 iOS 的 mock `DictionaryViewModel`，改为调用共享的 `DictionaryModel`：

```swift
import StetCore

@MainActor
final class DictionaryViewModel: ObservableObject {
    private let model = DictionaryModel()
    @Published private(set) var allWords: [String] = []
    @Published var draft = ""

    func load() { allWords = model.loadEntries() }
    func addDraftEntries() {
        allWords = model.addEntries(from: draft)
        draft = ""
    }
    func removeWord(_ word: String) { allWords = model.removeEntry(word) }
}
```

### 4.3 文件变更

| 操作 | 文件 |
|---|---|
| **迁移** | `DictionaryModel.swift` → `StetEngine/Sources/StetCore/` |
| **修改** | macOS `DictionaryViewModel.swift`（加 `import StetCore`） |
| **重写** | iOS `DictionaryViewModel.swift`（调用共享 model） |
| **修改** | iOS `DictionaryView.swift`（接入真实增删 UI） |

---

## Phase 5：iCloud 同步

### 目标

在两端之间同步以下数据，用户在一端修改后另一端自动更新：

| 数据 | 同步方式 | 原因 |
|---|---|---|
| Dictionary 词条 | `NSUbiquitousKeyValueStore` | 数据量小（string array），无冲突风险 |
| API Keys | iCloud Keychain（`kSecAttrSynchronizable`） | 系统级加密同步，不走自定义通道 |

> `NSUbiquitousKeyValueStore` 限制 1MB 总量，Dictionary 词条 + 偏好远远够用。

### 5.1 改造 `DictionaryModel` 的存储后端

Phase 4 中 `DictionaryModel` 用的是 `UserDefaults`。Phase 5 替换为 `NSUbiquitousKeyValueStore`，同时保留 `UserDefaults` 作为本地缓存（离线时可用）。

```swift
// StetCore 包内
public final class SyncedDictionaryStore {
    private let cloud = NSUbiquitousKeyValueStore.default
    private let local = UserDefaults.standard
    private let key = "dictionary.entries"

    public init() {
        // 监听远端变更
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud
        )
        cloud.synchronize()
    }

    public func load() -> [String] {
        cloud.array(forKey: key) as? [String] ?? local.stringArray(forKey: key) ?? []
    }

    public func save(_ entries: [String]) {
        cloud.set(entries, forKey: key)
        local.set(entries, forKey: key)
    }

    @objc private func cloudDidChange(_ note: Notification) {
        // 通知 ViewModel 刷新
        let entries = cloud.array(forKey: key) as? [String] ?? []
        local.set(entries, forKey: key)
        NotificationCenter.default.post(name: .dictionaryDidSync, object: entries)
    }
}
```

### 5.2 API Key 同步

不写自定义同步逻辑。直接在 Keychain 存储时加 `kSecAttrSynchronizable: true`：

```swift
// RewriteSettingsStore / DictationSettingsStore
query[kSecAttrSynchronizable] = true
```

这样 API key 会通过系统 iCloud Keychain 自动同步到另一端，前提是用户登录了同一 Apple ID 并开启了 iCloud Keychain。

### 5.3 前置条件

- 两个 xcodeproj 都需要开启 iCloud capability（Key-value storage）
- Entitlements 中加 `com.apple.developer.ubiquity-kvstore-identifier`
- 两端的 identifier 需要匹配（通常设为 `$(TeamIdentifierPrefix)$(CFBundleIdentifier)`）

### 5.5 文件变更

| 操作 | 文件 |
|---|---|
| **新增** | `StetCore/SyncedDictionaryStore.swift` |
| **修改** | `DictionaryModel.swift`（切换到 synced store） |
| **修改** | 两端 `RewriteSettingsStore` / `DictationSettingsStore`（Keychain sync flag） |
| **修改** | 两端 entitlements（开启 iCloud KVS） |

---

## 不做的事情

- ❌ 不合并 xcodeproj（保持两个独立项目）
