# Implementation Plan: Audio Post-Processing

## Overview

本实现计划将 audio-post-processing 功能分解为离散的编码任务。该功能负责在音频捕获完成后、发送到转录服务之前，对音频文件进行分析和增强处理。

实现方法：
- 从核心音频分析基础设施开始
- 添加语音检测和质量指标计算
- 实现语音感知增益处理
- 集成到现有录音管道
- 添加全面的测试

---

## Tasks

- [x] 1. 定义核心协议和数据模型
  - [x] 1.1 定义 AudioPostProcessing 协议
    - 定义 `processAudioFile(at:duration:)` 方法签名
    - 标记协议为 Sendable
    - *Requirements: 10.1, 10.2, 10.3*
  
  - [x] 1.2 实现 AudioPostProcessingResult 结构体
    - 添加 url、duration、cleanupURLs、shouldDiscardAsNoSpeech 属性
    - 实现 `passthrough(url:duration:)` 静态方法
    - 实现 `discard(url:duration:)` 静态方法
    - 实现 `rewritten(sourceURL:rewrittenURL:duration:)` 静态方法
    - 标记为 Sendable
    - *Requirements: 10.1, 10.2, 10.3, 10.4, 10.5*
  
  - [x] 1.3 定义 SpeechEnhancing 协议
    - 定义 `enhanceAudioFile(at:analysis:)` 方法签名
    - 标记协议为 Sendable
    - *Requirements: 4.1, 5.1*
  
  - [x] 1.4 实现 SpeechEnhancementResult 结构体
    - 添加 outputURL、didRewriteAudio 属性
    - 标记为 Sendable
    - *Requirements: 5.3, 5.4*
  
  - [x] 1.5 实现 SpeechEnhancementPlan 结构体
    - 添加所有增强参数属性
    - 实现 `disabled` 静态常量
    - 标记为 Sendable
    - *Requirements: 3.4, 4.3, 4.4, 4.5*
  
  - [x] 1.6 定义 SpeechEnhancementError 枚举
    - 添加 unableToCreateOutputFormat 错误
    - 添加 unableToCreateOutputBuffer 错误
    - 添加 unableToAccessOutputChannelData 错误
    - *Requirements: 6.4*

