---
name: release
description: 发布 Stet macOS 正式版本或候选版本，处理版本号、发布 tag、GitHub Actions 跟踪及签名配置排查。用户要求发布、升级版本或运行 release workflow 时使用。
---

# Stet macOS Release

正式产物由 GitHub Actions 构建、签名、公证和发布。命令从仓库根执行。
本 skill 不覆盖 iOS 发布。只准备版本或修改发布文档时，不触发 tag push 或 workflow。

## 执行前

- 读取 [workflow 地图](../../../.github/WORKFLOWS.md) 和本次使用的 workflow：
  [正式发布](../../../.github/workflows/macos-release.yml) 或
  [候选发布](../../../.github/workflows/macos-release-candidate.yml)。输入、环境和 secrets 以配置为准。
- 明确版本 `X.Y.Z`、目标 commit 和正式发布 / 候选发布范围；版本不明确时询问。
- 普通代码、版本准备和 PR 操作遵循 [git-workflow](../git-workflow/SKILL.md)。
  正式发布使用下述现有脚本，它要求从干净的主 checkout 执行，并直接提交、推送 main 和 tag。
- 确认目标 PR 已合并、目标 commit 的 CI 通过。检查工作区、远端仓库、main 和已有 tag；网络查询失败不能视为 tag 不存在。

## 正式发布

1. 在主 checkout 刷新 `origin/main`，确认当前为干净的 `main`，仅以 fast-forward 同步。
   不从任务 worktree 切换或强占 main，不搬移其他任务的未提交改动。
2. 检查本地 `refs/tags/vX.Y.Z` 和远端同名 tag。已存在时核对已有发布状态，不覆盖 tag。
3. 检查 `Stet.xcodeproj/project.pbxproj`：版本写入 `MARKETING_VERSION`，
   build 为 `major * 1_000_000 + minor * 1_000 + patch`，必须高于已发布 build。
   `Info.plist` 引用这些设置，不直接修改它。版本已相同时先核对状态：bump 脚本会直接退出，不会补发 tag。
4. 在用户已授权正式发布后运行 `./scripts/bump-version.sh X.Y.Z`。
   先读 [脚本](../../../scripts/bump-version.sh) 确认行为；它会修改项目、提交、推送 main，再创建并推送 tag。
5. 核对本地 `HEAD`、`refs/tags/vX.Y.Z^{commit}` 与远端 main、tag 指向本次版本提交。
   标签不是 remote-tracking branch，不使用 `origin/vX.Y.Z` 解析标签。
6. 找到该 tag 和 commit 对应的 `macOS Release` run，跟踪至完成。
   核验签名、公证、DMG、Sparkle appcast、GitHub Release 及上传产物；报告版本、commit、run 和 Release 链接。

若推送或 workflow 失败，检查远端 refs 和 run，报告已完成与失败的阶段；不要盲目重跑 bump、重写 tag 或改为本机发布。

## 候选与手动测试

- 候选使用 `macos-release-candidate.yml` 的 `workflow_dispatch`，指定 `git_ref` 和
  `release_tag`（例如 `vX.Y.Z-rc1`）。目标 commit 的版本设置仍须对应 `X.Y.Z` 及其 build。
  通过普通任务分支 / PR 准备版本；不要用会推正式 tag 的 bump 脚本准备候选。
- 候选 workflow 使用 `release-candidate` environment，只上传 artifact，不创建 GitHub Release，也不生成 Sparkle appcast。
- 只有要验证发布链路时才使用 `macos-release.yml` 的手动模式：它使用 `production`，
  创建 draft/prerelease，`latest=false`、`verify_tag=false`。这是远端写入，须在用户授权范围内。
- 跟踪 run 至完成，核对所构建 commit、签名、公证和 artifact。产物在 `dist/github-release/<release_tag>/`。

## 签名与 Sparkle 排查

仅在配置发布环境或排查相关失败时使用；实际变量清单见对应 workflow。

- macOS iCloud KVS 需要手动管理的 Developer ID distribution provisioning profile。
  两个 environment 的 `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` 保存 profile 的单行 base64。
  更新时一起核对 App ID、证书、iCloud KVS entitlement、distribution type、UUID 和匹配的 secrets。
- profile 名称通过 app target 专用的 `STET_RELEASE_PROVISIONING_PROFILE_SPECIFIER` 传入，
  避免 Swift package resource bundle 和 StetVisuals 继承 app profile。
- `SPARKLE_PRIVATE_KEY_BASE64` 使用 Sparkle `generate_keys -x` 导出文件的原始内容；
  文件已是所需 base64，不再次解码，也不用 Keychain UI 复制的密码替代。不要输出私钥内容。
- CI 按 `Package.resolved` 的 Sparkle 版本构建 `generate_appcast`；SwiftPM binary target 不提供该 CLI。
- 二进制 framework 的预复制规范化由 `scripts/normalize-binary-frameworks.sh` 负责，
  最终重签和打包由 `scripts/release-macos-github.sh` 负责，发布由 `scripts/publish-github-release.sh` 负责。
  排查具体嵌入组件时读取脚本当前列表。
- CI 中 DMG 的 `spctl` 可能返回 `source=Insufficient Context`；结合公证和 `stapler validate` 结果判断。
