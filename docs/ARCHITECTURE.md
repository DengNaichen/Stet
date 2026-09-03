# Stet 架构地图

本文件是 Stet monorepo 的跨端总地图，帮助 agent 先判断应进入哪个模块或目录。端内细节由对应子目录架构文档与代码承载。

## 仓库地图

```text
.
├── AGENTS.md / CLAUDE.md     # 根 agent 入口（统一 monorepo 路由）
├── Makefile                  # 跨端 build / test / lint / ios-build 编排
├── docs/                     # Harness：specs、exec-plans、rules、VALIDATION
├── reference/                # Apple 平台参考库（按需读，非项目真相）
├── scripts/                  # 根级校验与编排脚本
├── .github/                  # CI workflows
├── Public/Stet/              # macOS 子树
│   ├── Stet.xcodeproj
│   ├── StetMac/              # macOS app（App / Core / Features / Shared）
│   ├── StetMacTests/ / StetMacUITests/
│   ├── StetVisuals/          # 共享视觉与 Metal shader
│   ├── Packages/StetEngine/  # 共享 Swift 包（StetCore、StetASR 等）
│   ├── scripts/              # macOS release、notarization 等
│   └── docs/                 # macOS 端内文档（release 等）
└── Private/StetMobile/       # iOS 子树
    ├── StetMobile.xcodeproj
    ├── StetMobile/           # iOS app
    ├── StetKeyboard/         # 键盘扩展
    ├── StetLiveActivity/     # Live Activity
    ├── StetMobileTests/ / StetMobileUITests/
    └── scripts/              # iOS runtime bootstrap 等
```

| 路径 | 职责 |
|------|------|
| 根 `docs/` | 跨端 harness：架构、specs、exec-plans、验证口径 |
| `Public/Stet/` | macOS 应用、共享包、macOS release |
| `Private/StetMobile/` | iOS 应用及扩展 |
| `Public/Stet/Packages/` | 跨端共享 Swift 包（iOS 通过相对路径引用） |
| `reference/` | Apple API 参考，按需打开 topic 文件 |

## 核心领域

- **Dictation session**：一次语音输入会话（主动 hotkey 或被动 listening）。
- **Transcript / HistoryEntry**：SwiftData 持久化的转写元数据；被动模式含 speaker regions。
- **Audio pipeline**：采集 → 归一化帧 → VAD / diarization → ASR（Nano / Realtime 等）。
- **Speaker profiles**：Keychain 本地存储的 enrollment 与 identity gate（被动模式）。

## 关键运行链路

1. **主动 dictation（macOS）**：hotkey → capture → ASR → rewrite（可选）→ 文本输出。
2. **被动 speech gate（macOS）**：continuous capture → speaker gate → Sortformer regions → per-turn Nano → HistoryEntry。
3. **iOS dictation**：session coordinator → Realtime / 本地引擎 → 文本输出。

## 依赖与外部边界

- **FunASR / Nano**：macOS 与 iOS 本地 ASR runtime（`StetEngine` / Vendor）。
- **FluidAudio**：流式 VAD 与 Sortformer diarization（macOS 被动模式）。
- **SherpaOnnxPackage**：speaker embedding（CAMPPlus）。
- **OpenAI-compatible providers**：rewrite 与云端 Realtime。
- **系统框架**：AVFoundation、SwiftUI、SwiftData、Security/Keychain、Metal（StetVisuals）。

## 放置规则

- macOS app 逻辑：`Public/Stet/StetMac/`（`App/`、`Core/`、`Features/`、`Shared/`）。
- iOS app 逻辑：`Private/StetMobile/StetMobile/`。
- 跨端共享类型与 ASR：`Public/Stet/Packages/StetEngine/Sources/`。
- 共享视觉：`Public/Stet/StetVisuals/`。
- 新 feature spec：`docs/specs/`；实现方案：`docs/exec-plans/active/`。
- 根目录仅放 monorepo 治理、CI、跨端 Makefile；不要在此放 app 源码。

## 硬约束

- 模型 payload、下载的 runtime framework、build 产物不得入 Git。
- iOS 构建使用 Xcode Beta（`make ios-build`），不改变全局 `xcode-select`。
- macOS 构建使用 stable Xcode（`/Applications/Xcode.app`）。
- 行为真相以代码为准；spec 与 exec-plan 为设计记录，冲突时以代码 + 本文件路由为准。
