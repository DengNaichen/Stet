# Stet 本地开发

本文件只记录本地开发环境的启动、配置和排障。模块与路径职责见 [ARCHITECTURE.md](ARCHITECTURE.md)；checks、runner 和 receipt 语义见 [VALIDATION.md](VALIDATION.md)，本文件只链接引用，不复述。

## 环境前提

开发和运行 Stet 需要 macOS 26.0 或更高版本、Xcode 26 或兼容版本、麦克风权限，以及用于向其他应用写入文本的辅助功能/输入控制权限 [DEVELOPMENT-0001]。

## 启动与停止

在 Xcode 打开 `Stet.xcodeproj`，等待 Swift Package 依赖解析后运行 `Stet` scheme；也可以在仓库根执行 `make build` 构建 Debug app [DEVELOPMENT-0002]。

## 本地配置

仓库没有可提交的本地环境配置示例；首次启动的账户、权限和听写设置由应用内引导完成。

## 排障

| 症状 | 核对 |
| --- | --- |
| 需要确认 Stet 与 Xcode 缓存占用 | 运行 `make doctor` 查看 Stet、Xcode 和 SwiftPM 相关存储 [DEVELOPMENT-0003]。 |
| 需要释放可重建的本地构建缓存 | 先退出 Xcode 和其他 Swift 构建工具，再运行 `make clean-derived-data`；脚本只删除经 allowlist 和路径检查的目标，保留归档、签名数据、模型、下载的 framework 和 simulator runtime [DEVELOPMENT-0004]。 |
