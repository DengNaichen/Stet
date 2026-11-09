# Stet 验证

本文件只保留仓库级验证入口、适用范围与报告边界。端内定向命令由各端文档维护；硬约束见 [rules/](rules/index.md) 与 [ARCHITECTURE.md](ARCHITECTURE.md)。

不要把计划执行或 CI 配置推断为已通过。Agent 必须报告实际命令、退出码和未运行项。

## 常用入口

Git/worktree 工具：`python3 -m unittest discover -s scripts/tests -p 'test_*.py'`
包含临时本地 Git 仓库中的创建、合并、清理及并发更新保护测试；不会操作实际远端。
`/bin/sh -n scripts/new-worktree` 与 `/bin/zsh -n scripts/xcode-storage.sh`
检查 shell 语法。真实工作区资源回收仍受运行进程和文件归属检查约束，测试通过不代表
已经回收了当前机器的 DerivedData。使用流程见
[git-workflow](../.agents/skills/git-workflow/SKILL.md)。

| 范围 | 直接命令 | 详细入口 |
|------|----------|----------|
| macOS build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build` | [`AGENTS.md`](../AGENTS.md) |
| macOS test | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` | [`AGENTS.md`](../AGENTS.md) |
| iOS build | `make ios-build` | [`StetMobile/AGENTS.md`](../StetMobile/AGENTS.md) |
| lint / format | `make lint` | 根 [`Makefile`](../Makefile) |
| Harness 入口检查 | `scripts/validate-agent-entrypoints` | 本文件 |

macOS-only 目标（`ci-build`、`release-github`、`doctor` 等）见根 [`Makefile`](../Makefile)。

`make test` 顺序运行两个独立的测试进程：先并行运行常规测试，再运行三个刻意
阻塞 MainActor 的后台音频回归测试。后者用于验证音频处理不依赖 MainActor，
若和常规测试同进程并行，会消耗其他测试的 3 秒状态等待期限，在较慢的 CI runner
上造成启动状态误报超时。两组都必须通过；没有延长等待期限或跳过回归测试。
单独验证这三个回归用例可运行 `make test-mainactor-isolation`；它们的完整标识符由
[Makefile](../Makefile) 中的 `MACOS_MAIN_ACTOR_ISOLATION_TESTS` 统一维护。

## Hook 与 CI

- Pre-commit：[.githooks/](../.githooks)（若已安装）。
- GitHub Actions 总览：[`.github/WORKFLOWS.md`](../.github/WORKFLOWS.md)。
- 根 [Makefile](../Makefile) 直接构建根 `Stet.xcodeproj`，iOS 目标构建 `StetMobile/StetMobile.xcodeproj`。

### monorepo-ci.yml

仓库根 [`.github/workflows/monorepo-ci.yml`](../.github/workflows/monorepo-ci.yml) 在 PR 与 push 到 `main`、`migration/**` 时运行：

| CI job | 本地等价命令 |
|--------|--------------|
| Repository Checks（Linux，始终运行） | CI helper 单测、兼容名单校验、`scripts/validate-agent-entrypoints`；工作流改动时加 `actionlint` |
| Swift Quality | `make lint` |
| macOS Tests（包含 app 构建） | `make test` |
| CI Result（Linux，始终运行） | 汇总：所有选中的任务必须成功，未选中的任务必须跳过 |

[scripts/ci-changes.py](../scripts/ci-changes.py) 按完整 Git diff 选择任务：名单和文档改动只跑
Linux 检查，iOS Swift 改动跑现有 lint，macOS／共享包改动跑完整构建和
测试。独立 Debug Build 与 `make test` 重复，已移除；本地 `make ci-build`
仍可使用。具体路径、保守回退和 PR／push 差异语义见
[CI 范围说明](../.github/WORKFLOWS.md#change-based-ci-scope)。

CI 配置的本地验证：

```sh
python3 -m unittest discover -s scripts/tests -p 'test_*.py'
python3 scripts/validate-app-compatibility.py --base-ref origin/main
scripts/validate-agent-entrypoints
actionlint
```

### Release workflows

签名 release 与 RC 构建在根 [`.github/workflows/`](../.github/workflows/)（[macos-release.yml](../.github/workflows/macos-release.yml)、[macos-release-candidate.yml](../.github/workflows/macos-release-candidate.yml)），job 在仓库根执行。

### 本地-only

`make ios-build` 目前不在 CI 中；本地验证 iOS 时使用，详见 [`StetMobile/AGENTS.md`](../StetMobile/AGENTS.md)。

## 执行与报告

Agent 必须区分：

- `passed`：适用命令已运行且退出码为零。
- `failed`：至少一个适用命令运行失败。
- `skipped`：有意跳过并记录原因。
- `not_run`：验证适用但未执行。

## Worktree preparation

See the [git-workflow skill](../.agents/skills/git-workflow/SKILL.md#环境准备与缓存边界) for setup and cache isolation constraints.
Run `python3 -m unittest discover -s scripts/tests -p 'test_worktree_*.py' -v` for cache, setup, hook and pre-commit behavior. Actual multi-worktree build measurements are recorded under [docs/research/](research).

## 文档链接 lint

首次执行 `make docs-lint-setup`，使用 Python 3.11 在 `linter/.venv` 安装固定版本与哈希的依赖。
随后运行 `make docs-lint`；`make lint` 也包含此检查。修改检查器时运行 `make docs-lint-test`。
依赖清单见 [requirements.txt](../linter/requirements.txt)，扫描配置见 [config.toml](../linter/config.toml)。

检查当前工作树中 Git 跟踪和未忽略的 Markdown，含 skills、研究和旧 specs；跳过 symlink 文档副本。
[reference/](../reference/) 正文不扫描，但链接到它的文件仍检查存在性，目标锚点明确计为跳过。
使用 CommonMark 解析链接、图片、引用式链接及 HTML href/src，校验本地目标、精确大小写和 Markdown 标题锚点。
非 Markdown 目标的 fragment 只计跳过；不执行命令、不请求外网、不检查内容正确性。

正文中的具体文件引用写成 Markdown 链接；命令、代码示例、待创建的模板路径和本机生成文件保留代码形式。
未定义的 reference label 由 CommonMark 当成普通文本，不会被推断成文件链接。外部 URL、代码块及 frontmatter 不作为本地引用检查。

无历史豁免清单：断链返回退出码 1（Make 显示失败）；配置或依赖问题返回 2。
旧文档存在断链时，本地 lint 和 CI 会失败，逐项修正文档后自然恢复通过；失败不等于检查器本身损坏。
CI 的 Repository Checks 每次运行检查器测试和全量文档链接检查，不因仅修改文档而跳过，也不使用 continue-on-error。
