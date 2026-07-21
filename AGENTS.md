# Stet 贡献者指南

本文件是 agent 的最小启动入口，只记录仓库事实和文档路由。

## 项目事实

- Stet 是单一项目的原生 macOS 菜单栏听写应用；主要工程入口是 `Stet.xcodeproj`，实现集中在 `StetMac/`、`StetVisuals/` 与本地 `Packages/StetEngine/`。[AGENT-0001]

## 工作路由

- 路径职责、模块边界、依赖和运行链路从 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 开始核对，再回到相关源码或构建清单。[AGENT-0002]
- 本地环境、Xcode 启动运行、Make 构建、配置与排障入口是 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。[AGENT-0003]
- 可执行验证、自动化绑定、已知覆盖差异与结果报告统一由 [docs/VALIDATION.md](docs/VALIDATION.md) 说明。[AGENT-0004]
- 编码、可靠性、安全与产品判断分别路由到 [CODING.md](docs/rules/CODING.md)、[RELIABILITY.md](docs/rules/RELIABILITY.md)、[SECURITY.md](docs/rules/SECURITY.md) 与 [PRODUCT_SENSE.md](docs/rules/PRODUCT_SENSE.md)，不在这里复制正文。[AGENT-0005]
- 产品定位与使用背景从 [README.md](README.md) 和 [PRODUCT_SENSE.md](docs/rules/PRODUCT_SENSE.md) 获取；当前仓库不能证明的目标用户等内容保持 `unknown`。[AGENT-0006]
