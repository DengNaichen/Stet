# Coding Rules

本文件记录 Stet 当前可由源码与配置证明的编码形状；目录职责和依赖方向见 [ARCHITECTURE.md](../ARCHITECTURE.md)。

## 代码组织

- UI/presentation types 与相关 tests 普遍使用 `@MainActor`；后台可变服务按真实边界使用 actor、Sendable contract 或 lock/serial queue，tests 采用对应的隔离形状。这是主导实现模式，不是无例外硬规则。[CODING-0004]

## 命名和风格

- `.swift-format` 配置 4 空格、120 列、最多一个连续空行和多元素 collection trailing comma；`make format` 与 `make format-lint` 只覆盖 `StetMac`、`StetMacTests`、`StetMacUITests`、`StetVisuals`，不覆盖 `Packages/StetEngine`。[CODING-0001]
- `.swiftlint.yml` 只启用 `empty_count`、`force_cast`、`force_try`，strict/no-cache 来自 Makefile 调用。其 include 仍写为不存在的 `StetTests`/`StetUITests` 路径，因此没有覆盖实际 `StetMacTests`/`StetMacUITests`。[CODING-0002]

## 测试约定

- `StetMacTests` 与 package tests 主要使用 Swift Testing；`StetMacUITests` 使用 XCTest。App tests 按 App/Core/Features/StetVisuals 等实现面组织并复用 `Support/TestSupport.swift`，package tests 位于 `Packages/StetEngine/Tests/<module>Tests`；是否使用 `@testable import` 以各 target 当前边界为准。[CODING-0003]

## 注释和文档

仓库没有从代表性源码中形成额外的项目专属注释格式；以当前上下文附近的写法为准。
