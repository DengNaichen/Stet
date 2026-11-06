import importlib.util
import io
import os
from unittest.mock import patch
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "cleanup-branches.py"
SPEC = importlib.util.spec_from_file_location("cleanup_branches", SCRIPT_PATH)
cleanup = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = cleanup
SPEC.loader.exec_module(cleanup)


class FakeRepository:
    def __init__(self, snapshot, checks, behind_count=0):
        self._snapshot = snapshot
        self._checks = checks
        self._base = cleanup.BaseStatus("local", "remote", behind_count)
        self.events = []

    def ensure_safe_entry(self):
        self.events.append(("ensure",))

    def refresh(self):
        self.events.append(("refresh",))

    def base_status(self):
        return self._base

    def fast_forward_main(self):
        self.events.append(("fast-forward",))

    def snapshot(self):
        return self._snapshot

    def merge_check(self, branch, oid):
        return self._checks[(branch, oid)]

    def revalidate_worktree(self, action):
        self.events.append(("revalidate-worktree", action.branch))

    def remove_worktree(self, action):
        self.events.append(("remove-worktree", action.branch))

    def revalidate_branch(self, action, remote):
        scope = "remote" if remote else "local"
        self.events.append(("revalidate-{}".format(scope), action.branch))

    def delete_local_branch(self, action):
        self.events.append(("delete-local", action.branch))

    def ensure_remote_delete_target(self):
        self.events.append(("verify-remote-target",))

    def delete_remote_branches(self, actions):
        if actions:
            self.events.append(
                ("delete-remote", tuple(action.branch for action in actions))
            )


class RecordingRunner:
    def __init__(self):
        self.calls = []

    def run(self, args, cwd, check=True):
        self.calls.append((list(args), Path(cwd), check))
        return subprocess.CompletedProcess(args, 0, "", "")


