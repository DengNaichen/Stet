# Security Rules

本文件记录当前仓库实际存在的安全配置面、风险边界和硬约束。它回答"在这个项目里，哪些地方改了会影响安全"和"什么安全规则不能违反"。

<!-- harnesskit:todo-checklist:start -->
补全本文件前请确认：
- 从真实源码、配置、脚本、部署方式、依赖清单和测试入口中提炼安全 surface。
- 不要虚构 security policy、漏洞披露渠道、支持版本、响应 SLA、secret scan、dependency scan 或 CI security gate。
- 自动化安全检查的状态归 [VALIDATION.md](../VALIDATION.md)，本文件只链接引用、不复制 runner/命令；只记人工评审的安全项。
- 只写已确认内容；当前没有可记录事实时可保留对应小节为空。
<!-- harnesskit:todo-checklist:end -->

## 安全配置面

### 认证、授权与访问控制

### 数据、文件写入与输出

### 调度、外部输入与执行边界

### 外部系统与依赖

## 安全验证与人工评审

自动化安全检查（secret scan、dependency scan、SAST、安全相关测试、pre-commit、CI security gate 等）的状态、命令和 runner 以 [VALIDATION.md](../VALIDATION.md) 为准，本文件不复制。本节只记录安全视角的补充：

- 如发现安全风险缺少对应自动化检查，在 [VALIDATION.md](../VALIDATION.md) 补登记，不要在本文件维护第二份检查清单。

## 硬约束

以下规则必须始终成立，违反即为错误：