- [x] 2. 实现音频信号分析器
  - [x] 2.1 创建 AudioAnalysis 结构体
    - 添加 shouldDiscardAsNoSpeech 属性
    - 添加 speechFrameRatio 属性
    - 添加 noiseFloorDBFS 属性
    - 添加 speechLevelP75DBFS 属性
    - 添加 overallPeakDBFS 属性
    - 添加 recommendedGainDB 属性
    - 实现 speechEnhancementPlan 计算属性
    - 实现 summaryLine 计算属性
    - 标记为 Sendable
    - *Requirements: 1.4, 1.5, 1.6, 1.7, 1.8, 7.1*
  
  - [x] 2.2 创建 AudioSignalAnalyzer 枚举
    - 定义 Configuration 嵌套结构体
    - 设置 speechProbabilityThreshold = 0.8
    - 设置 minimumSpeechSegmentDuration = 0.4
    - 设置 analysisFrameDuration = 0.02
    - 设置 analysisHopDuration = 0.01
    - 设置 targetSpeechLevelDBFS = -20
    - 设置 maxBoostDB = 10
    - 设置 maxCutDB = -4
    - 设置 limiterCeilingDBFS = -1
    - 设置 lowNoiseMarginDB = 4
    - 设置 fullNoiseMarginDB = 8
    - 设置 enhancementGainEpsilonDB = 0.5
    - 设置 attenuationThresholdAboveTargetDB = 6
    - *Requirements: 8.1, 8.3, 8.5, 8.6, 9.1, 9.2, 9.3, 9.4*
  
  - [x] 2.3 实现 analyze(samples:sampleRate:) 方法
    - 处理空样本边界情况
    - 归一化样本到 VAD 采样率
    - 使用 VadManager 检测语音片段
    - 过滤短语音片段（< 0.4 秒）
    - 计算语音帧比率
    - 计算整体峰值电平
    - 创建语音掩码
    - 计算帧级指标
    - 计算语音电平 P75
    - 计算噪声底噪 P20
    - 计算推荐增益
    - 返回 AudioAnalysis 结果
    - *Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.1*
  
  - [x] 2.4 实现 makeSpeechEnhancementPlan(from:) 方法
    - 检查是否标记为无语音
    - 检查增益是否超过阈值（0.5 dB）
    - 创建 SpeechEnhancementPlan 实例
    - 设置所有增强参数
    - *Requirements: 3.1, 3.2, 3.3, 3.4*
  
  - [x] 2.5 实现 normalizeSamplesForAnalysis(samples:sampleRate:) 私有方法
    - 检查采样率是否需要转换
    - 使用 AudioConverter 重采样到 16kHz
    - 返回归一化样本
    - *Requirements: 1.1*
  
  - [x] 2.6 实现 frameMetrics(samples:sampleRate:speechMask:) 私有方法
    - 计算帧长度和跳跃长度
    - 遍历所有帧
    - 计算每帧的 RMS 电平
    - 根据语音掩码分类为语音帧或噪声帧
    - 返回语音帧电平和噪声帧电平数组
    - *Requirements: 1.5, 1.6, 9.1, 9.2*
  
  - [x] 2.7 实现 makeSpeechMask(sampleCount:sampleRate:segments:) 私有方法
    - 创建布尔数组，长度等于样本数
    - 遍历所有语音片段
    - 标记语音片段范围内的样本为 true
    - 返回语音掩码
    - *Requirements: 1.2*
  
  - [x] 2.8 实现 coverage(in:start:end:) 私有方法
    - 计算范围内标记为 true 的样本数
    - 返回覆盖率（0 到 1）
    - *Requirements: 1.4*
  
  - [x] 2.9 实现 peakDBFS(from:) 私有方法
    - 找到样本的最大绝对值
    - 转换为 DBFS（20 * log10）
    - 处理零值边界情况（返回 -160）
    - *Requirements: 1.7*
  
  - [x] 2.10 实现 rmsDBFS(from:) 私有方法
    - 计算样本的均方根
    - 转换为 DBFS（20 * log10）
    - 处理零值边界情况（返回 -160）
    - *Requirements: 1.5, 1.6*
  
  - [x] 2.11 实现 percentile(_:_:) 私有方法
    - 排序数值数组
    - 计算百分位数位置
    - 使用线性插值计算结果
    - 处理边界情况
    - *Requirements: 1.5, 1.6*
  
  - [x] 2.12 实现 recommendedGainDB(speechLevelDBFS:noiseFloorDBFS:overallPeakDBFS:) 私有方法
    - 计算原始增益（目标 - 当前）
    - 应用增益边界（+10 / -4 dB）
    - 根据信噪比缩放正增益
    - 应用峰值安全限制
    - 返回最终推荐增益
    - *Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7*

- [x] 3. 实现语音感知增益处理器
  - [x] 3.1 创建 SpeechAwareGainProcessor 结构体
    - 定义 Configuration 嵌套枚举
    - 设置 frameDuration = 0.02
    - 设置 hopDuration = 0.01
    - 设置 lowNoiseMarginDB = 4
    - 设置 fullNoiseMarginDB = 8
    - 设置 minimumConfidence = 0
    - 实现 init()
    - 符合 SpeechEnhancing 协议
    - *Requirements: 4.1, 4.2, 4.3, 9.1, 9.2*
  
  - [x] 3.2 实现 enhanceAudioFile(at:analysis:) 方法
    - 检查文件格式（仅处理 WAV）
    - 检查是否需要增强
    - 使用 AudioConverter 加载样本
    - 调用 applyEnhancement 处理样本
    - 检查样本是否改变
    - 调用 writeSamples 写入文件
    - 返回 SpeechEnhancementResult
    - *Requirements: 3.1, 3.2, 3.3, 5.1, 5.4, 5.5, 6.1*
  
  - [x] 3.3 实现 applyEnhancement(to:sampleRate:analysis:) 静态方法
    - 验证输入参数
    - 检查是否需要增强
    - 计算帧参数
    - 计算攻击/释放步长
    - 转换限幅器上限到线性值
    - 初始化平滑增益为 0
    - 遍历所有帧
    - 对每帧应用增益和限幅
    - 返回增强后的样本
    - *Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6*
  
  - [x] 3.4 实现 speechConfidence(frameRMSDB:noiseFloorDBFS:) 静态方法
    - 计算信噪比边际
    - 如果边际 ≤ 4 dB，返回 0
    - 如果边际 ≥ 8 dB，返回 1
    - 否则线性插值
    - 处理无效值边界情况
    - *Requirements: 4.2, 4.6, 8.6*
  
  - [x] 3.5 实现 rmsDBFS(from:) 静态方法
    - 计算样本的均方根
    - 转换为 DBFS
    - 处理零值边界情况
    - *Requirements: 4.1*
  
  - [x] 3.6 实现 dbToLinear(_:) 静态方法
    - 使用公式 10^(gainDB/20)
    - 处理无效值边界情况
    - *Requirements: 4.3*
  
  - [x] 3.7 实现 clampSample(_:ceilingLinear:) 静态方法
    - 限制样本在 [-ceiling, ceiling] 范围内
    - 转换为 Float
    - 处理无效值边界情况
    - *Requirements: 4.5*
  
  - [x] 3.8 实现 writeSamples(_:) 私有静态方法
    - 创建 16-bit PCM 输出格式
    - 生成临时文件 URL
    - 创建 AVAudioFile
    - 创建 AVAudioPCMBuffer
    - 转换样本到 Int16
    - 写入文件
    - 返回文件 URL
    - *Requirements: 5.1, 5.2, 5.3*