class CleanupPlanTests(unittest.TestCase):
    def setUp(self):
        self.ancestry = cleanup.MergeCheck(
            cleanup.MergeEvidence("ancestry", "contained in origin/main"), ""
        )
        self.pull_request = cleanup.MergeCheck(
            cleanup.MergeEvidence("pull-request", "merged PR #42 exact head"), ""
        )
        self.unproven = cleanup.MergeCheck(None, "merge is unproven")

    def test_plan_protects_future_dirty_and_unproven_branches(self):
        root = Path("/repo")
        snapshot = cleanup.RepositorySnapshot(
            root=root,
            local_branches={
                "main": "m",
                "future/idea": "f",
                "merged": "a",
                "squash": "s",
                "dirty": "d",
                "unique": "u",
            },
            remote_branches={
                "main": "m",
                "future/idea": "f",
                "merged": "a",
                "squash": "s",
                "dirty": "d",
                "unique": "u",
            },
            worktrees=[
                cleanup.Worktree(root, "main", "m", True),
                cleanup.Worktree(root / "dirty", "dirty", "d", False),
            ],
        )
        checks = {
            ("merged", "a"): self.ancestry,
            ("squash", "s"): self.pull_request,
            ("unique", "u"): self.unproven,
        }

        plan = cleanup.build_cleanup_plan(
            snapshot, lambda branch, oid: checks[(branch, oid)], include_remote=True
        )

        self.assertEqual(
            [action.branch for action in plan.local_branches], ["merged", "squash"]
        )
        self.assertEqual(
            [action.branch for action in plan.remote_branches], ["merged", "squash"]
        )
        kept = {(item.scope, item.branch): item.reason for item in plan.kept}
        self.assertIn(("local", "future/idea"), kept)
        self.assertIn(("remote", "future/idea"), kept)
        self.assertIn(("local", "dirty"), kept)
        self.assertIn(("remote", "dirty"), kept)
        self.assertEqual(kept[("local", "unique")], "merge is unproven")
        self.assertEqual(kept[("remote", "unique")], "merge is unproven")

    def test_dry_run_does_not_apply_selected_actions(self):
        root = Path("/repo")
        snapshot = cleanup.RepositorySnapshot(
            root=root,
            local_branches={"main": "m", "merged": "a"},
            remote_branches={"main": "m", "merged": "a"},
            worktrees=[
                cleanup.Worktree(root, "main", "m", True),
                cleanup.Worktree(root / "merged", "merged", "a", True),
            ],
        )
        repository = FakeRepository(snapshot, {("merged", "a"): self.ancestry}, 2)
        output = io.StringIO()

        cleanup.run_cleanup(repository, apply=False, include_remote=True, output=output)

        self.assertEqual(repository.events, [("ensure",), ("refresh",)])
        self.assertIn("Mode: dry-run", output.getvalue())
        self.assertIn("would fast-forward by 2 commit(s)", output.getvalue())
        self.assertIn("DELETE remote merged", output.getvalue())

    def test_remote_disabled_lists_each_skipped_branch_and_reason(self):
        snapshot = cleanup.RepositorySnapshot(
            root=Path("/repo"),
            local_branches={"main": "m"},
            remote_branches={
                "main": "m",
                "future/idea": "f",
                "merged": "a",
                "unproven": "u",
            },
            worktrees=[],
        )

        plan = cleanup.build_cleanup_plan(
            snapshot,
            lambda branch, oid: self.unproven,
            include_remote=False,
        )
        output = io.StringIO()
        cleanup.render_plan(
            plan,
            cleanup.BaseStatus("m", "m", 0),
            apply=False,
            include_remote=False,
            output=output,
        )

        self.assertEqual(
            [item.branch for item in plan.skipped], ["merged", "unproven"]
        )
        kept = {(item.scope, item.branch): item.reason for item in plan.kept}
        self.assertEqual(kept[("local", "main")], "protected base branch")
        self.assertEqual(kept[("remote", "main")], "protected base branch")
        self.assertEqual(
            kept[("remote", "future/idea")], "protected future branch"
        )
        self.assertIn("SKIP remote merged [remote cleanup disabled", output.getvalue())
        self.assertIn("SKIP remote unproven [remote cleanup disabled", output.getvalue())
        self.assertNotIn("SKIP remote main", output.getvalue())
        self.assertNotIn("SKIP remote future/idea", output.getvalue())

    def test_remote_deletion_requires_apply_and_remote(self):
        snapshot = cleanup.RepositorySnapshot(
            root=Path("/repo"),
            local_branches={"main": "m", "merged": "a"},
            remote_branches={"main": "m", "merged": "a"},
            worktrees=[],
        )
        checks = {("merged", "a"): self.ancestry}

        apply_without_remote = FakeRepository(snapshot, checks)
        cleanup.run_cleanup(
            apply_without_remote, apply=True, include_remote=False, output=io.StringIO()
        )
        self.assertIn(("delete-local", "merged"), apply_without_remote.events)
        self.assertFalse(
            any(event[0] == "delete-remote" for event in apply_without_remote.events)
        )

        preview_with_remote = FakeRepository(snapshot, checks)
        cleanup.run_cleanup(
            preview_with_remote, apply=False, include_remote=True, output=io.StringIO()
        )
        self.assertFalse(
            any(event[0] == "delete-remote" for event in preview_with_remote.events)
        )

        apply_with_remote = FakeRepository(snapshot, checks)
        cleanup.run_cleanup(
            apply_with_remote, apply=True, include_remote=True, output=io.StringIO()
        )
        self.assertIn(("delete-remote", ("merged",)), apply_with_remote.events)

    def test_exact_pr_head_is_required_for_squash_merge_evidence(self):
        pull_requests = [
            {
                "number": 1,
                "headRefName": "topic",
                "headRefOid": "old-tip",
                "baseRefName": "main",
                "mergeCommit": {"oid": "merge-1"},
                "mergedAt": "2026-07-01T00:00:00Z",
            },
            {
                "number": 2,
                "headRefName": "other",
                "headRefOid": "tip",
                "baseRefName": "main",
                "mergeCommit": {"oid": "merge-2"},
                "mergedAt": "2026-07-02T00:00:00Z",
            },
            {
                "number": 3,
                "headRefName": "topic",
                "headRefOid": "tip",
                "baseRefName": "release",
                "mergeCommit": {"oid": "merge-3"},
                "mergedAt": "2026-07-03T00:00:00Z",
            },
        ]
        self.assertIsNone(cleanup.find_exact_merged_pr("topic", "tip", pull_requests))

        pull_requests.append(
            {
                "number": 4,
                "headRefName": "topic",
                "headRefOid": "tip",
                "baseRefName": "main",
                "mergeCommit": {"oid": "merge-4"},
                "mergedAt": "2026-07-04T00:00:00Z",
            }
        )
        evidence = cleanup.find_exact_merged_pr("topic", "tip", pull_requests)
        self.assertEqual(evidence.kind, "pull-request")
        self.assertEqual(evidence.merge_oid, "merge-4")
        self.assertIn("#4", evidence.detail)

    def test_pr_merge_commit_must_still_be_in_origin_main(self):
        pull_requests = [
            {
                "number": 7,
                "headRefName": "topic",
                "headRefOid": "tip",
                "baseRefName": "main",
                "mergeCommit": {"oid": "merge-tip"},
                "mergedAt": "2026-07-07T00:00:00Z",
            }
        ]

        class MergeRepository(cleanup.GitRepository):
            def __init__(self, merge_is_current):
                super().__init__(Path("/repo"))
                self.merge_is_current = merge_is_current

            def _is_ancestor(self, older, newer):
                return older == "merge-tip" and self.merge_is_current

            def _merged_pull_requests(self, branch):
                return pull_requests, None

        current = MergeRepository(True).merge_check("topic", "tip")
        stale = MergeRepository(False).merge_check("topic", "tip")

        self.assertEqual(current.evidence.kind, "pull-request")
        self.assertIsNone(stale.evidence)
        self.assertIn("no longer contained", stale.reason)

    def test_local_delete_is_bound_to_the_reviewed_oid(self):
        runner = RecordingRunner()
        repository = cleanup.GitRepository(Path("/repo"), runner)
        repository._read_worktrees = lambda: []

        repository.delete_local_branch(
            cleanup.BranchAction("topic", "tip", self.pull_request.evidence)
        )
        repository.delete_local_branch(
            cleanup.BranchAction("normal", "tip", self.ancestry.evidence)
        )

        self.assertEqual(
            runner.calls[1][0],
            ["git", "update-ref", "-d", "refs/heads/topic", "tip"],
        )
        self.assertEqual(
            runner.calls[4][0],
            ["git", "update-ref", "-d", "refs/heads/normal", "tip"],
        )

    def test_remote_delete_uses_exact_oid_leases(self):
        runner = RecordingRunner()
        repository = cleanup.GitRepository(Path("/repo"), runner)
        actions = [
            cleanup.BranchAction("first", "oid-1", self.ancestry.evidence),
            cleanup.BranchAction("second", "oid-2", self.pull_request.evidence),
        ]

        repository._remote_url = "unused"
        repository.ensure_remote_delete_target = lambda: None
        repository.delete_remote_branches(actions)

        self.assertEqual(
            runner.calls[2][0],
            [
                "git",
                "push",
                "--atomic",
                "--force-with-lease=refs/heads/first:oid-1",
                "--force-with-lease=refs/heads/second:oid-2",
                "origin",
                "--delete",
                "first",
                "second",
            ],
        )
        self.assertEqual(
            runner.calls[3][0], ["git", "fetch", "--prune", "origin"]
        )

    def test_github_remote_parser_accepts_common_forms(self):
        self.assertEqual(
            cleanup.github_repository_from_remote("git@github.com:owner/repo.git"),
            "owner/repo",
        )
        self.assertEqual(
            cleanup.github_repository_from_remote("https://github.com/owner/repo"),
            "owner/repo",
        )
        self.assertIsNone(cleanup.github_repository_from_remote("/tmp/origin.git"))


