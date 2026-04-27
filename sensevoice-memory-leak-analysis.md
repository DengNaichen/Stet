# SenseVoice Memory Leak Analysis

## Executive Summary

The SenseVoice integration has several memory management issues that can lead to memory leaks and resource accumulation. The problems stem from lifecycle management, context reuse patterns, and C API memory ownership.

---

## Identified Memory Leak Issues

### 1. **Context Reuse Without Proper Cleanup (Primary Issue)**

**Location:** `SenseVoiceTranscriptionService.swift` lines 85-111

**Problem:**
The service attempts to reuse a loaded engine from `SenseVoiceContextManager`, but the context accumulates state across multiple transcriptions without proper cleanup between uses.

```swift
if let reusedEngine = await manager.engineIfLoaded(matching: modelURL) {
    engine = reusedEngine
    isTransient = false
} else {
    let newEngine = try engineFactory(modelURL)
    try await newEngine.prewarm()
    engine = newEngine
    isTransient = true
}
```

**Why it leaks:**
- When `isTransient = false`, the engine is never released after transcription
- The context accumulates internal state from `sv_full()` calls
- No cleanup happens between transcriptions when reusing the context
- The workaround at line 273 (auto-release after 5 transcriptions) is insufficient

---

### 2. **C API String Memory Ownership Unclear**

**Location:** `SenseVoiceTranscriptionService.swift` lines 283-286, 291-294

**Problem:**
```swift
guard let cString = sv_get_text(svCtx, false, true) else { return "" }
return String(cString: cString)
```