- [x] 4. 实现默认音频后处理器
  - [x] 4.1 创建 DefaultAudioPostProcessor 类
    - 添加 speechEnhancer 依赖
    - 实现 init(settingsStore:speechEnhancer:)
    - 符合 AudioPostProcessing 协议
    - 标记为 @unchecked Sendable
    - *Requirements: 3.1, 4.1*
  
  - [x] 4.2 实现 processAudioFile(at:duration:) 方法
    - 检查文件扩展名（仅处理 WAV）
    - 加载音频文件和样本
    - 获取文件采样率
    - 调用 AudioSignalAnalyzer.analyze
    - 记录分析摘要（Info 级别）
    - 记录性能跟踪摘要（如果启用）
    - 检查是否标记为无语音
    - 如果无语音，记录警告并返回 discard
    - 调用 speechEnhancer.enhanceAudioFile
    - 检查是否重写了音频
    - 如果重写，记录 Info 并返回 rewritten
    - 否则返回 passthrough
    - *Requirements: 1.1, 1.8, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 5.1, 5.4, 6.1, 7.1, 7.2, 7.3, 7.4*
  
  - [x] 4.3 添加错误处理
    - 捕获音频文件加载错误
    - 记录警告并返回 passthrough
    - 捕获语音增强错误
    - 记录警告并返回 passthrough
    - *Requirements: 6.2, 6.3, 6.4*

- [x] 5. 集成到录音管道
  - [x] 5.1 在 ConfigurableSpeechService 中集成
    - 添加 audioPostProcessor 依赖
    - 在录音完成后调用 processAudioFile
    - 处理 passthrough 结果
    - 处理 discard 结果
    - 处理 rewritten 结果
    - 清理临时文件
    - *Requirements: 10.1, 10.2, 10.3, 10.4*

- [x] 6. Checkpoint - 核心功能完成
  - 确保所有测试通过，如有问题请询问用户。

- [ ]* 7. 编写单元测试
  - [ ]* 7.1 编写 AudioPostProcessingResult 测试
    - 测试 passthrough 创建正确的结果
    - 测试 discard 创建正确的结果
    - 测试 rewritten 创建正确的结果
    - *Requirements: 10.1, 10.2, 10.3, 10.4, 10.5*
  
  - [ ]* 7.2 编写 AudioSignalAnalyzer 测试
    - 测试空样本返回无语音分析
    - 测试静音返回无语音分析
    - 测试语音样本检测到语音
    - 测试噪声底噪计算
    - 测试语音电平计算
    - 测试推荐增益在边界内
    - 测试增强计划生成
    - *Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.1, 3.1, 3.2, 3.3, 3.4*
  
  - [ ]* 7.3 编写 SpeechAwareGainProcessor 测试
    - 测试静音不请求增强
    - 测试静音不被提升
    - 测试安静语音被提升
    - 测试响亮语音不被提升
    - 测试限幅器防止削波
    - 测试增强是确定性的
    - 测试语音置信度计算
    - 测试 RMS 计算
    - 测试 dB 到线性转换
    - 测试样本限幅
    - *Requirements: 3.1, 3.2, 3.3, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6*
  
  - [ ]* 7.4 编写 DefaultAudioPostProcessor 测试
    - 测试非 WAV 文件直接传递
    - 测试无语音录音被丢弃
    - 测试语音录音被增强
    - 测试增益不足时跳过增强
    - 测试文件加载失败时降级
    - 测试语音增强失败时降级
    - *Requirements: 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 6.1, 6.2, 6.3*

