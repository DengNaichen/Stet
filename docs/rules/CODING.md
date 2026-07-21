# Stet 编码规则

本文件记录从当前仓库中提取的编码约定和硬约束。它回答"在这个项目里，代码应该长什么样"，不重复通用工程建议。

## 代码组织

目录布局、模块职责和"某功能属于哪个模块"见 [ARCHITECTURE.md](../ARCHITECTURE.md)（放置规则的唯一来源）。本节只补充模块**内部**的编码层面组织：

格式化和 lint 配置位于仓库根的 `.swift-format` 与 `.swiftlint.yml`。

## 命名和风格

Swift Format 使用 4 个空格缩进、120 字符行长、最多一个连续空行，并要求多元素集合保留尾随逗号 [CODING-0001]。

SwiftLint 仅启用 `empty_count`、`force_cast` 和 `force_try` [CODING-0002]。

## 测试约定

`StetEngine` 的 package 测试分别放在 `Tests/StetCoreTests`、`Tests/StetRewriteTests` 和 `Tests/StetAITests` [CODING-0004]。

## 注释和文档

未核实到除格式配置外需要额外追踪的注释或 API 文档约定。

## 硬约束

以下规则必须始终成立，违反即为错误：

`.swiftlint.yml` 当前只包含 `StetMac`、`StetTests`、`StetUITests` 和 `StetVisuals`；它没有包含 `StetMacTests` 或 `Packages/StetEngine` [CODING-0003]。

仓库的 SwiftLint scope 必须包含 `StetMacTests` 和 `Packages/StetEngine` [CODING-0005]。
