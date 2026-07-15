import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmod, mkdir, mkdtemp, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const require = createRequire(import.meta.url);
const updateScript = fileURLToPath(new URL("../templates/init/scripts/harness-update.cjs", import.meta.url));
const claimsScript = fileURLToPath(new URL("../templates/init/scripts/claims-verify.cjs", import.meta.url));
const update = require(updateScript);
const claims = require(claimsScript);

const SOURCE = "src/shared.txt";
const ARTIFACT_A = "docs/a.md";
const ARTIFACT_B = "docs/b.md";
const SIDECAR_A = ".harnesskit/audit/claims/a.json";
const SIDECAR_B = ".harnesskit/audit/claims/b.json";
const USER_REF = ".harnesskit/audit/transcript/confirmations/update.json";
const ADR_REF = "docs/adr/decision.md";
const POLICY_REF = "docs/policy.md";
const LEGACY = "legacy -- file.txt";
const OBSOLETE = "obsolete.txt";
const SOURCE_BYTES = Buffer.from("shared evidence\n");
const FIXED_TIME = "2026-07-15T08:09:10.123Z";

function absolute(root, repoPath) {
	return join(root, ...repoPath.split("/"));
}

function sha256(contents) {
	return createHash("sha256").update(contents).digest("hex");
}

async function writeRepoFile(root, repoPath, contents) {
	const path = absolute(root, repoPath);
	await mkdir(dirname(path), { recursive: true });
	await writeFile(path, contents);
}

async function writeRepoJSON(root, repoPath, value) {
	await writeRepoFile(root, repoPath, claims.canonicalJSONStringify(value));
}

function git(root, args, options = {}) {
	const result = spawnSync("git", ["-C", root, ...args], {
		encoding: options.encoding === null ? null : "utf8",
		input: options.input,
		env: options.env || process.env,
	});
	assert.equal(result.status, 0, `${args.join(" ")}: ${String(result.stderr)}`);
	return options.encoding === null ? result.stdout : result.stdout.trim();
}

function commitAll(root, message) {
	git(root, ["add", "-A"]);
	git(root, ["commit", "-m", message]);
	return git(root, ["rev-parse", "HEAD"]);
}

async function createFixture(t, prefix = "stet-update-discovery-") {
	const root = await mkdtemp(join(tmpdir(), prefix));
	t.after(() => rm(root, { recursive: true, force: true }));
	git(root, ["init"]);
	git(root, ["config", "user.name", "HarnessKit Test"]);
	git(root, ["config", "user.email", "harnesskit@example.test"]);
	await writeRepoFile(root, ".gitignore", "ignored.tmp\n");
	await writeRepoFile(root, SOURCE, SOURCE_BYTES);
	await writeRepoFile(root, ARTIFACT_A, "# A\n\n[A-0001]\n[A-0002]\n[A-0003]\n[A-0004]\n");
	await writeRepoFile(root, ARTIFACT_B, "# B\n\n[B-0001]\n[B-0002]\n");
	await writeRepoFile(root, ADR_REF, "# Decision\n");
	await writeRepoFile(root, POLICY_REF, "# Policy\n");
	await writeRepoFile(root, LEGACY, "unique rename body\n");
	await writeRepoFile(root, OBSOLETE, "DO-NOT-LEAK-OLD-BODY\n");
	await writeRepoJSON(root, USER_REF, {
		schema_version: 1,
		confirmed_by: "Maintainer",
		date: "2026-07-15",
		claim_ids: ["A-0003"],
	});
	await writeRepoJSON(root, claims.ARTIFACT_MANIFEST_PATH, {
		schema_version: 3,
		claim_namespaces: [
			{ namespace: "A", display_name: "A", next_number: 5 },
			{ namespace: "B", display_name: "B", next_number: 3 },
		],
		claim_artifacts: [
			{ path: ARTIFACT_A, namespace: "A", sidecar: SIDECAR_A },
			{ path: ARTIFACT_B, namespace: "B", sidecar: SIDECAR_B },
		],
	});
	await writeRepoJSON(root, SIDECAR_A, {
		schema_version: 4,
		artifact: ARTIFACT_A,
		items: [
			{ id: "A-0001", kind: "observed", sources: [{ path: SOURCE, sha256: sha256(SOURCE_BYTES) }] },
			{ id: "A-0002", kind: "observed", sources: [{ path: SOURCE, sha256: sha256(SOURCE_BYTES) }] },
			{
				id: "A-0003",
				kind: "intent",
				confirmed_by: { type: "user", ref: USER_REF, date: "2026-07-15" },
			},
			{
				id: "A-0004",
				kind: "intent",
				confirmed_by: { type: "adr", ref: ADR_REF, date: "2026-07-15" },
			},
		],
	});
	await writeRepoJSON(root, SIDECAR_B, {
		schema_version: 4,
		artifact: ARTIFACT_B,
		items: [
			{ id: "B-0001", kind: "observed", sources: [{ path: SOURCE, sha256: sha256(SOURCE_BYTES) }] },
			{
				id: "B-0002",
				kind: "intent",
				confirmed_by: { type: "policy", ref: POLICY_REF, date: "2026-07-15" },
			},
		],
	});
	const sourceCommit = commitAll(root, "source");
	update.finalizeBaseline(root, sourceCommit, { clock: () => new Date(FIXED_TIME) });
	const baselineCommit = commitAll(root, "baseline");
	return { root, sourceCommit, baselineCommit };
}

