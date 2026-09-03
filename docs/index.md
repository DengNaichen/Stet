# docs 索引

本目录是 Stet monorepo 的 durable context 入口：架构地图、实践规则、验证规范、软件需求与 Technical Plan。临时审计、草案和未定决策不放在这里。

## 入口

- [HARNESS.md](HARNESS.md)：Harness 分层、workflow 与 agent 启动路径。
- [ARCHITECTURE.md](ARCHITECTURE.md)：跨端地图、模块边界与放置规则。
- [VALIDATION.md](VALIDATION.md)：验证命令、适用范围与报告口径。
- [GLOSSARY.md](GLOSSARY.md)：Stet 专有术语。
- [rules/index.md](rules/index.md)：跨端 coding、product、security 判断规则。
- [specs/index.md](specs/index.md)：完整软件需求目录。
- [exec-plans/README.md](exec-plans/README.md)：Technical Plan 的 active/completed 生命周期。
- [archive/README.md](archive/README.md)：已退役、gitignored 的本地-only 资产说明。
- [reference/README.md](../reference/README.md)：Apple 平台参考库（按需读）。

## 端内地图

端内细节见 [ARCHITECTURE.md](ARCHITECTURE.md) 仓库地图；各端 agent 入口如下。

- macOS：`Public/Stet/` — 入口 [`Public/Stet/AGENTS.md`](../Public/Stet/AGENTS.md)
- iOS：`Private/StetMobile/` — 入口 [`Private/StetMobile/AGENTS.md`](../Private/StetMobile/AGENTS.md)
- 共享包：`Public/Stet/Packages/`（StetEngine 等；iOS 通过相对路径引用）

## 其他文档

- macOS release 流程：[`Public/Stet/docs/release.md`](../Public/Stet/docs/release.md)
