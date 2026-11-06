# 为什么每个 worktree 都要重新编译很久

记录日期：2026-11-06。状态：问题已确认，原因部分验证，方案未实施。

## 现象

在新的 git worktree 里跑 `make build`、`make test` 或 `python3 scripts/arch-check.py`，
第一次都要等好几分钟，期间没有进度输出，看起来像卡住。

## 已验证的事实

- **DerivedData 按工程路径区分。** `~/Library/Developer/Xcode/DerivedData/Stet-<hash>` 的
  `info.plist` 里 `WorkspacePath` 就是工程路径。每个 worktree 路径对应一份独立的 DerivedData，
  各 2–2.5 GB，首次构建要完整编译。记录时目录里有 4 份，合计约 10 GB，
  分别对应主仓库、`.infcode/worktrees/refactor-arch-rules`，以及 `/tmp` 下两个临时 worktree。
- **依赖检查工具每个 checkout 各编译一次。** `tools/deps-graph/.build` 被 `.gitignore` 忽略，
  不随分支走。首次运行要编译 swift-syntax，实测 `Build complete! (157.84s)`，目录约 208 MB。
- **worktree 很多且没清理。** `git worktree list` 有 18 条，其中大量指向 `/tmp` 且已标 `prunable`，
  另有 5 个在 `.infcode/worktrees/`。
- **仓库的 pre-commit 钩子依赖 `rg`，本机没有安装。** 提交时输出 `rg: command not found`，
  钩子被跳过，所以提交前不会自动格式化和 lint。这和编译慢无关，但同属本地环境没配好。
- `scripts/setup-worktree` 目前只是空壳（"skeleton (no-op)"），没有做任何预热或共享。
- Xcode 26.6。`xcodebuild -showBuildSettings` 里能看到 `COMPILATION_CACHE_CAS_PATH`
  （一个所有工程共用的目录），但没有看到 `COMPILATION_CACHE_ENABLE_CACHING`。

## 还没验证的假设

- 假设：Xcode 的编译缓存目前没有启用或没有命中，所以不同路径的 worktree 无法复用编译结果。
  需要用 `COMPILATION_CACHE_ENABLE_CACHING=YES` 实测一次冷构建的耗时再对比。
- 我没有量过一次完整的冷构建（Xcode 部分）具体耗时，只知道会话中多次等待了数分钟。
- Swift 包的下载和解析是否每个 DerivedData 各做一次，没有确认。

## 可以尝试的方案（均未实施）

1. 对 `xcodebuild` 打开编译缓存（`COMPILATION_CACHE_ENABLE_CACHING=YES`），先在一个新 worktree 上
   对比冷构建耗时，有效再写进 Makefile。
2. 让 `scripts/arch-check.py` 把 deps-graph 的构建目录放到所有 checkout 共用的位置
   （例如按 `Package.resolved` 的哈希命名），避免每个 worktree 重编 swift-syntax。
3. 用 `-clonedSourcePackagesDirPath` 让多个 worktree 共用 Swift 包检出。
4. 定期 `git worktree prune`，并删除对应的 DerivedData；把常用的 worktree 数量控制在个位数。
5. 在 `scripts/setup-worktree` 里做预热（构建一次、安装依赖检查工具），并输出进度，
   这样等待时能看到它在做什么。
6. 安装 ripgrep（`brew install ripgrep`），让 pre-commit 钩子真正生效。

## 给自动化工具（agent）的提示

长时间的构建和测试应放到后台运行并监控结果，不要在前台等待。
这类等待没有输出，用户很容易以为工具卡死而中断。