async function rewriteBaselineSource(root, sourceCommit) {
	const baseline = update.readBaseline(root);
	await writeRepoJSON(root, update.UPDATE_BASELINE_PATH, { ...baseline, source_commit: sourceCommit });
	commitAll(root, "rewrite baseline source");
}

test("Claim inventory is stable, structured, reverse-indexed, and verifier-compatible", async (t) => {
	const { root } = await createFixture(t);
	const before = claims.verifyClaims(root);
	const inventory = claims.collectClaimInventory(root);
	assert.deepEqual(claims.verifyClaims(root), before);
	assert.deepEqual(Object.keys(before), [
		"schema_version",
		"claim_schema",
		"status",
		"valid",
		"counts",
		"violations",
	]);
	assert.deepEqual(inventory.locators.find(({ path }) => path === SOURCE), {
		path: SOURCE,
		claim_ids: ["A-0001", "A-0002", "B-0001"],
		artifacts: [ARTIFACT_A, ARTIFACT_B],
	});
	for (const [path, claimId] of [
		[USER_REF, "A-0003"],
		[ADR_REF, "A-0004"],
		[POLICY_REF, "B-0002"],
	]) {
		assert.deepEqual(inventory.locators.find((entry) => entry.path === path)?.claim_ids, [claimId]);
	}
	assert.deepEqual(
		inventory.locators.map(({ path }) => path),
		inventory.locators.map(({ path }) => path).toSorted(claims.compareText),
	);
	await writeRepoFile(root, SOURCE, "stale evidence\n");
	assert.equal(claims.verifyClaims(root).violations.every(({ code }) => code === "source_hash_mismatch"), true);
	assert.deepEqual(claims.collectClaimInventory(root), inventory);
});

