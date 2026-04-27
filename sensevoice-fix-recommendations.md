# SenseVoice 内存泄漏修复方案

## 问题核心

**权衡：** 性能（保持上下文热启动）vs 内存（频繁清理）

你的担心是对的：
- 模型加载（`sv_init_from_file_with_params` + `prewarm`）可能需要 **1-3 秒**
- 对于频繁的语音输入场景，每次都冷启动会严重影响用户体验
- 但不清理会导致内存持续增长

---

## 推荐方案：智能清理策略（Hybrid Approach）

### 核心思路
保持上下文重用以获得性能，但在 **每次转录后重置内部状态**，而不是完全释放上下文。

### 方案 A：添加 C API 的 `sv_reset()` 函数（最优）

#### 1. 在 C API 层添加重置函数

```c
// sensevoice_c.h
SV_API void sv_reset(struct sv_context * ctx);
```

这个函数应该：
- 清理 `sv_full()` 累积的中间状态
- 释放临时缓冲区和 attention cache
- **保留**已加载的模型权重和 GPU 上下文
- 重置转录计数器

#### 2. Swift 层调用

```swift
// SenseVoiceCppContext.swift
func resetState() {
    guard let ctx = context else { return }
    sv_reset(ctx)
    transcriptionCount = 0
}
```

#### 3. 在每次转录后调用

```swift
// SenseVoiceTranscriptionService.swift
let result = try await engine.transcribe(samples: samples, languageCode: languageCode)

// 重置状态但保持模型加载
if !isTransient {
    await engine.resetState()  // 新方法
}
```

**优点：**
- ✅ 保持模型热启动（0ms 延迟）
- ✅ 清理中间状态，防止内存累积
- ✅ 最佳性能和内存平衡

**缺点：**
- ❌ 需要修改 C API（如果你有源码访问权限）
- ❌ 需要重新编译 sensevoice.xcframework

---

### 方案 B：基于内存压力的自适应清理（推荐，无需修改 C API）

如果无法修改 C API，使用智能清理策略：

```swift
// SenseVoiceContextManager.swift
@MainActor
final class SenseVoiceContextManager: ObservableObject {
    // ... existing code ...
    
    private var lastCleanupTime = Date()
    private var transcriptionsSinceCleanup = 0
    private let maxTranscriptionsBeforeCleanup = 10  // 从 5 增加到 10
    private let maxTimeBetweenCleanups: TimeInterval = 300  // 5 分钟
    
    // 新增：内存压力监控
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var isUnderMemoryPressure = false
    
    init() {
        setupMemoryPressureMonitoring()
    }
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        
        memoryPressureSource?.setEventHandler { [weak self] in
            self?.isUnderMemoryPressure = true
            Task { @MainActor in
                await self?.cleanupResources()
            }
        }
        
        memoryPressureSource?.resume()
    }
    
    func shouldCleanupAfterTranscription() -> Bool {
        transcriptionsSinceCleanup += 1
        let timeSinceCleanup = Date().timeIntervalSince(lastCleanupTime)
        
        // 立即清理的条件
        if isUnderMemoryPressure {
            return true
        }
        
        // 达到转录次数上限
        if transcriptionsSinceCleanup >= maxTranscriptionsBeforeCleanup {
            return true
        }
        
        // 超过时间上限
        if timeSinceCleanup >= maxTimeBetweenCleanups {
            return true
        }
        
        return false
    }
    
    func recordCleanup() {
        lastCleanupTime = Date()
        transcriptionsSinceCleanup = 0
        isUnderMemoryPressure = false
    }
}
```

```swift
// SenseVoiceTranscriptionService.swift
func transcribe(...) async throws -> TranscriptionResult {
    // ... existing transcription code ...
    
    let result = try await engine.transcribe(samples: samples, languageCode: languageCode)
    
    // 智能清理决策
    if !isTransient {
        let manager = await contextManagerProvider()
        if await manager.shouldCleanupAfterTranscription() {
            await engine.releaseResources()
            await manager.cleanupResources()
            await manager.recordCleanup()
            
            AppLogger.info(
                "SenseVoice context cleaned up: reason=\(cleanupReason) transcriptionCount=\(transcriptionCount)",
                category: .perfTrace
            )
        }
    } else {
        await engine.releaseResources()
    }
    
    // ... rest of code ...
}
```

**优点：**
- ✅ 无需修改 C API
- ✅ 在正常情况下保持热启动（10 次转录或 5 分钟）
- ✅ 内存压力时自动清理
- ✅ 可配置的清理策略

**缺点：**
- ⚠️ 每 10 次转录会有一次冷启动延迟
- ⚠️ 仍然会有一定的内存累积（但可控）

---

### 方案 C：后台预热 + 双缓冲（最复杂但体验最好）

