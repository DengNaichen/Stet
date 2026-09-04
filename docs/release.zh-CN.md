# 发布指南

这份文档记录了 Stet 当前已经跑通的发布流程。

## 总览

Stet 在**仓库根目录**（`.github/workflows/`）使用三条 GitHub Actions workflow。GitHub 只会执行根目录 workflow；完整列表见 [`.github/README.md`](../.github/README.md)。

- `Monorepo CI`
  - 文件：`.github/workflows/monorepo-ci.yml`
  - 触发：PR，以及对 `main`、`migration/**` 的 push
  - 用途：lint、build、test（`make lint`、`make ci-build`、`make test`）

- `macOS Release Candidate`
  - 文件：`.github/workflows/macos-release-candidate.yml`
  - 触发：`workflow_dispatch`
  - environment：`release-candidate`
  - 工作目录：仓库根目录（发布脚本和 Xcode 工程位于根目录）
  - 用途：生成签名并公证过的候选发布产物，但不创建 GitHub Release

- `macOS Release`
  - 文件：`.github/workflows/macos-release.yml`
  - 触发：`v*` tag 的 `push`，以及用于安全手测的 `workflow_dispatch`
  - environment：`production`
  - 工作目录：仓库根目录
  - 用途：在 GitHub Actions 中构建、签名、公证、生成 Sparkle appcast、发布 GitHub Release，并上传发布产物

## 日常发布流程

标准发布只走 GitHub Actions，不在本机手工生成或上传正式产物。`v0.2.4` 是 SenseVoice 介入前最后一版已验证流程；新的标准是在保留这条流程的基础上，让构建脚本在 Xcode 复制二进制 framework 前规范化 SenseVoice/Sherpa-ONNX artifact，并在 release 脚本中只重签明确列出的嵌入组件。

日常开发：

1. 开分支并提 PR。
2. 等 `Monorepo CI` 通过。
3. 合并到 `main`。

发布前验证：

1. 需要时，在 GitHub Actions 手动运行 `macOS Release Candidate`。
2. 使用测试标签，例如 `v0.0.10-rc1`。
   运行前先更新 `Stet.xcodeproj/project.pbxproj`，让 `MARKETING_VERSION` 对应发布版本，让 `CURRENT_PROJECT_VERSION` 对应由语义化版本推导出的单调递增 Sparkle build number。
   规则是 `CURRENT_PROJECT_VERSION = major * 1,000,000 + minor * 1,000 + patch`。
   比如 `v0.0.12-rc1` 需要 `MARKETING_VERSION = 0.0.12`、`CURRENT_PROJECT_VERSION = 12`；`v0.1.1-rc1` 需要 `MARKETING_VERSION = 0.1.1`、`CURRENT_PROJECT_VERSION = 1001`。
3. 确认签名、公证、DMG 生成、artifact 上传都成功。

正式发布：

1. 更新项目里的版本号和 build number。
   改 `Stet.xcodeproj/project.pbxproj`，不要直接改 `Info.plist`。`Info.plist` 只是引用项目里的 `$(MARKETING_VERSION)` 和 `$(CURRENT_PROJECT_VERSION)`。
   `CURRENT_PROJECT_VERSION` 必须跨版本持续递增。Sparkle 比较的是 `CFBundleVersion`，如果新 minor 版本把 build number 又从小值开始计，会让新版本在更新判断里看起来比旧 patch 版本更老。
2. 确认 `main` 上已经是要发布的 commit。
3. 推送正式 tag，例如 `v0.0.10`。
4. GitHub Actions 自动运行 `macOS Release`。
5. workflow 会在 GitHub Actions 中生成 DMG 和 `appcast.xml` 产物。
6. workflow 会直接发布 GitHub Release 并上传这些产物。

## GitHub Environments

### `release-candidate`

Secrets：

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`
- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`

Variables：

- `DEVELOPER_ID_APPLICATION`
- `ARCHIVE_PROVISIONING_PROFILE_SPECIFIER`
  - 只有当发布 archive 需要 distribution provisioning profile 时才需要

### `production`

Secrets：

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`
- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `SPARKLE_PRIVATE_KEY_BASE64`

Variables：

- `DEVELOPER_ID_APPLICATION`
- `ARCHIVE_PROVISIONING_PROFILE_SPECIFIER`
  - 如有需要再配置
- `SPARKLE_APPCAST_URL`
- `SPARKLE_PUBLIC_ED_KEY`

## Sparkle 最重要的注意点

最容易填错的值是：

- `SPARKLE_PRIVATE_KEY_BASE64`

这个 secret 不能直接从 Keychain Access 里手工复制“密码”来填。

正确的值必须来自 Sparkle 官方 `generate_keys -x` 导出的文件，或者等价的标准 Sparkle 导出文件。

正确做法：

1. 先构建 Sparkle 的 `generate_keys` 工具。
2. 导出密钥：

```bash
generate_keys -x /tmp/private-key.txt
```

3. 把 `/tmp/private-key.txt` 的文件内容直接写入 GitHub `production` environment 的 `SPARKLE_PRIVATE_KEY_BASE64`。

注意：

- 这个导出文件本身已经是 Sparkle 期望的 base64 文本。
- 不要在写入 GitHub 之前再做一次解码。
- 不要用 Keychain Access 里手工复制出来的原始文本替代它。

## 当前 Workflow 的行为

### Release candidate

`macOS Release Candidate` 会做这些事：

- 把 Developer ID 证书导入临时 keychain
- 存储 `notarytool` 凭据
- 运行 `scripts/release-macos-github.sh`
- 把 `dist/github-release/<release_tag>/` 上传为 artifact

这里刻意关闭了 Sparkle appcast 生成。

### Production release

`macOS Release` 额外会做这些事：

- 根据正式 tag 或手动测试模式解析 release 元数据
- 把 Sparkle secret 写到 runner 上的临时文件
- 按 `Package.resolved` 中的 Sparkle 版本下载 Sparkle 源码
- 在 CI 里构建 `generate_appcast`
- 运行 `scripts/release-macos-github.sh`
- 运行 `scripts/publish-github-release.sh`
- 把 `dist/github-release/<release_tag>/` 上传为 artifact

手动 `workflow_dispatch` 测试模式是安全的，因为它会设置：

- draft release = `true`
- prerelease = `true`
- latest = `false`
- verify tag = `false`

## 已知说明

- 在 CI 里，`spctl` 对 DMG 有时会返回 `source=Insufficient Context`。当前流程以 `stapler validate` 成功为更可靠的信号。
- 现在这条正式发布 workflow 会在 CI 中编译 Sparkle 的 `generate_appcast`，因为 Sparkle 的 SwiftPM 包只提供框架二进制，不提供 CLI 工具。
- 手动 release 测试时，artifact 上传路径使用你输入的 `release_tag`，不是 `github.ref_name`。
- SenseVoice/Sherpa-ONNX 的 XCFramework 不能改变发布入口。标准入口仍然是 `macOS Release Candidate` 和 `macOS Release`；不要为了二进制 framework 额外引入本地发布分支、手工 DMG、手工 appcast 或绕过 `scripts/release-macos-github.sh` 的流程。
- `sherpa_onnx.framework` 当前来自 SwiftPM remote binary target，实际内容是静态库包装的 framework。Xcode 复制前由 `scripts/normalize-binary-frameworks.sh` 修正 framework 结构和签名；最终发布包再由 `scripts/release-macos-github.sh` 统一重签 Sparkle、StetVisuals、sherpa_onnx 和主 app。