test("no-impact discovery is canonical, deterministic, and read-only", async (t) => {
	const { root, sourceCommit, baselineCommit } = await createFixture(t);
	const baselineBefore = await readFile(absolute(root, update.UPDATE_BASELINE_PATH));
	const indexPath = join(root, ".git", "index");
	const indexBefore = await readFile(indexPath);
	const indexStatBefore = await stat(indexPath);
	const first = update.discoverUpdate(root);
	const second = update.discoverUpdate(root);
	assert.deepEqual(first, second);
	assert.equal(first.status, "ready");
	assert.equal(first.baseline_source_commit, sourceCommit);
	assert.equal(first.frozen_head, baselineCommit);
	for (const key of [
		"git_changes",
		"freshness_diagnostics",
		"claim_impacts",
		"unindexed_changes",
		"markdown_review_seeds",
		"tooling_blockers",
	]) {
		assert.deepEqual(first[key], [], key);
	}
	const cli = spawnSync(process.execPath, [updateScript, "discover", "--root", root], { encoding: "utf8" });
	assert.equal(cli.status, 0, cli.stderr);
	assert.equal(cli.stdout, claims.canonicalJSONStringify(first));
	assert.deepEqual(await readFile(absolute(root, update.UPDATE_BASELINE_PATH)), baselineBefore);
	assert.deepEqual(await readFile(indexPath), indexBefore);
	assert.equal((await stat(indexPath)).mtimeMs, indexStatBefore.mtimeMs);
	assert.equal(git(root, ["status", "--porcelain=v1", "--untracked-files=all"]), "");
});

test("preflight rejects staged, unstaged, untracked, non-repository, and dirty submodule state", async (t) => {
	const ordinary = await mkdtemp(join(tmpdir(), "stet-update-nonrepo-"));
	t.after(() => rm(ordinary, { recursive: true, force: true }));
	assert.throws(() => update.discoverUpdate(ordinary), /Git command failed/);

	for (const scenario of ["staged", "unstaged", "untracked"]) {
		await t.test(scenario, async (st) => {
			const { root } = await createFixture(st, `stet-update-${scenario}-`);
			if (scenario === "staged") {
				await writeRepoFile(root, "staged.txt", "dirty\n");
				git(root, ["add", "staged.txt"]);
			} else if (scenario === "unstaged") {
				await writeRepoFile(root, SOURCE, "dirty\n");
			} else {
				await writeRepoFile(root, "untracked.txt", "dirty\n");
			}
			assert.throws(() => update.discoverUpdate(root), /worktree must be clean/);
		});
	}

	await t.test("ignored untracked is allowed", async (st) => {
		const { root } = await createFixture(st, "stet-update-ignored-");
		await writeRepoFile(root, "ignored.tmp", "allowed\n");
		assert.equal(update.discoverUpdate(root).status, "ready");
	});

	await t.test("dirty submodule", async (st) => {
		const { root } = await createFixture(st, "stet-update-submodule-host-");
		const child = await mkdtemp(join(tmpdir(), "stet-update-submodule-child-"));
		st.after(() => rm(child, { recursive: true, force: true }));
		git(child, ["init"]);
		git(child, ["config", "user.name", "HarnessKit Test"]);
		git(child, ["config", "user.email", "harnesskit@example.test"]);
		await writeRepoFile(child, "tracked.txt", "clean\n");
		commitAll(child, "child source");
		git(root, ["-c", "protocol.file.allow=always", "submodule", "add", child, "vendor/sub"]);
		commitAll(root, "add submodule");
		await writeRepoFile(join(root, "vendor/sub"), "tracked.txt", "dirty\n");
		assert.throws(() => update.discoverUpdate(root), /worktree must be clean/);
	});
});

test("baseline source must exist, name a commit, and be an ancestor", async (t) => {
	await t.test("missing", async (st) => {
		const { root } = await createFixture(st, "stet-update-missing-source-");
		await rewriteBaselineSource(root, "f".repeat(40));
		assert.throws(() => update.discoverUpdate(root), /does not exist/);
	});
	await t.test("blob", async (st) => {
		const { root } = await createFixture(st, "stet-update-blob-source-");
		const blob = git(root, ["rev-parse", `HEAD:${claims.ARTIFACT_MANIFEST_PATH}`]);
		await rewriteBaselineSource(root, blob);
		assert.throws(() => update.discoverUpdate(root), /commit object/);
	});
	await t.test("nonancestor", async (st) => {
		const { root } = await createFixture(st, "stet-update-nonancestor-");
		const tree = git(root, ["rev-parse", "HEAD^{tree}"]);
		const unrelated = git(root, ["commit-tree", tree], { input: "unrelated\n" });
		await rewriteBaselineSource(root, unrelated);
		assert.throws(() => update.discoverUpdate(root), /must be an ancestor/);
	});
});

