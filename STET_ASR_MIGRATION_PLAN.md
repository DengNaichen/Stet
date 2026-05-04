# Stet ASR 模块化与统一模型管理迁移计划 (ASR Migration Plan)

## 1. 目标 (Objective)
将 Whisper 和 SenseVoice 引擎及其模型管理逻辑从 `Stet` (macOS) 和 `StetMobile` (iOS) 的主工程中剥离，统一集成到 `StetEngine` Swift Package 的 `StetASR` 模块中。同时，将 iOS 端的模型加载策略从“内置打包 (Bundled)”迁移为“运行时按需下载 (On-demand Download)”，以优化包体积。

## 2. 核心架构 (Architecture)

### 物理结构设计
建议采用自包含的包结构，将底层引擎依赖 (Vendor) 封装在 `StetEngine` 内部：

```text
.
├── Stet.xcodeproj          # macOS 主工程
├── StetMobile/             # iOS 主工程
├── Packages/
│   └── StetEngine/         # 核心逻辑包
│       ├── Package.swift
│       ├── Sources/
│       │   ├── StetCore/     # 基础定义 (Error, Model, Shared Types)
│       │   ├── StetASR/      # ASR 引擎实现 + ModelManager (核心逻辑)
│       │   ├── StetAI/       # 云端 AI (OpenAI 等)
│       │   └── StetRewrite/  # 重写策略逻辑
│       └── Vendor/           # 底层引擎包 (由 StetEngine 内部引用)
│           ├── SherpaOnnxPackage/
│           └── WhisperPackage/
```

### 依赖封装原则
*   **隐藏底层**：主 App 仅 import `StetASR`，不直接接触 `sherpa_onnx` 或 `whisper` 的 C++ 包装层。
*   **内部引用**：`StetEngine/Package.swift` 使用相对路径引用 `Vendor/` 下的本地包。

## 3. 待迁移文件清单 (Source Files)

### A. 从 StetMobile (iOS) 迁出
- `Core/Engine/ASREngine.swift` -> `StetASR/`
- `Core/Engine/SherpaOnnxASREngine.swift` -> `StetASR/`
- `Core/Engine/HotwordPostProcessor.swift` -> `StetASR/`
- `Core/Engine/SenseVoiceResources.swift` -> 重构为 `ASRModelManager`

### B. 从 Stet (macOS) 迁出
- `Core/LocalWhisper/` 全部逻辑 -> `StetASR/`
- `Core/SenseVoice/` 全部逻辑 -> `StetASR/`

### C. 外部包搬迁
- `Vendor/SherpaOnnxPackage` -> `Packages/StetEngine/Vendor/`
- `Vendor/WhisperPackage` -> `Packages/StetEngine/Vendor/`

## 4. 统一模型管理设计 (Unified Model Management)

### 路径策略 (Path Resolution)
- **macOS**: `~/Library/Application Support/Stet/Models/`
- **iOS**: `Library/Application Support/Models/`

### 核心组件：ASRModelManager
1.  **状态定义**：
    ```swift
    enum ASRModelStatus {
        case notDownloaded    // 未下载
        case downloading(Double) // 下载中 (进度)
        case ready(URL)       // 已就绪 (返回本地磁盘路径)
        case error(Error)     // 错误
    }
    ```
2.  **职责**：
    *   统一管理 SenseVoice (.onnx) 和 Whisper (.bin) 的下载。
    *   检查本地文件完整性（MD5/SHA）。
    *   屏蔽平台差异：自动识别是在 macOS 还是 iOS 下运行并选择正确路径。

## 5. 详细迁移步骤 (Action Items)

### 阶段一：建立骨架 (Skeleton)
- [x] 在 `Packages/StetEngine/` 下创建 `Vendor/` 目录。
- [x] 将顶层的 `Vendor/` 内容移动至 `Packages/StetEngine/Vendor/`。
- [x] 更新 `StetEngine/Package.swift`，添加 `StetASR` Target，并配置对内部 Vendor 包的相对路径引用。

### 阶段二：协议与数据模型 (Contracts)
- [x] 将 `ASREngine` 协议、`ASRResult`、`ASRMetrics` 迁移至 `StetASR`。
- [x] 定义通用的 `ASRModelStatus` 及 `ASRModelManager` 接口。

### 阶段三：引擎实现搬迁 (Engines)
- [ ] **SenseVoice**: 迁移 `SherpaOnnxASREngine`，重构其初始化方法以接受 `ModelManager` 提供的 URL。
- [ ] **Whisper**: 迁移 macOS 的 `LocalWhisper` 逻辑，适配新的接口规范。
- [ ] 实现跨平台的 `URLSession` 下载器，用于 `ModelManager` 内部。

### 阶段四：App 端集成与资源清理 (Cleanup)
- [ ] **iOS 端**: 移除 `StetMobile` 项目中内置的所有 `.onnx` 和 `.txt` 文件。
- [ ] **iOS 端**: 在 `SenseVoiceViewModel` 中实现下载状态 UI 的展示。
- [ ] **macOS 端**: 移除旧的 `Core/SenseVoice` 和 `Core/LocalWhisper` 代码，全面切换至 `StetASR`。

## 6. 风险与注意事项
- **存储权限**：iOS 端需确保在下载前正确解析并创建 `Application Support` 目录。
- **构建配置**：确保 `StetEngine` 对底层 C++ 库的链接在 Package 模式下依然生效。
- **Git 历史**：由于涉及文件大范围移动，建议分次 commit 以保留 Git Trace 记录。
