# Stet 本地开发

本文件记录 Stet 的本地启动、配置与排障；验证命令见 [VALIDATION.md](VALIDATION.md)。

## 环境前提

- README 声明 macOS 26.0+、Xcode 26 或兼容版本，并要求麦克风与 Accessibility/input control 权限。[DEVELOPMENT-0001]
- Xcode project 当前把 app 与 project 的 `MACOSX_DEPLOYMENT_TARGET` 设为 15.0；该值进入产物的 `LSMinimumSystemVersion`，与 README 声明的开发/产品要求不是同一概念。[DEVELOPMENT-0006]

## 启动与停止

- 用 Xcode 打开 `Stet.xcodeproj`、解析 Swift Package dependencies 并运行 `Stet` scheme；`make build` 只构建 Debug app，不负责启动或停止。[DEVELOPMENT-0002]

## 本地配置

- 应用配置通过 onboarding 与 Settings 完成；普通 dictation 偏好保存在 `UserDefaults`，provider API keys 由 `KeychainSecretStore` 保存。根 `.env` 与 `.env.release` 只供专项 smoke/release scripts 使用，不是应用启动配置入口。[DEVELOPMENT-0003]
- Debug 与 Release 分别使用 `NaichengDeng.Stet.Debug` 和 `NaichengDeng.Stet`；本地 build 不应与已安装 app 共享身份，以免混淆 TCC、Launch Services 与 OAuth callback 状态。[DEVELOPMENT-0004]

## 排障

- `make doctor` 报告根磁盘、项目缓存、匹配的 DerivedData、共享 Xcode/SwiftPM caches、Archives 与 simulator runtimes。`make clean-derived-data` 会先拒绝正在使用的 build tools，再只删除 allowlist 中可重建的项目 caches 和匹配 Stet/StetMobile workspace 的 DerivedData；它保留 archives、签名数据、models、frameworks 与 simulator runtimes。[DEVELOPMENT-0005]
- 麦克风授权异常或 onboarding 未识别授权时，先按 README 核对 Debug entitlement 与一致的 `AVAudioApplication` request/status API family。