test("Git net diff preserves A/M/D/R paths, rename score, and reverse-routes freshness", async (t) => {
	const { root } = await createFixture(t);
	const renamed = "renamed -- space\nfile.txt";
	const added = "notes/new file\nline.txt";
	await mkdir(dirname(absolute(root, renamed)), { recursive: true });
	await rename(absolute(root, LEGACY), absolute(root, renamed));
	await rm(absolute(root, OBSOLETE));
	await writeRepoFile(root, added, "new body\n");
	await writeRepoFile(root, SOURCE, "changed evidence\n");
	commitAll(root, "net changes");
	const report = update.discoverUpdate(root);
	assert.deepEqual(report.git_changes.find(({ path }) => path === added), { status: "A", path: added });
	assert.deepEqual(report.git_changes.find(({ path }) => path === OBSOLETE), { status: "D", path: OBSOLETE });
	assert.deepEqual(report.git_changes.find(({ path }) => path === SOURCE), { status: "M", path: SOURCE });
	assert.deepEqual(report.git_changes.find(({ status }) => status === "R"), {
		status: "R",
		old_path: LEGACY,
		new_path: renamed,
		score: 100,
	});
	assert.equal(report.freshness_diagnostics.length, 3);
	for (const diagnostic of report.freshness_diagnostics) {
		assert.equal(diagnostic.code, "source_hash_mismatch");
		assert.deepEqual(diagnostic.claim_ids, ["A-0001", "A-0002", "B-0001"]);
		assert.deepEqual(diagnostic.artifacts, [ARTIFACT_A, ARTIFACT_B]);
	}
	assert.deepEqual(report.claim_impacts.find(({ path }) => path === SOURCE)?.signals, ["freshness", "git"]);
	assert.equal(report.unindexed_changes.length, 3);
	assert.equal(JSON.stringify(report).includes("DO-NOT-LEAK-OLD-BODY"), false);
	assert.deepEqual(update.discoverUpdate(root), report);
});

test("an indexed rename routes the old locator and emits the new path as unindexed", async (t) => {
	const { root } = await createFixture(t, "stet-update-indexed-rename-");
	const renamedSource = "src/renamed-source.txt";
	await rename(absolute(root, SOURCE), absolute(root, renamedSource));
	commitAll(root, "rename indexed source");
	const report = update.discoverUpdate(root);
	assert.deepEqual(report.git_changes, [
		{ status: "R", old_path: SOURCE, new_path: renamedSource, score: 100 },
	]);
	assert.deepEqual(report.claim_impacts, [
		{
			path: SOURCE,
			signals: ["freshness", "git"],
			claim_ids: ["A-0001", "A-0002", "B-0001"],
			artifacts: [ARTIFACT_A, ARTIFACT_B],
		},
	]);
	assert.deepEqual(report.unindexed_changes, [{ status: "A", path: renamedSource }]);
});