```swift
@MainActor
final class SenseVoiceContextManager: ObservableObject {
    private var primaryEngine: (any SenseVoiceEngine)?
    private var secondaryEngine: (any SenseVoiceEngine)?
    private var isPrewarmingSecondary = false
    
    func transcribe(...) async throws -> TranscriptionResult {
        // 使用主引擎
        let result = try await primaryEngine.transcribe(...)
        
        // 如果主引擎需要清理，切换到副引擎
        if shouldCleanup() {
            if secondaryEngine == nil && !isPrewarmingSecondary {
                // 后台预热副引擎
                Task.detached(priority: .utility) {
                    let newEngine = try engineFactory(modelURL)
                    try await newEngine.prewarm()
                    await MainActor.run {
                        self.secondaryEngine = newEngine
                    }
                }
            }
            
            // 清理主引擎
            await primaryEngine?.releaseResources()
            
            // 切换引擎
            swap(&primaryEngine, &secondaryEngine)
        }
        
        return result
    }
}
```

**优点：**
- ✅ 用户永远不会感受到冷启动延迟
- ✅ 定期清理内存
- ✅ 最佳用户体验

**缺点：**
- ❌ 内存占用翻倍（两个模型实例）
- ❌ 实现复杂度高
- ❌ 可能不适合大模型

---

## 性能测试数据（需要实测）

我建议先测试一下实际的冷启动时间：

```swift
// 测试代码
func benchmarkColdStart() async {
    let start = ProcessInfo.processInfo.systemUptime
    
    let engine = try SenseVoiceCppEngine(modelURL: modelURL)
    try await engine.prewarm()
    
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    print("Cold start time: \(elapsed * 1000)ms")
}
```

**预期结果：**
- 小模型（sense-voice-small-q5_0）：500-1500ms
- 大模型：2000-4000ms
- GPU 加速：可能更快

如果冷启动时间 < 500ms，那么方案 B 完全可行。
如果冷启动时间 > 2000ms，需要考虑方案 C 或优化 C API。

---

## 最终推荐

### 短期方案（立即可实施）

**方案 B（智能清理）+ 优化参数：**

```swift
// 调整清理阈值
private let maxTranscriptionsBeforeCleanup = 15  // 从 5 增加到 15
private let maxTimeBetweenCleanups: TimeInterval = 600  // 10 分钟

// 添加内存监控
private func currentMemoryUsageMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
    
    let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    
    guard kerr == KERN_SUCCESS else { return 0 }
    return Double(info.resident_size) / 1024.0 / 1024.0
}

func shouldCleanupAfterTranscription() -> Bool {
    let memoryMB = currentMemoryUsageMB()
    
    // 内存超过 500MB 时强制清理
    if memoryMB > 500 {
        AppLogger.warning("SenseVoice memory usage high: \(memoryMB)MB, forcing cleanup")
        return true
    }
    
    // 其他条件...
}
```

### 中期方案（如果有 C API 访问权限）

**方案 A（添加 sv_reset）：**
- 联系 sensevoice 库的维护者
- 提交 PR 添加 `sv_reset()` 函数
- 或者自己 fork 并修改

### 长期方案（如果性能要求极高）

**方案 C（双缓冲）：**
- 适用于高频使用场景
- 需要评估内存成本

---

## 实施步骤

1. **先测试冷启动时间**
   ```bash
   # 在 Xcode 中运行性能测试
   # 记录 sv_init_from_file_with_params + prewarm 的时间
   ```

2. **实施方案 B（智能清理）**
   - 添加内存监控
   - 调整清理阈值（15 次或 10 分钟）
   - 添加详细日志

3. **监控生产环境**
   - 收集内存使用数据
   - 收集用户体验反馈
   - 调整参数

4. **如果需要，升级到方案 A 或 C**

---

## 关键指标

需要监控的指标：
- **冷启动延迟**：用户可感知的延迟阈值是 200-500ms
- **内存增长率**：每次转录增加多少 MB
- **清理频率**：多久触发一次清理
- **用户体验**：是否有用户投诉延迟

---

## 代码示例：完整的智能清理实现