- [ ]* 8. 编写属性测试
  - [ ]* 8.1 编写增益边界属性测试
    - **Property 3: 增益推荐在有效范围内**
    - 生成随机语音电平、噪声底噪、峰值
    - 验证推荐增益在 [-4, 10] 范围内
    - *Requirements: 8.3, 8.5*
  
  - [ ]* 8.2 编写限幅器属性测试
    - **Property 5: 输出样本不超过限幅器上限**
    - 生成随机样本和分析结果
    - 验证增强后样本 ≤ 限幅器上限
    - *Requirements: 4.5*
  
  - [ ]* 8.3 编写语音置信度属性测试
    - **Property 6: 语音置信度在有效范围内**
    - 生成随机帧 RMS 和噪声底噪
    - 验证置信度在 [0, 1] 范围内
    - *Requirements: 4.2*
  
  - [ ]* 8.4 编写样本数保持属性测试
    - **Property 12: 增强后样本数不变**
    - 生成随机样本数组
    - 验证增强后样本数等于输入样本数
    - *Requirements: 5.2*
  
  - [ ]* 8.5 编写百分位数属性测试
    - **Property 8: 百分位数在数据范围内**
    - 生成随机数值数组
    - 验证百分位数在 [min, max] 范围内
    - *Requirements: 1.5, 1.6*
  
  - [ ]* 8.6 编写语音掩码属性测试
    - **Property 9: 语音掩码长度等于样本数**
    - 生成随机样本数和语音片段
    - 验证掩码长度等于样本数
    - *Requirements: 1.2*
  
  - [ ]* 8.7 编写帧覆盖率属性测试
    - **Property 10: 帧覆盖率在有效范围内**
    - 生成随机语音掩码和帧范围
    - 验证覆盖率在 [0, 1] 范围内
    - *Requirements: 1.4*

- [ ]* 9. 编写集成测试
  - [ ]* 9.1 编写端到端测试
    - 测试完整的后处理管道
    - 使用真实的音频文件
    - 验证输出文件格式
    - 验证输出文件质量
    - *Requirements: 所有*
  
  - [ ]* 9.2 编写性能测试
    - 测试 10 秒音频的处理时间
    - 验证 VAD 分析 < 500ms
    - 验证增益处理 < 200ms
    - 验证总延迟 < 录音时长的 20%
    - *Requirements: 性能要求*

- [~] 10. Final checkpoint - 完整功能验证
  - 确保所有测试通过，如有问题请询问用户。

---

## Notes

- 标记为 `*` 的任务是可选的测试任务，可以跳过以加快 MVP 开发
- 每个任务引用特定的需求以便追溯
- 属性测试使用 swift-check 库和 XCTest
- 单元测试使用 Swift Testing 框架
- 集成测试使用真实的音频文件和 CoreAudio API
- UI 组件（Views）不进行单元测试，仅测试业务逻辑
- 所有业务逻辑都通过单元测试和属性测试进行全面测试
- Checkpoint 确保在关键里程碑进行增量验证

---

## Implementation Status

本任务文档描述的是**已实现**的功能。所有核心组件和功能都已经存在于代码库中：

- ✅ 核心协议和数据模型（任务 1）
- ✅ 音频信号分析器（任务 2）
- ✅ 语音感知增益处理器（任务 3）
- ✅ 默认音频后处理器（任务 4）
- ✅ 录音管道集成（任务 5）
- ✅ 核心功能 Checkpoint（任务 6）
- ⚠️ 部分单元测试已实现（任务 7）
- ⏳ 属性测试待实现（任务 8）
- ⏳ 集成测试待补充（任务 9）
- ⏳ 最终验证待完成（任务 10）

**测试覆盖状态**：
- ✅ AudioPostProcessingResult 基本测试
- ✅ SpeechAwareGainProcessor 核心测试
- ✅ AudioSignalAnalyzer 基本测试
- ⚠️ 需要补充更多边界情况测试
- ⚠️ 需要实现属性测试
- ⚠️ 需要补充集成测试
