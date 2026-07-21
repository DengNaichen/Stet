# Stet 安全规则

本文件记录当前仓库实际存在的安全配置面、风险边界和硬约束。它回答"在这个项目里，哪些地方改了会影响安全"和"什么安全规则不能违反"。

## 安全配置面

### 认证、授权与访问控制

`DictationSettingsStore` 经 `DictationSecretStore` 读写 provider API key，默认使用 `KeychainSecretStore`；其 `UserDefaultsStore` 不保存 API key [SECURITY-0001]。

### 数据、文件写入与输出

文本注入只有在具备 Accessibility 或 post-event access 时才能模拟输入。自动缺失权限请求在每个 `SystemTextInjectionService` 实例中至多一次；手动 `requestAccess()` 可重复触发 [SECURITY-0002]。

### 调度、外部输入与执行边界

可选 MCP HTTP server 默认监听 `127.0.0.1:49321/mcp`，且仅在 `mcpServerEnabled` preference 为真时启动 [SECURITY-0003]。

### 外部系统与依赖

本轮未核实到需要额外记录的外部系统安全配置面。

## 安全验证与人工评审

自动化安全检查（secret scan、dependency scan、SAST、安全相关测试、pre-commit、CI security gate 等）的状态、命令和 runner 以 [VALIDATION.md](../VALIDATION.md) 为准，本文件不复制。本节只记录安全视角的补充：

- 如发现安全风险缺少对应自动化检查，在 [VALIDATION.md](../VALIDATION.md) 补登记，不要在本文件维护第二份检查清单。

## 硬约束

以下规则必须始终成立，违反即为错误：

Provider API key 必须通过 Keychain-backed secret store 保存，不得保存到 `UserDefaults` [SECURITY-0004]。

可选 MCP HTTP server 必须只绑定 loopback interface [SECURITY-0005]。
