# Stet 架构地图

本文件是 Stet monorepo 的跨端总地图，帮助 agent 先判断应进入哪个模块或目录。端内细节由对应子目录架构文档与代码承载。

## 仓库地图

```text
.
├── AGENTS.md / CLAUDE.md     # 根 agent 入口（统一 monorepo 路由）
├── Makefile                  # 跨端 build / test / lint / ios-build 编排
├── docs/                     # Harness：specs、research、rules、VALIDATION
├── reference/                # Apple 平台参考库（按需读，非项目真相）
├── scripts/                  # 根级校验与编排脚本
├── .github/                  # CI workflows
├── Stet.xcodeproj            # macOS project
├── StetMac/                  # macOS app（App / Core / Features / Shared）
├── StetMacTests/ / StetMacUITests/
├── StetVisuals/              # 共享视觉与 Metal shader
├── Packages/StetEngine/      # 共享 Swift 包（StetCore、StetASR 等）
└── StetMobile/               # iOS app and extensions
    ├── StetMobile.xcodeproj
    ├── StetMobile/           # iOS app
    ├── StetKeyboard/         # 键盘扩展
    ├── StetLiveActivity/     # Live Activity
    ├── StetMobileTests/ / StetMobileUITests/
    └── scripts/              # iOS runtime bootstrap 等
```

| 路径 | 职责 |
|------|------|
| 根 `docs/` | 跨端 harness：架构、specs、研究记录、验证口径 |
| 根 macOS 文件夹 | macOS 应用、共享包、macOS release |
| `StetMobile/` | iOS 应用及扩展 |
| `Packages/` | 跨端共享 Swift 包（iOS 通过相对路径引用） |
| `reference/` | Apple API 参考，按需打开 topic 文件 |

## 核心领域

- **Dictation session**：一次由用户主动启动的语音输入会话。
- **Transcript / HistoryEntry**：SwiftData 持久化的听写转写元数据；保留旧被动记录的字段与导出兼容。
- **Audio pipeline**：采集 → 归一化帧 → VAD / diarization → ASR（Nano / Realtime 等）。
- **Speaker profiles**：Keychain 本地存储的声纹档案，供会议说话人身份匹配使用。

## 关键运行链路

1. **主动 dictation（macOS）**：hotkey → capture → ASR → rewrite（可选）→ 文本输出。
2. **会议录制（macOS）**：显式启动 → 麦克风和系统音频 → `FluidAudioDiarizer` 分段 → Nano 转写与 `SpeakerIdentityService` 身份匹配 → 音频、session.json 与 transcript.md。

   被动监听运行时、持续帧广播、主人验证门及暂停/恢复接线已移除；会议和主动听写不经过被动会话协调器。
3. **iOS dictation**：session coordinator → Realtime / 本地引擎 → 文本输出。

## 依赖与外部边界

- **FunASR / Nano**：macOS 与 iOS 本地 ASR runtime（`StetEngine` / Vendor）。
- **FluidAudio**：macOS 本地转写、音频处理与会议 Sortformer diarization。
- **SherpaOnnxPackage**：speaker embedding（CAMPPlus）。
- **OpenAI-compatible providers**：rewrite 与云端 Realtime。
- **系统框架**：AVFoundation、SwiftUI、SwiftData、Security/Keychain、Metal（StetVisuals）。

## 放置规则

- macOS app 逻辑：`StetMac/`（`App/`、`Core/`、`Features/`、`Shared/`）。
- iOS app 逻辑：`StetMobile/StetMobile/`。
- 跨端共享类型与 ASR：`Packages/StetEngine/Sources/`。
- 共享视觉：`StetVisuals/`。
- 新 feature spec：`docs/specs/`；研究与验证记录：`docs/research/`。
- 根目录承载 macOS 源码、共享包与跨端治理文件；iOS 代码位于 `StetMobile/`。

## 硬约束

- 模型 payload、下载的 runtime framework、build 产物不得入 Git。
- iOS 构建使用 Xcode Beta（`make ios-build`），不改变全局 `xcode-select`。
- macOS 构建使用 stable Xcode（`/Applications/Xcode.app`）。
- 行为真相以代码为准；spec 与研究文档为需求和设计记录，冲突时以代码 + 本文件路由为准。
