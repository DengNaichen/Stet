# macOS 会议录音实现与验证

工作项：[GitHub #93](https://github.com/DengNaichen/Stet/issues/93)。本次以可播放的录音文件为成功标准，转写结果单独判断。实现和自动验证已完成；下述实机验收尚未执行，issue 保持打开。

## 已实现

- `MacMeetingAudioRecorder` 管理独立的会议采集生命周期。麦克风使用所选设备 UID 创建 `AVCaptureSession`；系统声音使用全局 Core Audio process tap，不依赖飞书或微信启动时机。
- 系统音频的私有 aggregate device 只包含 tap，避免把双工耳机的输入声道误当作系统输出。默认输出或采样率改变时重建系统采集，麦克风继续使用原选定设备。
- `MeetingAudioRecordingSink` 复制回调中的借用 buffer，再交给串行写盘队列；待写数据上限为 8 MiB。停止时先结束并排空硬件回调，再排空写盘队列。
- `MeetingAudioFileSession` 按 host-clock 时间戳对齐两路音频，处理采样率变化、静音间隔、重叠与重采样尾部，持续写入文件。录制过程中不在内存累计全场音频。
- 启动、采集、写盘、输入中断、麦克风持续无回调及休眠错误进入可见失败状态，尽量完成已有音频文件。系统静音或暂时没有系统回调本身不是失败。
- 启动期间显示准备状态并防止重复开启。录音保存后才进入原有处理流程；处理失败保留 `recordingStatus: recorded`，界面明确说明录音已保存。

### 每次录音的文件

位置：`~/Library/Application Support/Stet/Meetings/<本地开始时间>/`。同秒重新开始使用不同目录，避免覆盖上一次录音。

| 文件 | 内容 |
|---|---|
| `microphone.wav` | 所选麦克风轨，16 kHz、PCM16、单声道 |
| `system.wav` | 系统输出轨，与麦克风轨对齐；无系统播放时为静音 |
| `audio.wav` | 两轨各乘 0.5 后混合，兼容现有会议入口 |
| `capture.json` | 采集状态、两轨收到的帧数、时长、错误及不连续点 |
| `session.json` | 既有会议元数据，新增独立的 `recordingStatus` |

转写仍可在录音结束后从 `audio.wav` 加载全场样本；本次没有改变转写模型或处理策略。有界内存保证针对采集和混音阶段。

## 自动验证

环境：本机 `/Applications/Xcode.app`，Xcode 27.0（27A266a），Apple Silicon，macOS 27 SDK。最初构建缺失 Metal Toolchain，使用 `xcodebuild -downloadComponent MetalToolchain` 补齐后继续验证。

| 检查 | 实际结果 |
|---|---|
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make ci-build` | **passed**，退出码 0；未签名 Debug 应用构建成功 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` | **passed**，退出码 0；623 项测试、92 个 suite 全部通过，测试执行约 36.2 秒；包含会议相关 24 项测试 |
| `make lint` | **passed**，退出码 0 |
| `git diff --check` | **passed**，退出码 0 |
| `python3 -m unittest discover -s scripts/tests -p 'test_*.py'` | **passed**，17 项 CI helper 测试 |
| `python3 scripts/validate-app-compatibility.py`、`python3 scripts/validate-rewrite-models.py`、`scripts/validate-agent-entrypoints` | **passed**，退出码均为 0 |

定向测试源码：

- [MeetingAudioFileSessionTests](../StetMacTests/Core/Audio/Capture/MeetingAudioFileSessionTests.swift)：不同采样率与回调次序、系统播放晚于/早于录音、系统静音、格式变化和间隔、借用 buffer 复用、停止排空、缺失麦克风、写入错误、缓冲超限，以及 20 分钟合成时间轴的末段双源声音。
- [MacMeetingRecordingRuntimeTests](../StetMacTests/Core/Speech/MacMeetingRecordingRuntimeTests.swift)：保存先于处理完成、采集失败保留录音、处理失败保留录音成功状态、重复启动、启动失败清理、会议元数据。
- [MeetingRecordingStoreTests](../StetMacTests/Core/Speech/MeetingRecordingStoreTests.swift)：目录与同秒重启保护。
- [MacMeetingRecordingNotificationTests](../StetMacTests/Shared/Utilities/MacMeetingRecordingNotificationTests.swift)：录音保存与处理通知。

复跑完整测试使用 CI 的标准入口：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test
```

最终日志在 `/tmp/stet-full-test-final.log`、`/tmp/stet-ci-lint.log` 和 `/tmp/stet-ci-helper-tests.log`；日志不进入 Git。这里报告的是创建 PR 前的本地执行结果；远端 CI 状态以 PR 的 Checks 为准。

### 完整测试阻塞已修复

最初 `make test` 在测试源码编译阶段失败。最小跨模块编译用例复现了同一错误：应用的 `MainActor` 默认隔离被用于后台服务协议，导致测试中的独立 actor 无法遵循它们。已将 `AudioCaptureService`、`AudioLevelSource`、`AudioPostProcessing`、`AudioFileTranscriptionService`、`SpeechService`、`FunASRNanoEngine` 明确声明为 `nonisolated`，由各实现管理自身隔离；修复后该用例与完整测试均通过。

解除编译阻塞后，全量测试发现一个 DeepSeek 测试漏传 `.off` 思考档位：该测试断言关闭思考，却沿用新增可配置档位之前的 fixture。已让测试显式传入所验证的 `.off`，与同次模型配置变更中已更新的共享包测试一致。生产模型配置和请求实现未修改，原有断言保留。

此前仅通过临时 runner 执行会议测试不足以证明 CI 可通过；现在完整 `StetTests` 目标已编译并执行成功，没有排除失败测试或降低 CI 检查要求。

## 待实机验收

以下均为 **not_run**。使用签名后的 Stet，并通过 macOS 公开提示授予麦克风和系统音频录制权限。每项先停止录音，再分别试听两条源轨与混音；不要以转写是否产生文字判断录音是否成功。

| 场景 | 验收内容 |
|---|---|
| 先录音，后开启飞书通话 | 通话前麦克风有声；对方开始说话后系统轨有声；此前音频保留 |
| 先开启飞书通话，再录音 | 两方声音从录音启动后出现 |
| 微信通话，戴耳机 | 对方声音直接出现在系统轨；不依赖麦克风拾取耳机漏音 |
| 无通话软件，戴耳机，选择内置麦克风 | 麦克风轨包含本地讲话；系统轨可全静音，录音仍成功 |
| 通话开始/结束、切换默认输出或蓝牙模式 | 原麦克风不被耳机输入替换；音轨保留时间位置；无法恢复时显示失败并保存已录部分 |
| 连续真实录制 20–30 分钟 | 起止播放同步标记，核对两路时长、末段内容、偏移及进程内存；合成测试不能代替此项 |
| 拒绝权限、断开输入、休眠、写盘失败 | 不静默继续成功；已有源文件可访问 |

尚未验证原始三段失败录音的具体故障阶段，也未在签名应用中验证 Core Audio 授权拒绝/撤销行为。公开 API 返回的错误会被上报；纯静音与权限导致的静音不能仅凭振幅判断。扬声器回声消除、独立应用选择和转写质量不属于本次范围。
