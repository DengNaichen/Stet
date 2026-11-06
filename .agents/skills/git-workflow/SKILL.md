---
name: git-workflow
description: 管理 Stet 的任务分支、worktree、提交、GitHub PR 和合并后清理。开始代码修改或处理 Git 交付与收尾时使用；只读分析无需创建分支。
---

# Stet Git workflow

## 开工

主 checkout 的稳定位置是 `main`；实现放在任务 worktree。先检查当前分支、
`git status --short`、upstream 和 `git worktree list --porcelain`。
已有改动先确认归属，保留现场，不用切分支、stash 或 reset 自动迁移它们。
现有脏主 checkout 不需要为遵守新规则而立即切换到 main。

一个独立交付对应一个分支、一个 PR、最多一个可写 worktree。
有 GitHub issue 时命名 `issue-<编号>-<短名>`；无 issue 的明确小任务用
`fix/<短名>`、`feat/<短名>` 或 `chore/<短名>`，不强制为此开票。
已合并的工作分支结束使用，新任务从最新 `origin/main` 开始。

手工创建使用仓库入口：

```sh
scripts/new-worktree issue-143-pre-commit
```

入口刷新远端基线后创建 sibling `stet-worktrees/<branch-slug>`，调用目标
checkout 的 `scripts/setup-worktree`。已有分支对应 worktree 时复用原路径，
包括宿主管理路径；`--no-setup` 仅用于明确无需构建环境的任务。
setup 失败保留目录，在该目录修复并重跑。不要另建 `/tmp` clone 来交付同一任务。
后续命令显式使用返回路径作为工作目录。检查分支、HEAD 和 diff 再开始修改。

有真实实现依赖时用 `--base <前置分支>` 创建堆叠分支，PR 指向前置分支。
前置 PR 合并后，将当前 PR 接回 main 并核对实际 diff；squash 后需要核对提交范围，
不能仅改 base 就宣称完成。独立任务始终直接面向 main。

`main` 和登记过的 `future/*` 为长期分支。未来实验用对应 issue 或仓库文档记录
保留原因、起点和退出条件；进入实现时另开普通任务分支。

## 提交与 PR

按路径 stage，只提交当前任务；使用简洁的 conventional commit 描述行为变化。
按改动运行验证并区分本地测试、模拟依赖和实际 App 验证。
PR 目标默认 main，关联解决的 issue 用 `Fixes #<编号>`。
显式 push 当前分支并设置 upstream；核对远端 URL 的目标仓库，输出时遮蔽凭据。
创建后读回 base、head 和文件范围，确认没有带入其他工作。
“提交并开 PR”不授权合并，也不授权自动合并。

此流程跨 Codex、Claude Code、Cursor 使用，不依赖 Herdr；用户明确要求 Herdr
时才使用其适配流程。现有 setup/cache 入口负责环境，本 skill 不另建缓存实现。

## 合并后收尾

确认 PR 已合并及最终 head，检查该分支是否又有新提交、未推送工作或未提交文件。
用户授权清理后，从干净的 main checkout 使用：

```sh
python3 scripts/cleanup-branches.py --branch issue-143-pre-commit --remote
python3 scripts/cleanup-branches.py --branch issue-143-pre-commit --remote --apply
```

省略 `--branch` 盘点所有分支；省略 `--remote` 只处理本地分支。
默认预览会 fetch/prune 远端引用，但不更新本地 main 或删除文件。
apply 会在 main 可快进时更新它，重新计算并核对候选；同时协调其他 agent，
清理期间不要继续编辑、启动或使用候选工作区。

清理证据为 tip 已进入 origin/main，或该分支的准确 tip 对应已合入 main 的 PR。
工具保护开放 PR、主/锁定 worktree、`future/*`，以及含未跟踪或 ignored 文件的
工作区。PR 查询失败时保留 GitHub 分支；不根据名字、年龄或远端消失判断可删。
手动放弃未合并实验需要用户明确指定，不属于批量脚本的合并清理范围。

对于含生成文件的工作区，先检查文件归属；可再生缓存通过
`scripts/xcode-storage.sh clean-project <worktree路径>` 清理。其他 ignored 文件
（模型、运行时、环境、HANDOFF 等）先保存或由用户明确处置，脚本不会强制删除。
工作区干净后，apply 在移除目录前调用相同缓存入口清理归属该路径的 DerivedData；
资源清理失败则停止，不删该工作区或分支。宿主拥有的工作区先按宿主生命周期关闭。
共享下载/编译缓存、Archives、签名数据和其他 worktree 的资源不属于清理范围。

每次删除前保存 `refs/archive/branch-cleanup/<运行ID>/...`，远端删除绑定准确 tip。
恢复提交可用 `git branch <恢复名> <归档引用>`；归档只保留已提交内容，不备份文件。
报告已删除/保留项、阻塞原因和归档前缀。不要用 detached HEAD 代替已完成工作区的回收。
