# docs 索引

本目录是 Stet monorepo 的 durable context 入口：架构地图、实践规则、验证规范、软件需求与研究记录。研究与实验记录集中在 [research/](research)，按历史证据阅读，不自动作为当前行为或已采纳决策。

## 入口

- [ARCHITECTURE.md](ARCHITECTURE.md)：跨端地图、模块边界与放置规则。
- [VALIDATION.md](VALIDATION.md)：验证命令、适用范围与报告口径。
- [GLOSSARY.md](GLOSSARY.md)：Stet 专有术语。
- [rules/index.md](rules/index.md)：跨端 coding、product、security 判断规则。
- [specs/index.md](specs/index.md)：完整软件需求目录。
- [research/INDEX.md](research/INDEX.md)：研究记录的证据范围、已知局限和后续关系。
- [reference/README.md](../reference/README.md)：Apple 平台参考库（按需读）。

## 端内地图

端内细节见 [ARCHITECTURE.md](ARCHITECTURE.md) 仓库地图；各端 agent 入口如下。

- macOS：仓库根目录 — 入口 [`../AGENTS.md`](../AGENTS.md)
- iOS：[StetMobile/](../StetMobile) — 入口 [`StetMobile/AGENTS.md`](../StetMobile/AGENTS.md)
- 共享包：[Packages/](../Packages)（StetEngine 等；iOS 通过相对路径引用）

## 其他文档

- macOS 发布工作流：[release skill](../.agents/skills/release/SKILL.md)