```swift
// SenseVoiceContextManager.swift
@MainActor
final class SenseVoiceContextManager: ObservableObject {
    static let shared = SenseVoiceContextManager()
    
    @Published private(set) var isModelLoaded = false
    @Published private(set) var loadedModelPath: String?
    @Published private(set) var isModelLoading = false
    
    private(set) var engine: (any SenseVoiceEngine)?
    
    // 清理策略参数
    private var transcriptionsSinceCleanup = 0
    private var lastCleanupTime = Date()
    private let maxTranscriptionsBeforeCleanup = 15
    private let maxTimeBetweenCleanups: TimeInterval = 600  // 10 分钟
    private let memoryThresholdMB: Double = 500
    
    // 内存压力监控
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var isUnderMemoryPressure = false
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
        category: "SenseVoiceContext"
    )
    
    init() {
        setupMemoryPressureMonitoring()
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        
        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self else { return }
            self.isUnderMemoryPressure = true
            self.logger.warning("Memory pressure detected, will cleanup on next transcription")
        }
        
        memoryPressureSource?.resume()
    }
    
    func loadModel(
        modelURL: URL,
        engineFactory: @Sendable (URL) throws -> any SenseVoiceEngine
    ) async throws {
        let newPath = modelURL.standardizedFileURL.path
        if let currentPath = loadedModelPath, currentPath != newPath {
            logger.info("SenseVoice model path changed, releasing old model resources.")
            await cleanupResources()
        }
        
        guard engine == nil else { return }
        
        isModelLoading = true
        defer { isModelLoading = false }
        
        do {
            let newEngine = try engineFactory(modelURL)
            try await newEngine.prewarm()
            engine = newEngine
            loadedModelPath = modelURL.standardizedFileURL.path
            isModelLoaded = true
            
            // 重置清理计数器
            transcriptionsSinceCleanup = 0
            lastCleanupTime = Date()
        } catch {
            engine = nil
            loadedModelPath = nil
            isModelLoaded = false
            throw error
        }
    }
    
    func engineIfLoaded(matching modelURL: URL) -> (any SenseVoiceEngine)? {
        guard let engine, let loadedModelPath else { return nil }
        guard loadedModelPath == modelURL.standardizedFileURL.path else { return nil }
        return engine
    }
    
    func shouldCleanupAfterTranscription() -> CleanupDecision {
        transcriptionsSinceCleanup += 1
        let timeSinceCleanup = Date().timeIntervalSince(lastCleanupTime)
        let memoryMB = currentMemoryUsageMB()
        
        // 内存压力 - 最高优先级
        if isUnderMemoryPressure {
            return .cleanup(reason: "memory_pressure")
        }
        
        // 内存超过阈值
        if memoryMB > memoryThresholdMB {
            return .cleanup(reason: "memory_threshold(\(Int(memoryMB))MB)")
        }
        
        // 达到转录次数上限
        if transcriptionsSinceCleanup >= maxTranscriptionsBeforeCleanup {
            return .cleanup(reason: "transcription_count(\(transcriptionsSinceCleanup))")
        }
        
        // 超过时间上限
        if timeSinceCleanup >= maxTimeBetweenCleanups {
            return .cleanup(reason: "time_elapsed(\(Int(timeSinceCleanup))s)")
        }
        
        return .keep
    }
    
    func cleanupResources() async {
        guard let engine else { return }
        
        let memoryBefore = currentMemoryUsageMB()
        logger.notice("SenseVoiceContextManager.cleanupResources: releasing context (memory: \(memoryBefore)MB)")
        
        await engine.releaseResources()
        self.engine = nil
        self.loadedModelPath = nil
        self.isModelLoaded = false
        
        // 重置状态
        transcriptionsSinceCleanup = 0
        lastCleanupTime = Date()
        isUnderMemoryPressure = false
        
        // 等待一帧让系统回收内存
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        let memoryAfter = currentMemoryUsageMB()
        let freed = memoryBefore - memoryAfter
        logger.notice("SenseVoice cleanup completed: freed \(freed)MB (before: \(memoryBefore)MB, after: \(memoryAfter)MB)")
    }
    
    private func currentMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }
    
    enum CleanupDecision {
        case cleanup(reason: String)
        case keep
    }
}
```

```swift
// SenseVoiceTranscriptionService.swift - 修改 transcribe 方法
func transcribe(
    audioFileAt fileURL: URL,
    languageCode: String?,
    prompt _: String?,
    audioDurationSeconds: TimeInterval?
) async throws -> TranscriptionResult {
    // ... 前面的代码保持不变 ...
    
    let manager = await contextManagerProvider()
    
    let engine: any SenseVoiceEngine
    let isTransient: Bool
    
    if let reusedEngine = await manager.engineIfLoaded(matching: modelURL) {
        engine = reusedEngine
        isTransient = false
    } else {
        let newEngine = try engineFactory(modelURL)
        try await newEngine.prewarm()
        engine = newEngine
        isTransient = true
    }
    
    // ... 转录代码 ...
    
    let result = try await engine.transcribe(samples: samples, languageCode: languageCode)
    
    // 智能清理决策
    if isTransient {
        await engine.releaseResources()
    } else {
        let decision = await manager.shouldCleanupAfterTranscription()
        switch decision {
        case .cleanup(let reason):
            AppLogger.info(
                "SenseVoice triggering cleanup: reason=\(reason) transcriptionsSinceLastCleanup=\(await manager.transcriptionsSinceCleanup)",
                category: .perfTrace
            )
            await manager.cleanupResources()
        case .keep:
            break
        }
    }
    
    // ... 后面的代码保持不变 ...
}
```

---

## 总结

**我的推荐：方案 B（智能清理）**

理由：
1. ✅ 无需修改 C API
2. ✅ 在大多数情况下保持热启动（15 次转录内）
3. ✅ 内存压力时自动响应
4. ✅ 实现简单，风险低
5. ✅ 可以根据实际数据调整参数

**关键改进：**
- 从 5 次增加到 15 次转录才清理
- 添加时间维度（10 分钟）
- 添加内存监控（500MB 阈值）
- 添加系统内存压力监听
- 详细的日志记录

这样可以在性能和内存之间取得很好的平衡，同时保持代码的可维护性。
