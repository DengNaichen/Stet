# Stet 贡献者指南

这是 Stet 的 agent 启动入口；完整模块地图见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，产品背景见 [README.md](README.md)。

## 项目事实

Stet 是由根 Xcode project 和本地 Swift Package 构建的 macOS 菜单栏听写应用 [AGENT-0001]。

## 路由

- 修改模块边界、依赖或运行链路前，读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。
- 本地启动、配置与缓存排障见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。
- 编码、可靠性、安全和产品判断分别见 [docs/rules/](docs/rules/) 的对应文件。
- 验证 scope、CI 绑定和结果报告见 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 行动 gate

修改 provider credential storage 或 MCP HTTP listener 前，必须先读 [docs/rules/SECURITY.md](docs/rules/SECURITY.md) 并核对相关源码 [AGENT-0003]。

## 验证入口

已配置的本地验证入口是 `make lint`、`make ci-build` 和 `make test`；适用范围及结果语义以 [docs/VALIDATION.md](docs/VALIDATION.md) 为准 [AGENT-0002]。

## 漂移处理

如果本入口与 owner 文档或真实仓库状态冲突，先核对相关源码、配置或构建清单，再同步修复对应 context 文档。