test("accepted self-writes are exact-hash filtered while Markdown and tooling drift remain", async (t) => {
	await t.test("accepted self-write", async (st) => {
		const { root, sourceCommit } = await createFixture(st, "stet-update-self-write-");
		await writeRepoFile(root, ARTIFACT_A, "# Accepted edit\n\n[A-0001]\n[A-0002]\n[A-0003]\n[A-0004]\n");
		update.finalizeBaseline(root, sourceCommit, { clock: () => new Date(FIXED_TIME) });
		commitAll(root, "accepted Harness write");
		const report = update.discoverUpdate(root);
		assert.equal(report.status, "ready");
		assert.deepEqual(report.git_changes, []);
		assert.deepEqual(report.markdown_review_seeds, []);
	});

	await t.test("accepted rename keeps the ordinary old-path deletion", async (st) => {
		const { root } = await createFixture(st, "stet-update-self-write-rename-");
		const ordinaryOldPath = "docs/ordinary-old.md";
		await rename(absolute(root, ARTIFACT_A), absolute(root, ordinaryOldPath));
		const historicalCommit = commitAll(root, "ordinary historical path");
		await rename(absolute(root, ordinaryOldPath), absolute(root, ARTIFACT_A));
		update.finalizeBaseline(root, historicalCommit, { clock: () => new Date(FIXED_TIME) });
		commitAll(root, "accepted Harness rename");
		const report = update.discoverUpdate(root);
		assert.equal(report.status, "ready");
		assert.deepEqual(report.git_changes, [{ status: "D", path: ordinaryOldPath }]);
		assert.deepEqual(report.unindexed_changes, [{ status: "D", path: ordinaryOldPath }]);
		assert.deepEqual(report.markdown_review_seeds, []);
	});

	await t.test("unaccepted Markdown", async (st) => {
		const { root } = await createFixture(st, "stet-update-markdown-drift-");
		await writeRepoFile(root, ARTIFACT_A, "# Manual edit\n\n[A-0001]\n[A-0002]\n[A-0003]\n[A-0004]\n");
		commitAll(root, "manual Markdown");
		const report = update.discoverUpdate(root);
		assert.equal(report.status, "ready");
		assert.deepEqual(report.markdown_review_seeds, [{ change: "modified", path: ARTIFACT_A }]);
		assert.deepEqual(report.tooling_blockers, []);
	});

	for (const [name, path, mutate] of [
		["manifest", claims.ARTIFACT_MANIFEST_PATH, async (root) => {
			const value = JSON.parse(await readFile(absolute(root, claims.ARTIFACT_MANIFEST_PATH), "utf8"));
			value.claim_namespaces[0].display_name = "Changed A";
			await writeRepoJSON(root, claims.ARTIFACT_MANIFEST_PATH, value);
		}],
		["sidecar", SIDECAR_A, async (root) => {
			const bytes = await readFile(absolute(root, SIDECAR_A));
			await writeRepoFile(root, SIDECAR_A, Buffer.concat([bytes, Buffer.from("\n")]));
		}],
		["user confirmation", USER_REF, async (root) => {
			const value = JSON.parse(await readFile(absolute(root, USER_REF), "utf8"));
			value.confirmed_by = "Another maintainer";
			await writeRepoJSON(root, USER_REF, value);
		}],
	]) {
		await t.test(`${name} drift blocks`, async (st) => {
			const { root } = await createFixture(st, `stet-update-${name.replaceAll(" ", "-")}-`);
			await mutate(root);
			commitAll(root, `${name} drift`);
			const report = update.discoverUpdate(root);
			assert.equal(report.status, "blocked");
			assert.equal(
				report.tooling_blockers.some(
					({ code, path: blockerPath }) => code === "harness_tooling_modified" && blockerPath === path,
				),
				true,
			);
			const cli = spawnSync(process.execPath, [updateScript, "discover", "--root", root], { encoding: "utf8" });
			assert.equal(cli.status, 1);
			assert.equal(cli.stdout, claims.canonicalJSONStringify(report));
		});
	}

	await t.test("missing sidecar is a report blocker", async (st) => {
		const { root } = await createFixture(st, "stet-update-sidecar-missing-");
		await rm(absolute(root, SIDECAR_A));
		commitAll(root, "remove sidecar");
		const report = update.discoverUpdate(root);
		assert.equal(report.status, "blocked");
		assert.equal(report.tooling_blockers.some(({ code }) => code === "sidecar_unavailable"), true);
		assert.equal(
			report.tooling_blockers.some(({ code }) => code === "harness_tooling_removed"),
			true,
		);
	});
});

