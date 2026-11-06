#!/usr/bin/env python3
"""Safely clean merged Git branches and their worktrees.

The command is intentionally conservative. It must run from a clean ``main``
worktree, defaults to a dry run, and never treats branch names or a deleted
remote ref as proof that work was merged.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import uuid
from urllib.parse import urlsplit
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Sequence, TextIO, Tuple


BASE_BRANCH = "main"
REMOTE_NAME = "origin"
PROTECTED_PREFIXES = ("future/",)


class SafetyError(RuntimeError):
    """Raised when cleanup cannot proceed without risking repository state."""


class CommandError(RuntimeError):
    """Raised when a subprocess command fails."""

    def __init__(self, args: Sequence[str], process: subprocess.CompletedProcess):
        detail = (process.stderr or process.stdout or "command failed").strip()
        detail = re.sub(r"(https?://)[^/\s]*@", r"\1<redacted>@", detail)
        super().__init__("{}: {}".format(re.sub(r"(https?://)[^/\s]*@", r"\1<redacted>@", " ".join(args)), detail))
        self.args_run = list(args)
        self.returncode = process.returncode


class CommandRunner:
    """Run commands without a shell so branch names remain data, not code."""

    def run(
        self,
        args: Sequence[str],
        cwd: Path,
        check: bool = True,
    ) -> subprocess.CompletedProcess:
        process = subprocess.run(
            list(args),
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            shell=False,
        )
        if check and process.returncode != 0:
            raise CommandError(args, process)
        return process


@dataclass(frozen=True)
class Worktree:
    path: Path
    branch: Optional[str]
    oid: str
    clean: bool
    status_error: Optional[str] = None


@dataclass(frozen=True)
class RepositorySnapshot:
    root: Path
    local_branches: Dict[str, str]
    remote_branches: Dict[str, str]
    worktrees: List[Worktree]


@dataclass(frozen=True)
class BaseStatus:
    local_oid: str
    remote_oid: str
    behind_count: int


@dataclass(frozen=True)
class MergeEvidence:
    kind: str
    detail: str
    merge_oid: Optional[str] = None


@dataclass(frozen=True)
class MergeCheck:
    evidence: Optional[MergeEvidence]
    reason: str


@dataclass(frozen=True)
class WorktreeAction:
    path: Path
    branch: str
    oid: str
    evidence: MergeEvidence


@dataclass(frozen=True)
class BranchAction:
    branch: str
    oid: str
    evidence: MergeEvidence


@dataclass(frozen=True)
class KeptItem:
    scope: str
    branch: str
    reason: str


@dataclass(frozen=True)
class SkippedItem:
    scope: str
    branch: str
    reason: str


@dataclass
class CleanupPlan:
    worktrees: List[WorktreeAction] = field(default_factory=list)
    local_branches: List[BranchAction] = field(default_factory=list)
    remote_branches: List[BranchAction] = field(default_factory=list)
    kept: List[KeptItem] = field(default_factory=list)
    skipped: List[SkippedItem] = field(default_factory=list)
    remote_disabled_count: int = 0


def is_protected_branch(branch: str) -> bool:
    return branch == BASE_BRANCH or branch.startswith(PROTECTED_PREFIXES)


def github_repository_from_remote(url: str) -> Optional[str]:
    if url.startswith(("https://", "http://")):
        parsed = urlsplit(url)
        if parsed.hostname == "github.com":
            url = "https://github.com" + parsed.path
    patterns = (
        r"^git@github\.com:([^/]+)/(.+)$",
        r"^ssh://git@github\.com/([^/]+)/(.+)$",
        r"^https?://github\.com/([^/]+)/(.+)$",
    )
    for pattern in patterns:
        match = re.match(pattern, url.strip())
        if not match:
            continue
        owner, repository = match.groups()
        if repository.endswith(".git"):
            repository = repository[:-4]
        if owner and repository:
            return "{}/{}".format(owner, repository)
    return None


def find_exact_merged_pr(
    branch: str,
    oid: str,
    pull_requests: Iterable[dict],
) -> Optional[MergeEvidence]:
    for pull_request in pull_requests:
        if not pull_request.get("mergedAt"):
            continue
        if pull_request.get("headRefName") != branch:
            continue
        if pull_request.get("headRefOid") != oid:
            continue
        if pull_request.get("baseRefName") != BASE_BRANCH:
            continue
        merge_commit = pull_request.get("mergeCommit")
        if not isinstance(merge_commit, dict) or not merge_commit.get("oid"):
            continue
        number = pull_request.get("number")
        return MergeEvidence(
            "pull-request",
            "merged PR #{} exact head into {}".format(number, BASE_BRANCH),
            merge_commit["oid"],
        )
    return None


def build_cleanup_plan(
    snapshot: RepositorySnapshot,
    merge_checker: Callable[[str, str], MergeCheck],
    include_remote: bool,
) -> CleanupPlan:
    plan = CleanupPlan()
    worktrees_by_branch = {
        worktree.branch: worktree
        for worktree in snapshot.worktrees
        if worktree.branch is not None
    }
    dirty_worktree_branches = {
        branch
        for branch, worktree in worktrees_by_branch.items()
        if not worktree.clean
    }
    check_cache: Dict[Tuple[str, str], MergeCheck] = {}

    def check(branch: str, oid: str) -> MergeCheck:
        key = (branch, oid)
        if key not in check_cache:
            check_cache[key] = merge_checker(branch, oid)
        return check_cache[key]

    for branch, oid in sorted(snapshot.local_branches.items()):
        if branch == BASE_BRANCH:
            plan.kept.append(KeptItem("local", branch, "protected base branch"))
            continue
        if branch.startswith(PROTECTED_PREFIXES):
            plan.kept.append(KeptItem("local", branch, "protected future branch"))
            continue

        worktree = worktrees_by_branch.get(branch)
        if worktree is not None and not worktree.clean:
            reason = worktree.status_error or "dirty worktree at {}".format(worktree.path)
            plan.kept.append(KeptItem("local", branch, reason))
            continue

        result = check(branch, oid)
        if result.evidence is None:
            plan.kept.append(KeptItem("local", branch, result.reason))
            continue

        if worktree is not None:
            plan.worktrees.append(
                WorktreeAction(worktree.path, branch, oid, result.evidence)
            )
        plan.local_branches.append(BranchAction(branch, oid, result.evidence))

    for worktree in snapshot.worktrees:
        if worktree.branch is None:
            plan.kept.append(KeptItem("worktree", "(detached)",
                                      "detached checkout preserved at {}".format(worktree.path)))

    if not include_remote:
        for branch in sorted(snapshot.remote_branches):
            if branch == BASE_BRANCH:
                plan.kept.append(KeptItem("remote", branch, "protected base branch"))
                continue
            if branch.startswith(PROTECTED_PREFIXES):
                plan.kept.append(
                    KeptItem("remote", branch, "protected future branch")
                )
                continue
            plan.skipped.append(
                SkippedItem(
                    "remote",
                    branch,
                    "remote cleanup disabled; add --remote to include it",
                )
            )
        plan.remote_disabled_count = len(plan.skipped)
        return plan

    for branch, oid in sorted(snapshot.remote_branches.items()):
        if branch == BASE_BRANCH:
            plan.kept.append(KeptItem("remote", branch, "protected base branch"))
            continue
        if branch.startswith(PROTECTED_PREFIXES):
            plan.kept.append(KeptItem("remote", branch, "protected future branch"))
            continue
        if branch in dirty_worktree_branches:
            worktree = worktrees_by_branch[branch]
            reason = worktree.status_error or "dirty worktree at {}".format(worktree.path)
            plan.kept.append(KeptItem("remote", branch, reason))
            continue

        result = check(branch, oid)
        if result.evidence is None:
            plan.kept.append(KeptItem("remote", branch, result.reason))
            continue
        plan.remote_branches.append(BranchAction(branch, oid, result.evidence))

    return plan


class GitRepository:
    def __init__(self, root: Path, runner: Optional[CommandRunner] = None):
        self.root = root.resolve()
        self.runner = runner or CommandRunner()
        self._remote_url: Optional[str] = None
        self.archive_id = uuid.uuid4().hex
        self._pr_cache: Dict[str, Tuple[List[dict], Optional[str]]] = {}

    @classmethod
    def discover(
        cls,
        cwd: Path,
        runner: Optional[CommandRunner] = None,
    ) -> "GitRepository":
        command_runner = runner or CommandRunner()
        process = command_runner.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd,
        )
        return cls(Path(process.stdout.strip()), command_runner)

    def _run_git(
        self,
        args: Sequence[str],
        cwd: Optional[Path] = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess:
        return self.runner.run(
            ["git"] + list(args),
            cwd=cwd or self.root,
            check=check,
        )

    def ensure_safe_entry(self) -> None:
        branch_process = self._run_git(
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            check=False,
        )
        if branch_process.returncode != 0:
            raise SafetyError("run cleanup from a branch, not detached HEAD")
        branch = branch_process.stdout.strip()
        if branch != BASE_BRANCH:
            raise SafetyError("run cleanup from the clean main worktree")
        if self._status_output(self.root):
            raise SafetyError("main worktree is dirty; commit or restore it before cleanup")
        self._run_git(["remote", "get-url", REMOTE_NAME])

    def refresh(self) -> None:
        self._run_git(["fetch", "--prune", REMOTE_NAME])

    def base_status(self) -> BaseStatus:
        local_oid = self._resolve_ref(BASE_BRANCH)
        remote_ref = "{}/{}".format(REMOTE_NAME, BASE_BRANCH)
        remote_oid = self._resolve_ref(remote_ref)
        if local_oid == remote_oid:
            return BaseStatus(local_oid, remote_oid, 0)
        if not self._is_ancestor(local_oid, remote_oid):
            raise SafetyError(
                "main cannot fast-forward to {}; reconcile it manually".format(remote_ref)
            )
        process = self._run_git(
            ["rev-list", "--count", "{}..{}".format(BASE_BRANCH, remote_ref)]
        )
        return BaseStatus(local_oid, remote_oid, int(process.stdout.strip()))

    def fast_forward_main(self) -> None:
        self._run_git(
            ["merge", "--ff-only", "{}/{}".format(REMOTE_NAME, BASE_BRANCH)]
        )

    def snapshot(self) -> RepositorySnapshot:
        local_branches = self._read_refs("refs/heads")
        remote_refs = self._read_refs("refs/remotes/{}".format(REMOTE_NAME))
        remote_branches: Dict[str, str] = {}
        prefix = REMOTE_NAME + "/"
        for ref, oid in remote_refs.items():
            if not ref.startswith(prefix):
                continue
            branch = ref[len(prefix) :]
            if branch == "HEAD":
                continue
            remote_branches[branch] = oid
        return RepositorySnapshot(
            root=self.root,
            local_branches=local_branches,
            remote_branches=remote_branches,
            worktrees=self._read_worktrees(),
        )

    def merge_check(self, branch: str, oid: str) -> MergeCheck:
        remote_main = "{}/{}".format(REMOTE_NAME, BASE_BRANCH)
        pull_requests, error = self._merged_pull_requests(branch)
        if any(pr.get("state") == "OPEN" for pr in pull_requests):
            return MergeCheck(None, "branch has an open PR")
        # For GitHub, a failed lookup cannot establish whether an open PR exists.
        if error and self._remote_url and github_repository_from_remote(self._remote_url):
            return MergeCheck(None, error)
        if self._is_ancestor(oid, remote_main):
            return MergeCheck(
                MergeEvidence("ancestry", "tip is contained in {}".format(remote_main)),
                "",
            )

        if error:
            return MergeCheck(None, error)
        evidence = find_exact_merged_pr(branch, oid, pull_requests)
        if evidence is not None and evidence.merge_oid is not None:
            try:
                merge_is_current = self._is_ancestor(evidence.merge_oid, remote_main)
            except CommandError:
                merge_is_current = False
            if merge_is_current:
                return MergeCheck(evidence, "")
            return MergeCheck(
                None,
                "exact-head merged PR is no longer contained in {}".format(remote_main),
            )
        return MergeCheck(
            None,
            "tip is not in {} and no merged PR has this exact head".format(remote_main),
        )

    def revalidate_worktree(self, action: WorktreeAction) -> None:
        if is_protected_branch(action.branch):
            raise SafetyError("refusing to remove protected branch {}".format(action.branch))
        if not action.path.exists():
            raise SafetyError("worktree disappeared before apply: {}".format(action.path))
        if self._status_output(action.path, include_ignored=True):
            raise SafetyError(
                "worktree became dirty or contains ignored files before apply: {}".format(
                    action.path
                )
            )
        branch_process = self._run_git(
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            cwd=action.path,
            check=False,
        )
        if branch_process.returncode != 0 or branch_process.stdout.strip() != action.branch:
            raise SafetyError("worktree branch changed before apply: {}".format(action.path))
        if self._resolve_ref(action.branch) != action.oid:
            raise SafetyError("branch tip changed before apply: {}".format(action.branch))
        self._pr_cache.pop(action.branch, None)
        if self.merge_check(action.branch, action.oid).evidence is None:
            raise SafetyError("merge evidence disappeared for {}".format(action.branch))

    def revalidate_branch(self, action: BranchAction, remote: bool) -> None:
        if is_protected_branch(action.branch):
            raise SafetyError("refusing to delete protected branch {}".format(action.branch))
        ref = (
            "{}/{}".format(REMOTE_NAME, action.branch)
            if remote
            else action.branch
        )
        if self._resolve_ref(ref) != action.oid:
            raise SafetyError("branch tip changed before apply: {}".format(ref))
        self._pr_cache.pop(action.branch, None)
        if self.merge_check(action.branch, action.oid).evidence is None:
            raise SafetyError("merge evidence disappeared for {}".format(action.branch))
        if not remote:
            checked_out = {
                worktree.branch
                for worktree in self._read_worktrees()
                if worktree.branch is not None
            }
            if action.branch in checked_out:
                raise SafetyError("branch is still checked out: {}".format(action.branch))

    def archive(self, scope: str, branch: str, oid: str) -> None:
        ref = "refs/archive/branch-cleanup/{}/{}/{}".format(self.archive_id, scope, branch)
        self._run_git(["update-ref", ref, oid])

    def remove_worktree(self, action: WorktreeAction) -> None:
        self.archive("heads", action.branch, action.oid)
        if (action.path / "Stet.xcodeproj").is_dir():
            # Use the caller's trusted cleanup implementation, not code from the old branch.
            cleaner = Path(__file__).resolve().parent / "xcode-storage.sh"
            self.runner.run(["/bin/zsh", str(cleaner), "clean-project", str(action.path)], self.root)
        self.revalidate_worktree(action)
        self._run_git(["worktree", "remove", str(action.path)])

    def delete_local_branch(self, action: BranchAction) -> None:
        ref = "refs/heads/{}".format(action.branch)
        self.archive("heads", action.branch, action.oid)
        self._run_git(
            [
                "update-ref",
                "-d",
                ref,
                action.oid,
            ]
        )
        try:
            checked_out = {
                worktree.branch
                for worktree in self._read_worktrees()
                if worktree.branch is not None
            }
        except (CommandError, OSError):
            self._restore_deleted_ref(ref, action.oid)
            raise
        if action.branch in checked_out:
            self._restore_deleted_ref(ref, action.oid)
            raise SafetyError(
                "branch became checked out during deletion; restored {}".format(
                    action.branch
                )
            )
        # Remove stale upstream configuration only if the branch has not reappeared.
        if self._run_git(["show-ref", "--verify", "--quiet", ref], check=False).returncode != 0:
            self._run_git(["config", "--remove-section", "branch." + action.branch], check=False)

    def _restore_deleted_ref(self, ref: str, oid: str) -> None:
        process = self._run_git(
            ["update-ref", ref, oid, "0" * len(oid)],
            check=False,
        )
        if process.returncode == 0:
            return
        current = self._run_git(["rev-parse", "--verify", ref], check=False)
        if current.returncode != 0:
            raise SafetyError("failed to restore {} after a cleanup race".format(ref))

    def ensure_remote_delete_target(self) -> None:
        fetch_process = self._run_git(
            ["remote", "get-url", "--all", REMOTE_NAME]
        )
        push_process = self._run_git(
            ["remote", "get-url", "--push", "--all", REMOTE_NAME]
        )
        fetch_urls = [line for line in fetch_process.stdout.splitlines() if line]
        push_urls = [line for line in push_process.stdout.splitlines() if line]
        if len(fetch_urls) != 1 or len(push_urls) != 1 or fetch_urls != push_urls:
            raise SafetyError(
                "origin fetch/push URLs differ or are ambiguous; remote cleanup is unsafe"
            )

    def delete_remote_branches(self, actions: Sequence[BranchAction]) -> None:
        if not actions:
            return
        self.ensure_remote_delete_target()
        for action in actions:
            self.archive("remotes/origin", action.branch, action.oid)
        self._run_git(
            ["push", "--atomic"]
            + [
                "--force-with-lease=refs/heads/{}:{}".format(
                    action.branch, action.oid
                )
                for action in actions
            ]
            + [REMOTE_NAME, "--delete"]
            + [action.branch for action in actions]
        )
        self._run_git(["fetch", "--prune", REMOTE_NAME])

    def _read_refs(self, namespace: str) -> Dict[str, str]:
        process = self._run_git(
            [
                "for-each-ref",
                "--format=%(refname:short)%09%(objectname)",
                namespace,
            ]
        )
        refs: Dict[str, str] = {}
        for line in process.stdout.splitlines():
            if not line.strip():
                continue
            ref, oid = line.split("\t", 1)
            refs[ref] = oid
        return refs

    def _read_worktrees(self) -> List[Worktree]:
        process = self._run_git(["worktree", "list", "--porcelain"])
        worktrees: List[Worktree] = []
        for record in process.stdout.strip().split("\n\n"):
            if not record.strip():
                continue
            fields: Dict[str, str] = {}
            for line in record.splitlines():
                key, separator, value = line.partition(" ")
                fields[key] = value if separator else ""
            path = Path(fields["worktree"])
            branch_ref = fields.get("branch")
            branch = None
            if branch_ref and branch_ref.startswith("refs/heads/"):
                branch = branch_ref[len("refs/heads/") :]
            try:
                status = self._status_output(path, include_ignored=True)
                clean = not status
                status_error = (
                    None
                    if clean
                    else "dirty or ignored worktree at {}".format(path)
                )
            except (CommandError, OSError) as error:
                clean = False
                status_error = "worktree status unavailable at {}: {}".format(path, error)
            if not worktrees or "locked" in fields:
                clean = False
                status_error = "primary or locked worktree is protected"
            worktrees.append(
                Worktree(
                    path=path,
                    branch=branch,
                    oid=fields.get("HEAD", ""),
                    clean=clean,
                    status_error=status_error,
                )
            )
        return worktrees

    def _status_output(self, path: Path, include_ignored: bool = False) -> str:
        args = ["status", "--porcelain", "--untracked-files=all"]
        if include_ignored:
            args.append("--ignored=matching")
        process = self._run_git(
            args,
            cwd=path,
        )
        return process.stdout.strip()

    def _resolve_ref(self, ref: str) -> str:
        process = self._run_git(["rev-parse", "--verify", ref])
        return process.stdout.strip()

    def _is_ancestor(self, older: str, newer: str) -> bool:
        process = self._run_git(
            ["merge-base", "--is-ancestor", older, newer],
            check=False,
        )
        if process.returncode == 0:
            return True
        if process.returncode == 1:
            return False
        raise CommandError(
            ["git", "merge-base", "--is-ancestor", older, newer],
            process,
        )

    def _merged_pull_requests(self, branch: str) -> Tuple[List[dict], Optional[str]]:
        if branch in self._pr_cache:
            return self._pr_cache[branch]
        if self._remote_url is None:
            self._remote_url = self._run_git(["remote", "get-url", REMOTE_NAME]).stdout.strip()
        if shutil.which("gh") is None:
            result = ([], "GitHub CLI is unavailable; squash merge is unproven")
            self._pr_cache[branch] = result
            return result

        repository = github_repository_from_remote(self._remote_url)
        if repository is None:
            result = ([], "origin is not a GitHub repository; squash merge is unproven")
            self._pr_cache[branch] = result
            return result

        auth = self.runner.run(
            ["gh", "auth", "status"],
            cwd=self.root,
            check=False,
        )
        if auth.returncode != 0:
            result = ([], "GitHub authentication is unavailable; squash merge is unproven")
            self._pr_cache[branch] = result
            return result

        try:
            opened = self.runner.run(
                ["gh", "pr", "list", "--repo", repository, "--state", "open",
                 "--head", branch, "--limit", "1", "--json", "number,state"], self.root
            )
            active = json.loads(opened.stdout)
            if not isinstance(active, list):
                raise ValueError("expected an open PR list")
            if active:
                result = (active, None)
                self._pr_cache[branch] = result
                return result
            process = self.runner.run(
                [
                    "gh",
                    "pr",
                    "list",
                    "--repo",
                    repository,
                    "--state",
                    "merged",
                    "--head",
                    branch,
                    "--limit",
                    "20",
                    "--json",
                    "number,state,headRefName,headRefOid,baseRefName,mergeCommit,mergedAt,url",
                ],
                cwd=self.root,
            )
            payload = json.loads(process.stdout)
            if not isinstance(payload, list):
                raise ValueError("expected a JSON list")
            result = (payload, None)
        except (CommandError, ValueError, json.JSONDecodeError) as error:
            result = ([], "GitHub PR lookup failed; squash merge is unproven: {}".format(error))
        self._pr_cache[branch] = result
        return result


def render_plan(
    plan: CleanupPlan,
    base_status: BaseStatus,
    apply: bool,
    include_remote: bool,
    output: TextIO,
) -> None:
    print("Mode: {}".format("apply" if apply else "dry-run"), file=output)
    if base_status.behind_count:
        verb = "fast-forwarded" if apply else "would fast-forward"
        print(
            "Main: {} by {} commit(s)".format(verb, base_status.behind_count),
            file=output,
        )
    else:
        print("Main: already matches origin/main", file=output)

    for action in plan.worktrees:
        print(
            "REMOVE worktree {} [{}; {}]".format(
                action.path, action.branch, action.evidence.detail
            ),
            file=output,
        )
    for action in plan.local_branches:
        print(
            "DELETE local {} [{}]".format(action.branch, action.evidence.detail),
            file=output,
        )
    for action in plan.remote_branches:
        print(
            "DELETE remote {} [{}]".format(action.branch, action.evidence.detail),
            file=output,
        )
    for item in plan.kept:
        print(
            "KEEP {} {} [{}]".format(item.scope, item.branch, item.reason),
            file=output,
        )
    for item in plan.skipped:
        print(
            "SKIP {} {} [{}]".format(item.scope, item.branch, item.reason),
            file=output,
        )

    if not include_remote:
        print(
            "Remote cleanup: disabled; add --remote to preview or apply {} branch(es)".format(
                plan.remote_disabled_count
            ),
            file=output,
        )
    print(
        "Summary: {} worktree(s), {} local branch(es), {} remote branch(es) selected".format(
            len(plan.worktrees),
            len(plan.local_branches),
            len(plan.remote_branches),
        ),
        file=output,
    )
    if not apply:
        suffix = " --remote" if include_remote else ""
        print("Dry-run only. Re-run with --apply{} after review.".format(suffix), file=output)


def apply_cleanup_plan(repository: GitRepository, plan: CleanupPlan) -> None:
    if plan.remote_branches:
        repository.ensure_remote_delete_target()
    for action in plan.worktrees:
        repository.revalidate_worktree(action)
        repository.remove_worktree(action)
    for action in plan.local_branches:
        repository.revalidate_branch(action, remote=False)
        repository.delete_local_branch(action)
    for action in plan.remote_branches:
        repository.revalidate_branch(action, remote=True)
    repository.delete_remote_branches(plan.remote_branches)


def run_cleanup(
    repository: GitRepository,
    apply: bool,
    include_remote: bool,
    output: TextIO,
    branches: Optional[Sequence[str]] = None,
) -> CleanupPlan:
    repository.ensure_safe_entry()
    repository.refresh()
    base_status = repository.base_status()
    if apply and base_status.behind_count:
        repository.fast_forward_main()
    snapshot = repository.snapshot()
    plan = build_cleanup_plan(snapshot, repository.merge_check, include_remote)
    if branches:
        selected = set(branches)
        known = set(snapshot.local_branches) | set(snapshot.remote_branches)
        if selected - known:
            raise SafetyError("unknown branches: " + ", ".join(sorted(selected - known)))
        for field_name in ("worktrees", "local_branches", "remote_branches", "kept", "skipped"):
            setattr(plan, field_name, [item for item in getattr(plan, field_name) if item.branch in selected])
    render_plan(plan, base_status, apply, include_remote, output)
    if apply:
        apply_cleanup_plan(repository, plan)
        if hasattr(repository, "archive_id"):
            print("Recovery refs: refs/archive/branch-cleanup/" + repository.archive_id + "/", file=output)
    return plan


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Safely clean merged branches from a clean main worktree.",
        epilog=(
            "The command always runs 'git fetch --prune origin'. Dry-run mode does not "
            "fast-forward main or delete worktrees/branches. --remote only includes remote "
            "branches in the plan; deletion still requires --apply."
        ),
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="apply the reviewed plan; otherwise only print it",
    )
    parser.add_argument(
        "--remote",
        action="store_true",
        help="include merged remote branches (actual deletion also requires --apply)",
    )
    parser.add_argument("--branch", action="append", help="limit cleanup to this branch (repeatable)")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        repository = GitRepository.discover(Path.cwd())
        run_cleanup(repository, args.apply, args.remote, sys.stdout, args.branch)
    except (SafetyError, CommandError, OSError) as error:
        print("error: {}".format(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
