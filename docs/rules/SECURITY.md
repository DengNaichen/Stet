# Security Rules

本文件记录 Stet 当前实际存在的 trust boundary、敏感数据路径与已知缺口。自动化检查状态见 [VALIDATION.md](../VALIDATION.md)。

## 安全配置面

### 认证、授权与访问控制

- 新建 provider API key 以 bundle identifier 为 Keychain service、provider-specific account 保存为 synchronizable generic-password item；查询匹配 synchronizable-any，更新既有非同步 item 不会强制迁移。普通偏好保存在 UserDefaults。[SECURITY-0001]
- 可选 MCP server 仅绑定 `127.0.0.1:49321/mcp` 且没有 authentication。任意本机 client 都可要求 Stet 尝试读取其进程权限范围内满足 absolute/existing/readable/regular 检查的路径；没有目录或扩展名 allowlist，并会返回 raw/final transcript。[SECURITY-0003]

### 数据、文件写入与输出

- Text injection 检查/请求 Accessibility 与 CGEvent post access，读取 focused AX element/selected text，并通过 transient pasteboard 与模拟 Cmd-C/Cmd-V 跨 app 读写；缺权限或失败时会请求授权并保留 clipboard fallback。[SECURITY-0002]
- 普通 dictation 的 rewrite success 或 fallback failure 会把完整 raw/final transcript 以 OSLog `.public` 记录，失败还含 error；该路径也覆盖本地 Apple Intelligence rewrite，但不覆盖 MCP rewrite。`dictationTranscriptTracingEnabled` 当前只有 key 定义，没有 gate 调用。[SECURITY-0006]

### 调度、外部输入与执行边界

- SenseVoice 与 FunASR model downloads 使用硬编码 HTTPS URLs；FunASR 只校验 2xx，SenseVoice 另校验非空。两者都不校验 digest/signature，已有目标文件也仅按存在性复用。[SECURITY-0004]

### 外部系统与依赖

- 普通 cloud rewrite 会把 raw transcript、language、preferred spellings、当前 app name 和由 app audience 选择的 system prompt 发往 provider；MCP rewrite 固定 `.ai` audience 且不传 app name，转写推理仍在本地。底层 OpenAI-compatible configuration 接受 custom base URL，只要求 scheme 与 host、并不强制 HTTPS；当前产品设置使用硬编码 provider URLs。[SECURITY-0005]
