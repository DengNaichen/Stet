# Worktree 缓存实现与并发验收 — 2026-11-07

对应 [Stet #150 第三项](https://github.com/DengNaichen/Stet/issues/150)。基于该问题所在的架构分支提交 `a0bfe3f`，在独立工作区实现，未包含主工作区未提交的图标和文档改动。

## 已实现

- `deps-graph` 按输入内容共享只读可执行产物：源码/锁文件/工具链/SDK/架构/构建器失效判断，每键进程锁，私有编译目录，原子发布和产物哈希校验。
- `arch-check.py` 每次验证工具版本；统一 `/tmp` 与 `/private/tmp` 等别名路径，仍拒绝仓库外路径。
- `setup-worktree --if-needed` 真正准备架构工具，输出阶段、命中/等待状态和耗时；Claude/Codex SessionStart、Codex Darwin environment 与已有 Cursor 入口调用同一脚本。
- 本地 build/ci-build/test 打开 Xcode 原生编译缓存并输出 timing，保留 CI 配置和每个工作区独立的可写产物。
- pre-commit 去掉对 `rg` 的依赖，用 Git NUL 路径和 Python 选择文件，Git/format/lint 失败明确退出。

遵循 HarnessKit shared-memory 的缓存身份、独立可写状态、锁和完整后发布的思路。其 APFS npm 快照实现当时仍在本机实验 worktree，未把它当作已合入的生产能力，也没有复制其 Node/Docker runtime。

## 最终版本：真实工具准备

在两个独立 worktree 同时启动最终版本，使用默认用户缓存；只发生一次真实 SwiftSyntax 编译，另一个进程等待同一 key。

| 场景 | 耗时 | 结果 |
|---|---:|---|
| 空缓存，worktree A | 160.57 s | 成功，构建并发布 |
| 同时启动，implementation worktree | 160.85 s | 成功，等待后命中同一完整产物 |
| 第二个已存在 worktree B 准备 | 0.625 s | 成功，缓存命中 |
| 第三个新 worktree C 准备 | 0.622 s | 成功，缓存命中 |

这里的“新”是没有该 checkout 自己的工具构建产物；机器已有依赖下载缓存。没有将预热时间从总账隐藏：首次真实编译仍需约160秒，同版本后续 checkout 不再各自重复这次编译。

在此前真实源码失效实验中，仅在 B 的工具源码加入 stderr 标记：B 重新构建得到新 key，运行产物确实输出该标记；A 保持原 key 且不输出标记；恢复 B 源码后重新命中原 key。该编译与两个应用构建并发，耗时202.43秒，不能与上表串行/等待时间当作同负载比较。该实验在最后两项缓存守卫加固前执行；最终版本另外通过了构建器变化和空XDG路径的回归测试及上表真实冷构建。

## Xcode：正确性通过，跨路径提速尚不明显

准备四个 worktree A/B/C/D，各自有独立的 DerivedData 和 SourcePackages。为排除网络波动，从同一组已下载且锁定版本的依赖生成独立 APFS clone 副本；原生clonefile已验证不同inode、修改副本不影响原件。测试前置的本地FunASR xcframework也以独立副本准备，未纳入Git。

| 场景 | 耗时 | 结果 | Xcode `Cache hit` / `Cache miss` 状态行 |
|---|---:|---|---:|
| A：空实验CAS，并发构建 | 74.32 s | BUILD SUCCEEDED | 74 / 554 |
| B：同一CAS，并发构建 | 74.63 s | BUILD SUCCEEDED | 66 / 562 |
| C：新路径、已有CAS，单独构建 | 41.00 s | BUILD SUCCEEDED | 288 / 340 |
| D：新路径、关闭编译缓存，单独构建 | 41.58 s | BUILD SUCCEEDED | 0 / 0 |

A/B期间还运行了工具源码失效编译，是并发压力验收，不可与C/D直接计算提速倍率。C/D是相近条件的单次顺序样本：虽然C有缓存命中，41.00 vs 41.58秒不足以证明显著加速。没有宣称解决Xcode新路径的全部冷编译。

`Cache hit/miss`是日志中的独立状态行计数，不是代码覆盖率、唯一源码文件数或测试通过数量。共享CAS不会让整个构建目录可共享：`normalize-binary-frameworks.sh`确实会修改并签名Sherpa artifact。A/B签名产物inode不同，工作区私有树写入不会出现在另一树。

默认DerivedData下，本机Xcode把编译缓存放在父级 `CompilationCache.noindex`；指定 `-derivedDataPath` 后CAS跟随该目录。本实验显式指定统一的独立实验CAS路径，保持Build/ModuleCache/SourcePackages各自独立。CI现有 `.build/ci/CompilationCache.noindex` 配置不变。

## 验收与真实发现的问题

- 全部脚本测试：**50 passed**，其中33个覆盖本次新增的缓存、setup、hook、路径行为。
- 完整 macOS 测试：**626 passed，0 failed，0 skipped**（包含测试构建约62.26秒）。
- `make lint`：SwiftLint零违规，swift-format通过。
- 最终缓存产物在4个worktree同时运行架构检查：R0–R7全部0，均退出0（0.77–1.58秒）。
- 实际执行配置中的Claude/Codex SessionStart命令，故意让 `CLAUDE_PROJECT_DIR` 指向主checkout，仍准备当前worktree。未把这当作GUI宿主事件送达测试。

真实验收和审查发现并修复：

1. `swift`是按argv[0]分派的链接；解析到`swift-frontend`再运行`build`会失败。保留driver调用名，单独记录目标身份；真实失败后补了实际子进程回归。
2. 缓存脚本在编译中被修改时，旧Python进程不能用新脚本hash发布旧逻辑产物。固定加载时摘要并明确中止要求重启；回归先红后绿。
3. 空 `XDG_CACHE_HOME` 必须回退HOME，不能落到源码树；覆盖unset/empty/override。
4. Foundation报告`/tmp`、Python报告`/private/tmp`导致225条虚假R0违规。规范化事实路径后4个worktree全部通过；回归覆盖别名、相对路径和仓库外路径。

没有通过放宽规则、跳过测试或共享可写构建目录来获得成功。

## 命令与证据

```sh
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
./scripts/setup-worktree --if-needed
python3 scripts/arch-check.py --summary
make ci-build CI_XCODEBUILD_FLAGS='-derivedDataPath <private-dir> -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates COMPILATION_CACHE_CAS_PATH=<shared-experiment-cas> COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES'
make ci-build MACOS_COMPILATION_CACHE=NO CI_XCODEBUILD_FLAGS='<same options with another private-dir>'
make test CI_XCODEBUILD_FLAGS='<private-dir/cache options> -resultBundlePath <result.xcresult>'
```

[结构化测量结果](worktree-cache-validation-2026-11-07.json)记录环境、最终构建器摘要、测试和隔离结果。本机原始日志和xcresult位于 `/tmp/stet-worktree-measurements-20261107`，不是持久发布资产；为验收创建的worktree和DerivedData可按归属回收。

范围边界：setup只预备架构工具；缺少ignored FunASR runtime时明确警告并给出既有构建入口，不伪称空checkout已可直接构建app。不自动安装Homebrew、不迁移模型缓存、不清理用户其他worktree。本轮明确实现并量化的收益是消除重复的工具编译，Xcode跨路径命中优化仍保留为未解决的性能部分。

已按路径归属核对并回收本次4个probe worktree、4份私有DerivedData及独立实验CAS；保留实现worktree、默认用户工具缓存、日志与xcresult。未清理其他会话的worktree或全局缓存。

## PR 基线更新

提交PR前将本批改动单独移植到 `origin/main` 的 `b9638d2`，不携带原架构分支历史。主线已经用grep移除了hook对rg的依赖，本批保留NUL路径与错误传播的进一步改进；主线的无rg真实Git测试补齐Python运行时后，断言保持原样。当前54个脚本测试、make lint及架构R0–R7全0均通过。主线还更新了deps-graph源码的cwd规范化，因此内容缓存正确重建了一次；Python消费端保留仓库相对路径及越界校验。上面的4工作区构建与626应用测试属于原实现基线的实测，本次移植未重新执行整组应用基准。
