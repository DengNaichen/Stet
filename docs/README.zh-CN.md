# Stet

Stet 是一款 macOS 菜单栏语音听写应用。

## 简介

Stet 会录音、转写，并且可以把结果直接粘贴回当前应用，或者替换掉已选文本。它常驻在菜单栏，通过全局快捷键启动，目标是尽量少改动地保留原始表达。

## 特性

- 菜单栏常驻运行，不占用 Dock
- 全局快捷键开始和结束听写
- 支持麦克风测试和输入设备选择
- 支持 OpenAI 和 Groq 作为转写提供方
- 支持 `Automatic`、`Stet account`、`Your own key` 三种 AI 执行模式
- 支持中文、英文以及中英混合听写偏好
- 支持个人词典
- 支持 Sparkle 自动更新

## 系统要求

- macOS 26.0 或更高版本
- Xcode 26 或兼容版本
- 麦克风权限
- 辅助功能 / 输入控制权限，用于把文本写回当前应用

## 快速开始

在 Xcode 中打开 `apps/mac/Stet.xcodeproj`，让依赖自动解析后运行 `Stet` scheme。

也可以直接从仓库根目录构建：

```bash
npm run mac:build
```

或者直接使用 `xcodebuild`：

```bash
xcodebuild -project apps/mac/Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' build
```

## 配置说明

首次启动时，Stet 会引导你完成权限、听写设置，以及 Stet 账号或自己的 API Key。设置里也可以调整音频输入、语言偏好、外观、更新和个人词典。

## 测试

运行 macOS 测试：

```bash
xcodebuild -project apps/mac/Stet.xcodeproj -scheme Stet -destination 'platform=macOS' test
```

## 发布

生成本地 Release 应用：

```bash
./scripts/build-macos-release.sh
```

生成适合发布的签名和公证产物：

```bash
./scripts/release-macos-github.sh
./scripts/publish-github-release.sh
```

发布产物会写入 `dist/github-release/<tag>/`。

## 许可证

Apache-2.0