class GitIntegrationTests(unittest.TestCase):
    def setUp(self):
        # Tests also run inside commit hooks; never inherit their index/worktree routing.
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0")
        isolation = patch.dict(os.environ, self.env, clear=True)
        isolation.start()
        self.addCleanup(isolation.stop)

    def run_command(self, args, cwd, check=True):
        process = subprocess.run(
            list(args),
            cwd=str(cwd),
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if check and process.returncode != 0:
            self.fail(
                "command failed: {}\nstdout: {}\nstderr: {}".format(
                    " ".join(args), process.stdout, process.stderr
                )
            )
        return process

    def git(self, repository, *args):
        return self.run_command(["git"] + list(args), repository)

    def commit_file(self, repository, branch, filename):
        self.git(repository, "switch", "-c", branch)
        (repository / filename).write_text(branch + "\n", encoding="utf-8")
        self.git(repository, "add", filename)
        self.git(repository, "commit", "-m", "add {}".format(branch))
        self.git(repository, "push", "-u", "origin", branch)
        self.git(repository, "switch", "main")
        self.git(repository, "merge", "--no-ff", branch, "-m", "merge {}".format(branch))
        self.git(repository, "push", "origin", "main")

    def local_branches(self, repository):
        process = self.git(
            repository, "for-each-ref", "--format=%(refname:short)", "refs/heads"
        )
        return set(process.stdout.splitlines())

    def remote_branches(self, repository):
        process = self.git(
            repository,
            "for-each-ref",
            "--format=%(refname:short)",
            "refs/remotes/origin",
        )
        return {
            branch[len("origin/") :]
            for branch in process.stdout.splitlines()
            if branch.startswith("origin/") and branch != "origin/HEAD"
        }

    def initialize_repository(self, temporary):
        origin = temporary / "origin.git"
        repository = temporary / "repository"
        self.run_command(["git", "init", "--bare", str(origin)], temporary)
        self.run_command(["git", "init", "-b", "main", str(repository)], temporary)
        self.git(repository, "config", "user.name", "Cleanup Test")
        self.git(repository, "config", "user.email", "cleanup@example.com")
        (repository / "README.md").write_text("baseline\n", encoding="utf-8")
        self.git(repository, "add", "README.md")
        self.git(repository, "commit", "-m", "baseline")
        self.git(repository, "remote", "add", "origin", str(origin))
        self.git(repository, "push", "-u", "origin", "main")
        return repository, origin

    def test_squash_merge_requires_exact_head_and_current_base(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, _ = self.initialize_repository(Path(directory))
            base = self.git(repo, "rev-parse", "HEAD").stdout.strip()
            self.git(repo, "switch", "-c", "topic")
            (repo / "topic.txt").write_text("feature\n")
            self.git(repo, "add", "topic.txt")
            self.git(repo, "commit", "-m", "topic")
            tip = self.git(repo, "rev-parse", "HEAD").stdout.strip()
            self.git(repo, "switch", "main")
            self.git(repo, "merge", "--squash", "topic")
            self.git(repo, "commit", "-m", "squashed")
            merged = self.git(repo, "rev-parse", "HEAD").stdout.strip()
            self.git(repo, "push", "origin", "main")
            repository = cleanup.GitRepository(repo)
            payload = [{"number": 42, "state": "MERGED", "headRefName": "topic",
                        "headRefOid": tip, "baseRefName": "main", "mergedAt": "2026-11-07",
                        "mergeCommit": {"oid": merged}}]
            repository._merged_pull_requests = lambda branch: (payload, None)
            self.assertEqual(repository.merge_check("topic", tip).evidence.kind, "pull-request")
            # An open PR still protects an ancestor; no deletion by ancestry alone.
            payload.append({"state": "OPEN"})
            self.assertIsNone(repository.merge_check("topic", tip).evidence)
            payload.pop()
            self.git(repo, "switch", "topic")
            (repo / "extra.txt").write_text("not reviewed\n")
            self.git(repo, "add", "extra.txt")
            self.git(repo, "commit", "-m", "after merge")
            new_tip = self.git(repo, "rev-parse", "HEAD").stdout.strip()
            self.assertIsNone(repository.merge_check("topic", new_tip).evidence)
            self.git(repo, "update-ref", "refs/remotes/origin/main", base)
            self.assertIsNone(repository.merge_check("topic", tip).evidence)

    def test_scoped_cleanup_preserves_other_branches_and_archives_deleted_tip(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, _ = self.initialize_repository(Path(directory))
            self.git(repo, "branch", "one")
            self.git(repo, "branch", "two")
            tip = self.git(repo, "rev-parse", "one").stdout.strip()
            repository = cleanup.GitRepository(repo)
            cleanup.run_cleanup(repository, True, False, io.StringIO(), ["one"])
            self.assertNotIn("one", self.local_branches(repo))
            self.assertIn("two", self.local_branches(repo))
            self.assertEqual(self.git(repo, "rev-parse", "refs/archive/branch-cleanup/"
                                     + repository.archive_id + "/heads/one").stdout.strip(), tip)

    def test_primary_and_locked_worktrees_are_protected(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, _ = self.initialize_repository(Path(directory))
            self.git(repo, "switch", "-c", "primary-topic")
            target = Path(directory) / "locked"
            self.git(repo, "worktree", "add", "-b", "locked-topic", str(target), "main")
            self.git(repo, "worktree", "lock", str(target))
            repository = cleanup.GitRepository(target)
            worktrees = repository._read_worktrees()
            self.assertTrue(all(not wt.clean for wt in worktrees))

    def test_resource_cleanup_failure_keeps_worktree_and_branch(self):
        with tempfile.TemporaryDirectory() as directory:
            repo, _ = self.initialize_repository(Path(directory))
            # A tracked project directory selects Stet's resource-cleanup adapter.
            (repo / "Stet.xcodeproj").mkdir()
            (repo / "Stet.xcodeproj/project.pbxproj").write_text("fixture\n")
            self.git(repo, "add", "Stet.xcodeproj")
            self.git(repo, "commit", "-m", "project")
            self.git(repo, "push", "origin", "main")
            target = Path(directory) / "topic"
            self.git(repo, "worktree", "add", "-b", "topic", str(target))
            repository = cleanup.GitRepository(repo)
            tip = self.git(repo, "rev-parse", "topic").stdout.strip()
            action = cleanup.WorktreeAction(target, "topic", tip,
                                            cleanup.MergeEvidence("ancestry", "merged"))
            original_run = repository.runner.run

            def fail_cleanup(args, cwd, check=True):
                if args[0] == "/bin/zsh":
                    raise cleanup.CommandError(args, subprocess.CompletedProcess(args, 2, "", "busy"))
                return original_run(args, cwd, check)

            repository.runner.run = fail_cleanup
            with self.assertRaises(cleanup.CommandError):
                repository.remove_worktree(action)
            self.assertTrue(target.exists())
            self.assertIn("topic", self.local_branches(repo))

    def test_local_delete_rejects_a_branch_that_moved(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            repository, _ = self.initialize_repository(temporary)
            old_oid = self.git(repository, "rev-parse", "HEAD").stdout.strip()
            self.git(repository, "branch", "topic")
            (repository / "second.txt").write_text("second\n", encoding="utf-8")
            self.git(repository, "add", "second.txt")
            self.git(repository, "commit", "-m", "second")
            new_oid = self.git(repository, "rev-parse", "HEAD").stdout.strip()
            self.git(repository, "branch", "-f", "topic", new_oid)
            action = cleanup.BranchAction(
                "topic", old_oid, cleanup.MergeEvidence("pull-request", "reviewed")
            )

            with self.assertRaises(cleanup.CommandError):
                cleanup.GitRepository(repository).delete_local_branch(action)

            self.assertEqual(
                self.git(repository, "rev-parse", "topic").stdout.strip(), new_oid
            )

    def test_local_delete_restores_a_branch_checked_out_during_the_race(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            repository, _ = self.initialize_repository(temporary)
            topic_oid = self.git(repository, "rev-parse", "HEAD").stdout.strip()
            self.git(repository, "branch", "topic")
            raced_worktree = temporary / "raced-worktree"

            class CheckoutRaceRepository(cleanup.GitRepository):
                def __init__(self, root, worktree):
                    super().__init__(root)
                    self.worktree = worktree
                    self.injected = False

                def _run_git(self, args, cwd=None, check=True):
                    if (
                        not self.injected
                        and list(args[:3]) == ["update-ref", "-d", "refs/heads/topic"]
                    ):
                        self.injected = True
                        self.runner.run(
                            ["git", "worktree", "add", str(self.worktree), "topic"],
                            cwd=self.root,
                        )
                    return super()._run_git(args, cwd=cwd, check=check)

            action = cleanup.BranchAction(
                "topic", topic_oid, cleanup.MergeEvidence("pull-request", "reviewed")
            )
            raced_repository = CheckoutRaceRepository(repository, raced_worktree)

            with self.assertRaises((cleanup.SafetyError, cleanup.CommandError)):
                raced_repository.delete_local_branch(action)

            self.assertEqual(
                self.git(repository, "rev-parse", "topic").stdout.strip(), topic_oid
            )
            self.assertEqual(
                self.git(raced_worktree, "symbolic-ref", "--short", "HEAD").stdout.strip(),
                "topic",
            )

    def test_remote_delete_rejects_a_branch_that_moved(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            repository, origin = self.initialize_repository(temporary)
            old_oid = self.git(repository, "rev-parse", "HEAD").stdout.strip()
            self.git(repository, "branch", "topic")
            self.git(repository, "push", "origin", "topic")
            (repository / "second.txt").write_text("second\n", encoding="utf-8")
            self.git(repository, "add", "second.txt")
            self.git(repository, "commit", "-m", "second")
            new_oid = self.git(repository, "rev-parse", "HEAD").stdout.strip()
            self.git(repository, "push", "origin", "main:topic")
            action = cleanup.BranchAction(
                "topic", old_oid, cleanup.MergeEvidence("ancestry", "reviewed")
            )

            with self.assertRaises(cleanup.CommandError):
                cleanup.GitRepository(repository).delete_remote_branches([action])

            remote_tip = self.run_command(
                ["git", "--git-dir", str(origin), "rev-parse", "refs/heads/topic"],
                temporary,
            ).stdout.strip()
            self.assertEqual(remote_tip, new_oid)

    def test_remote_delete_rejects_a_different_push_url(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            repository, _ = self.initialize_repository(temporary)
            other_origin = temporary / "other-origin.git"
            self.run_command(["git", "init", "--bare", str(other_origin)], temporary)
            self.git(repository, "config", "remote.origin.pushurl", str(other_origin))

            with self.assertRaises(cleanup.SafetyError):
                cleanup.GitRepository(repository).ensure_remote_delete_target()

    def test_end_to_end_cleanup_is_safe_and_repeatable(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            origin = temporary / "origin.git"
            repository = temporary / "repository"
            clean_worktree = temporary / "clean-worktree"
            dirty_worktree = temporary / "dirty-worktree"

            self.run_command(["git", "init", "--bare", str(origin)], temporary)
            self.run_command(["git", "init", "-b", "main", str(repository)], temporary)
            self.git(repository, "config", "user.name", "Cleanup Test")
            self.git(repository, "config", "user.email", "cleanup@example.com")
            (repository / "README.md").write_text("baseline\n", encoding="utf-8")
            (repository / ".gitignore").write_text("*.cache\n", encoding="utf-8")
            self.git(repository, "add", "README.md", ".gitignore")
            self.git(repository, "commit", "-m", "baseline")
            self.git(repository, "remote", "add", "origin", str(origin))
            self.git(repository, "push", "-u", "origin", "main")

            self.commit_file(repository, "merged-normal", "normal.txt")
            self.commit_file(repository, "merged-worktree", "worktree.txt")
            self.commit_file(repository, "dirty-merged", "dirty.txt")
            self.git(repository, "worktree", "add", str(clean_worktree), "merged-worktree")
            self.git(repository, "worktree", "add", str(dirty_worktree), "dirty-merged")
            (dirty_worktree / "generated.cache").write_text(
                "keep me\n", encoding="utf-8"
            )

            self.git(repository, "branch", "future/keep")
            self.git(repository, "switch", "-c", "unique")
            (repository / "unique.txt").write_text("unique\n", encoding="utf-8")
            self.git(repository, "add", "unique.txt")
            self.git(repository, "commit", "-m", "unique work")
            self.git(repository, "switch", "main")

            preview = self.run_command([sys.executable, str(SCRIPT_PATH)], repository)
            self.assertIn("Mode: dry-run", preview.stdout)
            self.assertIn("KEEP local future/keep", preview.stdout)
            self.assertIn("KEEP local dirty-merged", preview.stdout)
            self.assertTrue(clean_worktree.exists())
            self.assertIn("merged-normal", self.local_branches(repository))

            applied = self.run_command(
                [sys.executable, str(SCRIPT_PATH), "--apply"], repository
            )
            self.assertIn("Mode: apply", applied.stdout)
            branches = self.local_branches(repository)
            self.assertNotIn("merged-normal", branches)
            self.assertNotIn("merged-worktree", branches)
            self.assertIn("dirty-merged", branches)
            self.assertIn("future/keep", branches)
            self.assertIn("unique", branches)
            self.assertFalse(clean_worktree.exists())
            self.assertTrue(dirty_worktree.exists())

            remote_preview = self.run_command(
                [sys.executable, str(SCRIPT_PATH), "--remote"], repository
            )
            self.assertIn("DELETE remote merged-normal", remote_preview.stdout)
            self.assertIn("merged-normal", self.remote_branches(repository))

            remote_apply = self.run_command(
                [sys.executable, str(SCRIPT_PATH), "--apply", "--remote"], repository
            )
            self.assertIn("DELETE remote merged-normal", remote_apply.stdout)
            remote_branches = self.remote_branches(repository)
            self.assertNotIn("merged-normal", remote_branches)
            self.assertNotIn("merged-worktree", remote_branches)
            self.assertIn("dirty-merged", remote_branches)

            repeated = self.run_command(
                [sys.executable, str(SCRIPT_PATH), "--apply", "--remote"], repository
            )
            self.assertEqual(repeated.returncode, 0)
            self.assertIn("0 worktree(s), 0 local branch(es), 0 remote branch(es)", repeated.stdout)


if __name__ == "__main__":
    unittest.main()