test("ADR/policy inputs route as ordinary changes and internal state stays excluded", async (t) => {
	const { root } = await createFixture(t);
	await writeRepoFile(root, ADR_REF, "# Changed decision\n");
	await writeRepoFile(root, POLICY_REF, "# Changed policy\n");
	await writeRepoJSON(root, ".harnesskit/audit/state/run-state.json", { schema_version: 1, pending: true });
	await writeRepoJSON(root, ".harnesskit/receipts/latest.json", { status: "passed" });
	commitAll(root, "ordinary inputs and internal state");
	const report = update.discoverUpdate(root);
	assert.equal(report.status, "ready");
	assert.deepEqual(report.tooling_blockers, []);
	assert.deepEqual(report.claim_impacts.find(({ path }) => path === ADR_REF)?.claim_ids, ["A-0004"]);
	assert.deepEqual(report.claim_impacts.find(({ path }) => path === POLICY_REF)?.claim_ids, ["B-0002"]);
	assert.equal(
		report.git_changes.some(({ path }) => path?.includes("run-state") || path?.includes("receipts")),
		false,
	);
});

test("inventory exceptions without verifier blockers are never downgraded", async (t) => {
	const { root } = await createFixture(t, "stet-update-inventory-error-");
	const cacheKey = require.resolve(updateScript);
	const originalCollector = claims.collectClaimInventory;
	let isolatedUpdate;
	try {
		claims.collectClaimInventory = () => {
			throw new Error("synthetic inventory I/O failure");
		};
		delete require.cache[cacheKey];
		isolatedUpdate = require(updateScript);
	} finally {
		claims.collectClaimInventory = originalCollector;
		delete require.cache[cacheKey];
		require(updateScript);
	}
	assert.throws(() => isolatedUpdate.discoverUpdate(root), /synthetic inventory I\/O failure/);
});

test("a final HEAD recheck rejects races without emitting a CLI report", async (t) => {
	const { root } = await createFixture(t, "stet-update-head-race-");
	const bin = await mkdtemp(join(tmpdir(), "stet-update-git-wrapper-"));
	t.after(() => rm(bin, { recursive: true, force: true }));
	const wrapper = join(bin, "git");
	const counter = join(bin, "count");
	await writeFile(
		wrapper,
		`#!/bin/sh\nif [ "$1" = "--no-optional-locks" ]; then shift; fi\nif [ "$1" = "-C" ] && [ "$3" = "rev-parse" ] && [ "$4" = "--verify" ] && [ "$5" = "HEAD^{commit}" ]; then\n  count=0\n  if [ -f "$RACE_COUNT_FILE" ]; then count=$("$REAL_GIT" hash-object "$RACE_COUNT_FILE" >/dev/null 2>&1; sed -n '1p' "$RACE_COUNT_FILE"); fi\n  count=$((count + 1))\n  printf '%s\\n' "$count" > "$RACE_COUNT_FILE"\n  if [ "$count" -eq 2 ]; then "$REAL_GIT" -C "$2" commit --allow-empty -m race >/dev/null 2>&1; fi\nfi\nexec "$REAL_GIT" --no-optional-locks "$@"\n`,
	);
	await chmod(wrapper, 0o755);
	const realGit = spawnSync("sh", ["-c", "command -v git"], { encoding: "utf8" }).stdout.trim();
	const env = {
		...process.env,
		PATH: `${bin}:${process.env.PATH}`,
		REAL_GIT: realGit,
		RACE_COUNT_FILE: counter,
	};
	const cli = spawnSync(process.execPath, [updateScript, "discover", "--root", root], { encoding: "utf8", env });
	assert.equal(cli.status, 1);
	assert.equal(cli.stdout, "");
	assert.match(cli.stderr, /HEAD changed during update discovery/);
});
