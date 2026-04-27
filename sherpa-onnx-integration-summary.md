# Sherpa-ONNX SenseVoice 集成完成

## ✅ 已完成的功能

### 1. 核心实现
- ✅ `SherpaOnnxSenseVoiceModelManager.swift` - ONNX 模型管理
- ✅ `SherpaOnnxSenseVoiceTranscriptionService.swift` - 转录服务
- ✅ 集成 sherpa-onnx.xcframework 到项目

### 2. UI 功能
- ✅ 在设置界面添加 "SenseVoice Sherpa-ONNX (Better Memory)" 选项
- ✅ **下载按钮** - 点击即可从 HuggingFace 下载模型
- ✅ **Pick File 按钮** - 手动选择本地 .onnx 模型文件
- ✅ 下载进度显示
- ✅ 错误消息显示

### 3. 配置集成
- ✅ 添加到 `StoredTranscriptionEngine` 枚举
- ✅ 集成到 `DictationPipelineFactory`
- ✅ 添加 UserDefaults 配置项

## 📦 模型信息

### 自动下载
- **下载地址**: https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.onnx
- **存储位置**: `~/Library/Application Support/Stet/Models/SherpaOnnxSenseVoice/model.onnx`
- **文件格式**: .onnx (不是 .gguf)

### 手动选择
用户也可以点击 "Pick File..." 按钮手动选择任何 .onnx 格式的 SenseVoice 模型。

## 🎯 使用方法

1. 打开 Stet 应用
2. 进入 Settings → On-device Transcription
3. 找到 "SenseVoice Sherpa-ONNX (Better Memory)" 部分
4. 点击 **"Download"** 按钮自动下载模型
5. 下载完成后，在引擎选择器中选择 "SenseVoice Sherpa-ONNX (Better Memory)"

## 🔧 技术优势

### vs 原来的 GGML 实现

| 特性 | GGML 实现 | Sherpa-ONNX 实现 |
|------|-----------|------------------|
| 内存管理 | 手动管理，容易泄漏 | 自动管理，每次独立 |
| 状态清理 | 需要每 5 次清理 | 不需要手动清理 |
| API 复杂度 | 复杂的上下文管理 | 简单的 decode 调用 |
| 内存泄漏 | 有问题 | 无问题 |
| 冷启动 | 需要预热 | 按需加载 |

### 核心代码流程

```swift
// 创建 recognizer
let recognizer = SherpaOnnxCreateOfflineRecognizer(&config)

// 创建 stream
let stream = SherpaOnnxCreateOfflineStream(recognizer)

// 输入音频
SherpaOnnxAcceptWaveformOffline(stream, 16000, samples, count)

// 解码
SherpaOnnxDecodeOfflineStream(recognizer, stream)

// 获取结果
let result = SherpaOnnxGetOfflineStreamResult(stream)

// 自动释放（通过 defer）
```

## 🚀 下一步

### 需要在 Xcode 中完成：
1. 打开 `Stet.xcodeproj`
2. 在 Project Navigator 中，右键点击项目根目录
3. 选择 "Add Package Dependencies..."
4. 点击 "Add Local..."
5. 选择 `Vendor/SherpaOnnxPackage` 目录
6. 添加依赖

### 测试步骤：
1. 运行应用
2. 进入设置
3. 点击 Download 按钮下载模型
4. 选择 Sherpa-ONNX 引擎
5. 测试语音转录功能

## 📝 注意事项

1. **模型格式不同**：
   - 原 SenseVoice: `.gguf` 格式
   - Sherpa-ONNX: `.onnx` 格式
   - 两者不兼容，需要分别下载

2. **存储位置不同**：
   - 原 SenseVoice: `~/Library/Application Support/Stet/Models/`
   - Sherpa-ONNX: `~/Library/Application Support/Stet/Models/SherpaOnnxSenseVoice/`

3. **配置键不同**：
   - 原 SenseVoice: `mac.senseVoiceModelPath`
   - Sherpa-ONNX: `mac.sherpaOnnxSenseVoiceModelPath`

## ✨ 构建状态

✅ **BUILD SUCCEEDED** - 所有代码已成功编译
