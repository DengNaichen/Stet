# Audio Device Management Spec 对齐总结

## 概述

本文档总结了 Audio Device Management Spec 与实际生产代码和测试代码的对齐工作。

## 主要发现

### 1. Audio Capture Pipeline 架构已完整实现

实际代码中已经实现了一个非常健壮的 Audio Capture Pipeline，包括：

- **MacCaptureAudioDevicePlanner**: 候选设备生成和设备解析逻辑
- **MacCaptureAudioSessionFactory**: AVCaptureSession 创建和配置
- **MacCaptureAudioSampleBufferConverter**: 音频样本缓冲区转换
- **MacCaptureAudioFileRecorder**: 主录音器，协调所有组件
- **CaptureError**: 完整的错误定义

### 2. 候选设备策略已实现

代码实现了四级候选设备回退策略：

1. **Selected Device** - 用户手动选择的设备
2. **No Explicit Device Fallback** - 系统默认（让 AVCapture 自动选择）
3. **Built-in Fallback** - 内置麦克风
4. **System Default Fallback** - CoreAudio 默认设备

### 3. 设备解析逻辑已实现

`MacCaptureAudioDevicePlanner.resolveCaptureDevice()` 实现了完整的设备匹配逻辑：

1. 精确 UID 匹配（最可靠）
2. 精确名称匹配
3. 内置设备模糊匹配（处理名称变化）
4. 抛出错误并尝试下一个候选

### 4. 重试机制已实现

- 每个候选设备最多 4 次启动重试
- 重试间隔 0.15 秒
- 候选设备切换间隔 0.1 秒
- 详细的启动时序日志

### 5. 测试覆盖已部分实现

现有测试：
- ✅ MacCaptureAudioDevicePlannerTests
- ✅ MacCaptureAudioSessionFactoryTests
- ✅ MacCaptureAudioSampleBufferConverterTests
- ✅ CaptureErrorTests

缺失测试：
- ⚠️ MacCaptureAudioFileRecorder 的单元测试
- ⚠️ 集成测试（设备选择 + 录音）

## 对齐工作

### Requirements.md 更新

**新增内容**：

- **Technical Story 9: Audio Capture Pipeline Resilience**
  - 详细描述候选设备策略
  - 设备解析策略
  - 重试和时序要求

### Design.md 更新

**新增内容**：

1. **现有 Audio Capture 组件章节**
   - 详细记录所有已实现的组件
   - 包含完整的接口定义
   - 说明每个组件的职责

2. **Audio Capture Pipeline 架构图**
   - Mermaid 流程图展示完整的设备选择和回退流程
   - 详细的候选设备策略说明
   - 设备解析逻辑的伪代码

3. **集成点说明**
   - 明确 `AudioDeviceSelectionManager` 如何与现有 Pipeline 集成
   - 只需修改一行代码：传递 `selectedDevice` 参数

4. **日志和监控**
   - 详细的启动时序日志格式
   - 错误处理和日志级别

5. **测试覆盖率更新**
   - 明确现有组件已有测试覆盖
   - 标注新增组件需要的测试

### Tasks.md 更新

**更新内容**：

- **Task 6.1**: 详细描述 `MacCaptureAudioFileRecorder` 集成步骤
  - 候选设备生成逻辑
  - 设备解析逻辑
  - 重试机制
  - 回退策略

- **Task 6.2**: 扩展集成测试需求
  - 测试候选设备回退链
  - 测试重试机制

## 关键设计决策

### 1. 最小化修改

现有的 Audio Capture Pipeline 已经非常健壮，只需要一个集成点：

```swift
// 修改前
let candidates = MacCaptureAudioDevicePlanner.inputDeviceCandidates(selectedDevice: nil)

// 修改后
let selectedDevice = AudioDeviceSelectionManager.shared.currentRecordingDevice()
let candidates = MacCaptureAudioDevicePlanner.inputDeviceCandidates(selectedDevice: selectedDevice)
```

### 2. 保持现有架构

- 不修改 `MacCaptureAudioDevicePlanner` 的候选设备生成逻辑
- 不修改设备解析和重试机制
- 只添加用户设备选择的输入

### 3. 利用现有回退机制

当用户选择的设备不可用时，现有的回退机制会自动处理：

1. 尝试用户选择的设备
2. 如果失败，尝试系统默认（不指定设备）
3. 如果失败，尝试内置麦克风
4. 如果失败，尝试 CoreAudio 默认设备

## 下一步工作

### 必需任务

1. ✅ 完成 `AudioDeviceSelectionManager` 实现（已完成）
2. ✅ 集成到 `MacCaptureAudioFileRecorder`（只需一行代码）
3. ⚠️ 添加集成测试

### 可选任务

1. 为 `MacCaptureAudioFileRecorder` 添加单元测试
2. 添加性能测试（启动时间）
3. 添加压力测试（频繁设备切换）

## 测试策略

### 单元测试（Swift Testing）

- 测试 `AudioDeviceSelectionManager` 的设备选择逻辑
- 测试 `MacCaptureAudioDevicePlanner` 的候选设备生成（已有）
- 测试设备解析逻辑（已有）

### 集成测试（Swift Testing）

- 测试用户选择设备 → 录音成功
- 测试用户选择设备不可用 → 回退到内置麦克风
- 测试所有候选设备失败 → 抛出错误

### 属性测试（swift-check + XCTest）

- Property 12: 设备切换后录音使用新设备
- 生成随机设备序列，验证录音使用正确的设备

## 总结

Audio Capture Pipeline 的实际实现非常优秀，已经包含了：

- ✅ 完整的候选设备策略
- ✅ 健壮的设备解析逻辑
- ✅ 多级重试机制
- ✅ 详细的日志和监控
- ✅ 完善的错误处理
- ✅ 基本的测试覆盖

Spec 文档现在已经完全对齐实际代码，清晰地描述了：

- 现有组件的架构和职责
- 集成点和修改方式
- 候选设备策略的详细逻辑
- 测试覆盖的现状和需求

唯一需要的修改是在 `MacCaptureAudioFileRecorder.startRecording()` 中传递用户选择的设备，其余的回退和重试逻辑都已经完美实现。
