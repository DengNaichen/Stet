# Reliability Rules

本文件记录 Stet 当前可证明的 failure、recovery、cleanup 与兼容性边界。验证入口见 [VALIDATION.md](../VALIDATION.md)。

## 高风险改动区域

- `ConfigurableSpeechService` 的成功 stop 与 cancel 会清空 active state、停止 prewarm/forwarding 并释放本地 ASR contexts，processed audio cleanup URLs 也会 best-effort 删除；rewrite failure 回退 raw transcript。`stopRecording()`/post-processing 抛错以及 start/activate failure 并不覆盖同样的 context/capture cleanup，转写或最终空文本会失败终止。[RELIABILITY-0001]
- `MacDictationCaptureCoordinator` 为 transient auto-paste 保存完整 pasteboard snapshot，仅当当前 pasteboard 仍匹配临时内容时延迟恢复；普通注入失败会恢复并保留非 transient clipboard fallback，但部分 verification-unavailable/failed target profile 会按 optimistic completed 处理。[RELIABILITY-0002]
- Alternative local ASR 只在 pipeline factory 构造所选 service 抛错时回退 Local Whisper；异步 prewarm/prepare、音频准备或实际 transcription failure 不触发 factory fallback，Local Whisper fallback 也可能失败。[RELIABILITY-0003]
- History/status、stats 与 legacy dictionary migration 是持久状态兼容面。History 的 `.processing` insert 与 final update 都由未等待的 detached tasks 执行，实际落盘顺序无保证；legacy migration version key 表示只尝试一次，即使读取失败或无内容也会清理旧 defaults 并记版本。[RELIABILITY-0004]
- Release build 会删除当前 tag 工作目录中的已知生成子路径，随后归档、重签名、生成 DMG、公证并生成 appcast；tag/version/build 校验发生在归档和重签名之后。发布 workflow 再以 `--clobber` 创建/更新 GitHub Release assets，具有外部副作用。[RELIABILITY-0005]

## 验证覆盖

当前 checks、CI 绑定与已知覆盖缺口统一见 [VALIDATION.md](../VALIDATION.md)。