**Why it might leak:**
- `sv_get_text()` returns `const char *` but ownership is unclear
- If the C API allocates memory for the string, Swift never frees it
- The C header doesn't document whether the caller owns the returned pointer
- Typical C APIs either:
  - Return a pointer to internal buffer (caller doesn't free) ✓ likely safe
  - Return allocated memory (caller must free) ⚠️ potential leak

**Same issue with:**
- `sv_lang_str(langID)` at line 293

---

### 3. **Actor Isolation and Concurrent Access**

**Location:** `SenseVoiceTranscriptionService.swift` lines 88-111

**Problem:**
```swift
let manager = await contextManagerProvider()

if let reusedEngine = await manager.engineIfLoaded(matching: modelURL) {
    engine = reusedEngine
    isTransient = false
}
```

**Why it's problematic:**
- `SenseVoiceContextManager` is `@MainActor` isolated
- Multiple concurrent transcription requests could race to access the shared engine
- The engine is stored as a non-isolated property in the manager
- `SenseVoiceCppContext` is an actor, but the engine wrapper is not properly isolated

---

### 4. **Transient Engine Cleanup on Error Path**

**Location:** `SenseVoiceTranscriptionService.swift` line 101

**Problem:**
```swift
} catch {
    if isTransient { await engine.releaseResources() }
    // ...
    throw error
}
```

**Why it's incomplete:**
- Only cleans up on error, not on success for transient engines
- Line 111 does clean up on success, but the pattern is fragile
- If an exception occurs between lines 101-111, cleanup might be skipped

---

### 5. **Context Accumulation in sv_full()**

**Location:** `SenseVoiceTranscriptionService.swift` lines 253-276

**Problem:**
```swift
let rc = sv_full(svCtx, buffer.baseAddress, Int32(buffer.count), langPtr, nThreads)
```

**Why it leaks:**
- Each `sv_full()` call may allocate internal buffers for:
  - Encoder/decoder states
  - Attention caches
  - Intermediate tensors
  - GPU memory (when `use_gpu = true`)
- The workaround at line 273 releases after 5 calls, but:
  - Memory accumulates during those 5 calls
  - The threshold is arbitrary
  - No memory pressure monitoring

---

### 6. **GPU Memory Not Explicitly Released**

**Location:** `SenseVoiceTranscriptionService.swift` lines 214-217

**Problem:**
```swift
#if !targetEnvironment(simulator)
    params.use_gpu = true
    params.flash_attn = true
#else
    params.use_gpu = false
#endif
```

**Why it leaks:**
- GPU memory allocated by Metal/CUDA is not tracked by Swift ARC
- `sv_free()` should release GPU memory, but:
  - If the context is reused, GPU memory accumulates
  - Flash attention allocates large temporary buffers
  - No explicit GPU memory cleanup between transcriptions

---

### 7. **DispatchQueue Capture in Actor**

**Location:** `SenseVoiceTranscriptionService.swift` lines 197-199

**Problem:**
```swift
nonisolated private static let inferenceQueue = DispatchQueue(
    label: "com.stet.sensevoice.inference",
    qos: .utility
)
```

**Why it's problematic:**
- The actor uses a static DispatchQueue for inference
- Captures `ctx` (OpaquePointer) in async closures
- If the actor is deallocated while inference is running:
  - The closure still holds the context pointer
  - `deinit` might race with the running inference
  - Potential use-after-free or double-free

---

## Memory Leak Patterns

### Pattern 1: Reused Context Accumulation
```
User dictates → Reuse engine → sv_full() allocates → No cleanup
User dictates → Reuse engine → sv_full() allocates → No cleanup
User dictates → Reuse engine → sv_full() allocates → No cleanup
User dictates → Reuse engine → sv_full() allocates → No cleanup
User dictates → Reuse engine → sv_full() allocates → Cleanup (5th call)
```
**Result:** Memory grows linearly until the 5-call threshold

### Pattern 2: Transient Engine Leak on Manager Transition
```
1. Manager has no loaded engine
2. Create transient engine → transcribe → cleanup ✓
3. Manager loads persistent engine
4. Reuse persistent engine → transcribe → NO cleanup ✗
5. Reuse persistent engine → transcribe → NO cleanup ✗
```
**Result:** Persistent engine never cleaned up until app restart or model change

### Pattern 3: GPU Memory Accumulation
```
sv_full() → Allocate GPU buffers → Keep in context
sv_full() → Allocate GPU buffers → Keep in context
sv_full() → Allocate GPU buffers → Keep in context
```
**Result:** GPU memory grows until `sv_free()` is called

---

## Root Causes

1. **Mismatched Lifecycle Expectations**
   - Swift code expects context reuse for performance
   - C API expects cleanup after each use or periodic cleanup
   - No clear contract in the C header documentation

2. **Missing Cleanup Hooks**
   - No cleanup between transcriptions when reusing context
   - No memory pressure monitoring
   - No explicit GPU memory management

3. **Actor Isolation Mismatch**
   - `@MainActor` manager holding non-isolated engine
   - Actor-based context using static DispatchQueue
   - Potential race conditions on cleanup

4. **Workaround Instead of Fix**
   - Line 273: "auto-releasing context to prevent drift and memory bloat"
   - This acknowledges the problem but doesn't solve it
   - Arbitrary threshold (5 calls) is not memory-aware

---

## Evidence of Known Issues

The code itself contains evidence that the developers were aware of memory issues:

1. **Line 273 comment:**
   ```swift
   AppLogger.info("SenseVoice transcriptionCount reached limit, auto-releasing context to prevent drift and memory bloat.", category: .perfTrace)
   ```
   - Explicitly mentions "memory bloat"
   - Workaround rather than root cause fix

2. **Transient vs Persistent Pattern:**
   - The code distinguishes between transient and persistent engines
   - Only transient engines are cleaned up
   - Suggests awareness that cleanup is needed but unclear when

3. **Context Manager Cleanup Method:**
   - `SenseVoiceContextManager.cleanupResources()` exists
   - Only called on model path change or explicit request
   - Not called during normal operation

---

## Recommended Fixes (Not Implemented)

### Fix 1: Cleanup After Every Transcription
```swift
// Always cleanup after transcription, even for reused engines
defer {
    Task {
        await engine.releaseResources()
        if !isTransient {
            await manager.cleanupResources()
        }
    }
}
```

### Fix 2: Add Memory Pressure Monitoring
```swift
private func shouldCleanupContext() -> Bool {
    let memoryUsage = ProcessInfo.processInfo.physicalMemory
    let threshold = 0.8 // 80% memory usage
    return memoryUsage > threshold
}
```

### Fix 3: Explicit GPU Memory Management
```swift
// After each transcription
if params.use_gpu {
    // Force GPU memory release
    await context.releaseGPUResources()
}
```

### Fix 4: Fix String Memory Ownership
```swift
// If sv_get_text() allocates memory
guard let cString = sv_get_text(svCtx, false, true) else { return "" }
defer { free(UnsafeMutableRawPointer(mutating: cString)) }
return String(cString: cString)
```

### Fix 5: Remove Context Reuse
```swift
// Simplest fix: always create fresh context
let engine = try engineFactory(modelURL)
try await engine.prewarm()
defer { await engine.releaseResources() }
```

---

## Testing Recommendations

1. **Memory Profiling:**
   - Run Instruments with Allocations and Leaks templates
   - Perform 20+ consecutive transcriptions
   - Monitor memory growth pattern

2. **GPU Memory Monitoring:**
   - Use Metal System Trace
   - Check GPU memory allocation over time
   - Verify cleanup on `sv_free()`

3. **Stress Testing:**
   - Rapid consecutive transcriptions
   - Long-running session (100+ transcriptions)
   - Concurrent transcription requests

4. **Leak Detection:**
   - Enable Address Sanitizer
   - Enable Malloc Stack Logging
   - Use `leaks` command-line tool

---

## Impact Assessment

**Severity:** High

**User Impact:**
- Memory usage grows over time during extended dictation sessions
- May cause system slowdown or app termination
- GPU memory exhaustion can affect other apps

**Frequency:**
- Occurs on every transcription when reusing context
- Accumulates linearly with usage
- More severe for users with frequent dictation

**Workaround:**
- Restart app periodically
- Switch to different transcription engine
- The 5-call auto-cleanup provides partial mitigation

---

## Additional Notes

1. The C API documentation is minimal - memory ownership is unclear
2. The workaround suggests this is a known issue
3. The actor isolation pattern may have concurrency bugs
4. GPU memory is particularly problematic as it's not tracked by ARC
5. The context reuse optimization may not be worth the complexity

---

## Files Involved

- `Stet/Core/SenseVoice/SenseVoiceTranscriptionService.swift` (primary)
- `Stet/Core/SenseVoice/SenseVoiceContextManager.swift` (lifecycle)
- `Stet/Core/SenseVoice/SenseVoiceModelManager.swift` (model management)
- `Vendor/SenseVoicePackage/sensevoice.xcframework/` (C API)

---

## Conclusion

The SenseVoice integration has multiple memory management issues, with the primary problem being context reuse without proper cleanup. The code contains workarounds (5-call auto-cleanup) that acknowledge the issue but don't fully resolve it. A comprehensive fix would require either:

1. Eliminating context reuse (simplest, may impact performance)
2. Implementing proper cleanup after each transcription
3. Adding memory pressure monitoring and adaptive cleanup
4. Clarifying C API memory ownership and fixing string handling

The current implementation will leak memory during normal operation, with severity depending on usage patterns.
