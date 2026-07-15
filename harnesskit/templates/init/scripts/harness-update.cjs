#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const { realpathSync } = require("node:fs");
const { isAbsolute, resolve } = require("node:path");
const { TextDecoder } = require("node:util");

const {
	ARTIFACT_MANIFEST_PATH,
	canonicalJSONStringify,
	collectClaimInventory,
	compareText,
	hashRepoFile,
	isRepoRelativePath,
	loadArtifactManifest,
	readRepoFile,
	readRepoJSON,
	safeRegularFile,
	verifyClaims,
	withClaimContractLock,
	writeRepoFileAtomic,
} = require("./claims-verify.cjs");

const UPDATE_BASELINE_SCHEMA_VERSION = 1;
const COMPARE_REPORT_SCHEMA_VERSION = 1;
const DISCOVERY_REPORT_SCHEMA_VERSION = 1;
const UPDATE_BASELINE_PATH = ".harnesskit/audit/state/update-baseline.json";
const RUN_STATE_PATH = ".harnesskit/audit/state/run-state.json";
const RECEIPTS_DIR = ".harnesskit/receipts";
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const SOURCE_COMMIT_PATTERN = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
const UTC_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const COMPARE_ALLOWED_VIOLATIONS = new Set(["source_hash_mismatch", "source_unavailable"]);
const GIT_OID_PATTERN = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;

function isPlainObject(value) {
	return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertExactKeys(value, expected, pointer) {
	if (!isPlainObject(value)) throw new Error(`${pointer} must be an object`);
	const wanted = new Set(expected);
	for (const key of Object.keys(value)) {
		if (!wanted.has(key)) throw new Error(`${pointer} has unknown field ${key}`);
	}
	for (const key of expected) {
		if (!Object.hasOwn(value, key)) throw new Error(`${pointer} is missing field ${key}`);
	}
}

function assertKnownOptions(options, allowed, operation) {
	if (!isPlainObject(options)) throw new Error(`${operation} options must be an object`);
	for (const key of Object.keys(options)) {
		if (!allowed.has(key)) throw new Error(`${operation} has unknown option ${key}`);
	}
}

function isCanonicalUTCTimestamp(value) {
	if (typeof value !== "string" || !UTC_TIMESTAMP_PATTERN.test(value)) return false;
	const parsed = new Date(value);
	return !Number.isNaN(parsed.getTime()) && parsed.toISOString() === value;
}

function completedAtFromClock(clock) {
	if (typeof clock !== "function") throw new Error("clock must be a function");
	const value = clock();
	const parsed = value instanceof Date ? value : new Date(value);
	if (Number.isNaN(parsed.getTime())) throw new Error("clock returned an invalid timestamp");
	return parsed.toISOString();
}

function isExcludedSnapshotPath(path) {
	return (
		path === UPDATE_BASELINE_PATH ||
		path === RUN_STATE_PATH ||
		path === RECEIPTS_DIR ||
		path.startsWith(`${RECEIPTS_DIR}/`)
	);
}

function assertSnapshotPath(path, pointer) {
	if (!isRepoRelativePath(path)) throw new Error(`${pointer} is unsafe`);
	if (isExcludedSnapshotPath(path)) throw new Error(`${pointer} is excluded from Harness snapshots`);
}

function canonicalBaseline(value) {
	assertExactKeys(
		value,
		["schema_version", "source_commit", "completed_at", "harness_snapshot"],
		"baseline",
	);
	if (value.schema_version !== UPDATE_BASELINE_SCHEMA_VERSION) {
		throw new Error(`baseline.schema_version must equal ${UPDATE_BASELINE_SCHEMA_VERSION}`);
	}
	if (typeof value.source_commit !== "string" || !SOURCE_COMMIT_PATTERN.test(value.source_commit)) {
		throw new Error("baseline.source_commit must be a full lowercase 40- or 64-hex object ID");
	}
	if (!isCanonicalUTCTimestamp(value.completed_at)) {
		throw new Error("baseline.completed_at must be a canonical UTC RFC 3339 timestamp");
	}
	if (!Array.isArray(value.harness_snapshot)) {
		throw new Error("baseline.harness_snapshot must be an array");
	}

	const snapshot = [];
	let previousPath = null;
	for (let index = 0; index < value.harness_snapshot.length; index += 1) {
		const entry = value.harness_snapshot[index];
		const pointer = `baseline.harness_snapshot[${index}]`;
		assertExactKeys(entry, ["path", "sha256"], pointer);
		assertSnapshotPath(entry.path, `${pointer}.path`);
		if (previousPath !== null && compareText(previousPath, entry.path) >= 0) {
			throw new Error("baseline.harness_snapshot paths must be unique and strictly code-point sorted");
		}
		if (typeof entry.sha256 !== "string" || !SHA256_PATTERN.test(entry.sha256)) {
			throw new Error(`${pointer}.sha256 must be lowercase SHA-256 hex`);
		}
		previousPath = entry.path;
		snapshot.push({ path: entry.path, sha256: entry.sha256 });
	}
	if (!snapshot.some(({ path }) => path === ARTIFACT_MANIFEST_PATH)) {
		throw new Error(`baseline.harness_snapshot must include ${ARTIFACT_MANIFEST_PATH}`);
	}
	return {
		schema_version: UPDATE_BASELINE_SCHEMA_VERSION,
		source_commit: value.source_commit,
		completed_at: value.completed_at,
		harness_snapshot: snapshot,
	};
}

function parseBaselineBytes(contents) {
	const bytes = Buffer.isBuffer(contents) ? contents : Buffer.from(contents);
	let parsed;
	try {
		parsed = JSON.parse(bytes.toString("utf8"));
	} catch {
		throw new Error(`${UPDATE_BASELINE_PATH}: invalid JSON`);
	}
	const baseline = canonicalBaseline(parsed);
	if (!bytes.equals(Buffer.from(canonicalJSONStringify(baseline), "utf8"))) {
		throw new Error(`${UPDATE_BASELINE_PATH}: JSON is not in canonical form`);
	}
	return baseline;
}

function readBaseline(root = process.cwd()) {
	return parseBaselineBytes(readRepoFile(resolve(root), UPDATE_BASELINE_PATH));
}

function readBaselineIfPresent(root) {
	const file = safeRegularFile(root, UPDATE_BASELINE_PATH);
	if (!file.ok) {
		if (file.reason === "missing") return null;
		throw new Error(`${UPDATE_BASELINE_PATH}: ${file.reason}`);
	}
	return readBaseline(root);
}

function assertVerifierResult(report, { allowSourceFreshnessViolations = false } = {}) {
	if (!isPlainObject(report) || !Array.isArray(report.violations)) {
		throw new Error("Claim verifier returned an invalid report");
	}
	if (report.valid === true && report.status === "passed" && report.violations.length === 0) return;
	if (
		allowSourceFreshnessViolations &&
		report.valid === false &&
		report.status === "failed" &&
		report.violations.length > 0 &&
		report.violations.every(({ code }) => COMPARE_ALLOWED_VIOLATIONS.has(code))
	) {
		return;
	}
	const codes = [...new Set(report.violations.map(({ code }) => code).filter(Boolean))]
		.sort(compareText)
		.join(", ");
	throw new Error(`Claim verifier gate failed${codes ? `: ${codes}` : ""}`);
}

function addSnapshotPath(paths, path, owner) {
	assertSnapshotPath(path, `${owner} path ${path}`);
	paths.add(path);
}

function collectHarnessSnapshot(root) {
	const manifest = loadArtifactManifest(root);
	const paths = new Set();
	addSnapshotPath(paths, ARTIFACT_MANIFEST_PATH, "artifact manifest");
	for (const artifact of manifest.claim_artifacts) {
		addSnapshotPath(paths, artifact.path, `registered artifact ${artifact.path}`);
		addSnapshotPath(paths, artifact.sidecar, `registered sidecar ${artifact.sidecar}`);
		const sidecar = readRepoJSON(root, artifact.sidecar);
		for (const item of sidecar.items) {
			if (item.kind === "intent" && item.confirmed_by.type === "user") {
				addSnapshotPath(paths, item.confirmed_by.ref, `user confirmation for ${item.id}`);
			}
		}
	}
	return [...paths]
		.sort(compareText)
		.map((path) => ({ path, sha256: hashRepoFile(root, path) }));
}

function computeHarnessSnapshot(root = process.cwd(), options = {}) {
	assertKnownOptions(options, new Set(["allowSourceFreshnessViolations"]), "computeHarnessSnapshot");
	const absoluteRoot = resolve(root);
	assertVerifierResult(verifyClaims(absoluteRoot), {
		allowSourceFreshnessViolations: options.allowSourceFreshnessViolations === true,
	});
	return collectHarnessSnapshot(absoluteRoot);
}

function compareSnapshots(baselineSnapshot, currentSnapshot) {
	const before = new Map(baselineSnapshot.map(({ path, sha256 }) => [path, sha256]));
	const after = new Map(currentSnapshot.map(({ path, sha256 }) => [path, sha256]));
	const added = [];
	const modified = [];
	const removed = [];
	for (const { path, sha256 } of currentSnapshot) {
		if (!before.has(path)) added.push({ path, sha256 });
		else if (before.get(path) !== sha256) {
			modified.push({ path, baseline_sha256: before.get(path), current_sha256: sha256 });
		}
	}
	for (const { path, sha256 } of baselineSnapshot) {
		if (!after.has(path)) removed.push({ path, sha256 });
	}
	return {
		schema_version: COMPARE_REPORT_SCHEMA_VERSION,
		matched: added.length === 0 && modified.length === 0 && removed.length === 0,
		added,
		modified,
		removed,
	};
}

function compareBaseline(root = process.cwd()) {
	const absoluteRoot = resolve(root);
	const baseline = readBaseline(absoluteRoot);
	const current = computeHarnessSnapshot(absoluteRoot, { allowSourceFreshnessViolations: true });
	return compareSnapshots(baseline.harness_snapshot, current);
}

function runGit(root, args, allowedStatuses = new Set([0])) {
	const result = spawnSync("git", ["--no-optional-locks", "-C", root, ...args], {
		encoding: null,
		env: { ...process.env, GIT_OPTIONAL_LOCKS: "0", LC_ALL: "C" },
		maxBuffer: 16 * 1024 * 1024,
	});
	if (result.error) throw new Error(`Git command failed: ${result.error.message}`);
	if (!allowedStatuses.has(result.status)) {
		const detail = Buffer.isBuffer(result.stderr) ? result.stderr.toString("utf8").trim() : "";
		throw new Error(`Git command failed${detail ? `: ${detail}` : ""}`);
	}
	return { status: result.status, stdout: result.stdout || Buffer.alloc(0) };
}

function decodeGitUTF8(bytes, label) {
	try {
		return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
	} catch {
		throw new Error(`${label} contains invalid UTF-8`);
	}
}

function gitLine(root, args, label) {
	const value = decodeGitUTF8(runGit(root, args).stdout, label);
	return value.endsWith("\n") ? value.slice(0, -1) : value;
}

function assertGitRoot(root) {
	const topLevel = gitLine(root, ["rev-parse", "--show-toplevel"], "Git top-level");
	if (realpathSync(resolve(topLevel)) !== realpathSync(root)) {
		throw new Error("--root must be the Git worktree top-level");
	}
	if (gitLine(root, ["rev-parse", "--is-inside-work-tree"], "Git worktree state") !== "true") {
		throw new Error("--root must be an ordinary Git worktree");
	}
	if (gitLine(root, ["rev-parse", "--is-bare-repository"], "Git repository state") !== "false") {
		throw new Error("--root must be an ordinary Git worktree");
	}
}

function readFrozenHead(root) {
	const head = gitLine(root, ["rev-parse", "--verify", "HEAD^{commit}"], "Git HEAD");
	if (!GIT_OID_PATTERN.test(head)) throw new Error("Git HEAD must resolve to a full commit object ID");
	return head;
}

function assertCleanGitWorktree(root) {
	const status = runGit(root, [
		"status",
		"--porcelain=v1",
		"-z",
		"--untracked-files=all",
		"--ignore-submodules=none",
	]).stdout;
	if (status.length !== 0) throw new Error("Git worktree must be clean");
}

function assertBaselineSource(root, sourceCommit, frozenHead) {
	const type = runGit(root, ["cat-file", "-t", sourceCommit], new Set([0, 1, 128]));
	if (type.status !== 0) throw new Error("baseline.source_commit does not exist");
	if (decodeGitUTF8(type.stdout, "baseline source type").trim() !== "commit") {
		throw new Error("baseline.source_commit must name a commit object");
	}
	const ancestor = runGit(
		root,
		["merge-base", "--is-ancestor", sourceCommit, frozenHead],
		new Set([0, 1]),
	);
	if (ancestor.status === 1) throw new Error("baseline.source_commit must be an ancestor of frozen HEAD");
}

function isSafeGitPath(path) {
	if (typeof path !== "string" || path.length === 0 || path.includes("\u0000")) return false;
	if (isAbsolute(path) || path.startsWith("/")) return false;
	return path.split("/").every((segment) => segment !== "" && segment !== "." && segment !== "..");
}

function parseGitNameStatus(bytes) {
	if (bytes.length === 0) return [];
	if (bytes[bytes.length - 1] !== 0) throw new Error("Git diff name-status output is truncated");
	const fields = [];
	let start = 0;
	for (let index = 0; index < bytes.length; index += 1) {
		if (bytes[index] !== 0) continue;
		fields.push(decodeGitUTF8(bytes.subarray(start, index), "Git diff path"));
		start = index + 1;
	}
	const changes = [];
	for (let index = 0; index < fields.length; ) {
		const status = fields[index++];
		if (/^[AMD]$/.test(status)) {
			const path = fields[index++];
			if (!isSafeGitPath(path)) throw new Error("Git diff contains an unsafe path");
			changes.push({ status, path });
			continue;
		}
		const rename = /^R(\d{1,3})$/.exec(status);
		if (rename && Number(rename[1]) <= 100) {
			const oldPath = fields[index++];
			const newPath = fields[index++];
			if (!isSafeGitPath(oldPath) || !isSafeGitPath(newPath)) {
				throw new Error("Git diff contains an unsafe rename path");
			}
			changes.push({
				status: "R",
				old_path: oldPath,
				new_path: newPath,
				score: Number(rename[1]),
			});
			continue;
		}
		throw new Error(`Git diff contains unsupported status ${status || "<empty>"}`);
	}
	return changes;
}

function changePaths(change) {
	return change.status === "R" ? [change.old_path, change.new_path] : [change.path];
}

function changeSortPath(change) {
	return change.status === "R" ? change.new_path : change.path;
}

function sortGitChanges(changes) {
	return changes.sort(
		(left, right) =>
			compareText(changeSortPath(left), changeSortPath(right)) ||
			compareText(left.status, right.status) ||
			compareText(left.old_path || "", right.old_path || ""),
	);
}

function excludeInternalChanges(changes) {
	const filtered = [];
	for (const change of changes) {
		if (change.status !== "R") {
			if (!isExcludedSnapshotPath(change.path)) filtered.push(change);
			continue;
		}
		const oldExcluded = isExcludedSnapshotPath(change.old_path);
		const newExcluded = isExcludedSnapshotPath(change.new_path);
		if (oldExcluded && newExcluded) continue;
		if (oldExcluded) filtered.push({ status: "A", path: change.new_path });
		else if (newExcluded) filtered.push({ status: "D", path: change.old_path });
		else filtered.push(change);
	}
	return filtered;
}

function destinationPath(change) {
	if (change.status === "D") return null;
	return change.status === "R" ? change.new_path : change.path;
}

function acceptedSelfWritePath(root, change, acceptedHashes) {
	const path = destinationPath(change);
	if (path === null || !acceptedHashes.has(path)) return null;
	try {
		return hashRepoFile(root, path) === acceptedHashes.get(path) ? path : null;
	} catch {
		return null;
	}
}

function filterAcceptedSelfWrites(root, changes, acceptedHashes) {
	const filtered = [];
	for (const change of changes) {
		if (acceptedSelfWritePath(root, change, acceptedHashes) === null) {
			filtered.push(change);
		} else if (change.status === "R") {
			filtered.push({ status: "D", path: change.old_path });
		}
	}
	return filtered;
}

function hashAcceptedPaths(root, snapshot) {
	const current = [];
	for (const { path } of snapshot) {
		if (!safeRegularFile(root, path).ok) continue;
		try {
			current.push({ path, sha256: hashRepoFile(root, path) });
		} catch {
			// The verifier already reports unsafe or unreadable contract files.
		}
	}
	return current;
}

function isToolingSnapshotPath(path) {
	return (
		path === ARTIFACT_MANIFEST_PATH ||
		path.startsWith(".harnesskit/audit/claims/") ||
		path.startsWith(".harnesskit/audit/transcript/")
	);
}

function verifierDiagnostic(violation) {
	return { code: violation.code, path: violation.path, message: violation.message };
}

function compareDiagnostic(left, right) {
	return (
		compareText(left.path, right.path) ||
		compareText(left.code, right.code) ||
		compareText(left.message, right.message)
	);
}

function discoveryDrift(baselineSnapshot, currentSnapshot, blockingViolations) {
	const comparison = compareSnapshots(baselineSnapshot, currentSnapshot);
	const markdownReviewSeeds = [];
	const toolingBlockers = blockingViolations.map(verifierDiagnostic);
	for (const [change, entries] of [
		["added", comparison.added],
		["modified", comparison.modified],
		["removed", comparison.removed],
	]) {
		for (const { path } of entries) {
			if (isToolingSnapshotPath(path)) {
				toolingBlockers.push({
					code: `harness_tooling_${change}`,
					path,
					message: `accepted Harness tooling path was ${change}`,
				});
			} else {
				markdownReviewSeeds.push({ change, path });
			}
		}
	}
	markdownReviewSeeds.sort(
		(left, right) => compareText(left.path, right.path) || compareText(left.change, right.change),
	);
	const uniqueBlockers = new Map();
	for (const blocker of toolingBlockers) {
		uniqueBlockers.set(`${blocker.path}\u0000${blocker.code}\u0000${blocker.message}`, blocker);
	}
	return {
		markdownReviewSeeds,
		toolingBlockers: [...uniqueBlockers.values()].sort(compareDiagnostic),
	};
}

function locatorMapFromInventory(inventory) {
	return new Map(inventory.locators.map((entry) => [entry.path, entry]));
}

function freshnessDiagnostics(violations, locators) {
	return violations
		.filter(({ code }) => COMPARE_ALLOWED_VIOLATIONS.has(code))
		.map((violation) => {
			const route = locators.get(violation.path);
			return {
				...verifierDiagnostic(violation),
				claim_ids: route ? route.claim_ids : [],
				artifacts: route ? route.artifacts : [],
			};
		})
		.sort(compareDiagnostic);
}

function claimImpacts(changes, freshness, locators) {
	const impacts = new Map();
	function add(path, signal) {
		const route = locators.get(path);
		if (!route) return;
		const entry = impacts.get(path) || {
			path,
			signals: new Set(),
			claim_ids: route.claim_ids,
			artifacts: route.artifacts,
		};
		entry.signals.add(signal);
		impacts.set(path, entry);
	}
	for (const change of changes) for (const path of changePaths(change)) add(path, "git");
	for (const diagnostic of freshness) add(diagnostic.path, "freshness");
	return [...impacts.values()]
		.sort((left, right) => compareText(left.path, right.path))
		.map((entry) => ({ ...entry, signals: [...entry.signals].sort(compareText) }));
}

function unindexedChanges(changes, locators, harnessPaths) {
	const out = [];
	function isUnindexed(path) {
		return !locators.has(path) && !harnessPaths.has(path);
	}
	for (const change of changes) {
		if (change.status !== "R") {
			if (isUnindexed(change.path)) out.push(change);
			continue;
		}
		const oldUnindexed = isUnindexed(change.old_path);
		const newUnindexed = isUnindexed(change.new_path);
		if (oldUnindexed && newUnindexed) out.push(change);
		else if (oldUnindexed) out.push({ status: "D", path: change.old_path });
		else if (newUnindexed) out.push({ status: "A", path: change.new_path });
	}
	return sortGitChanges(out);
}

function discoverUpdate(root = process.cwd()) {
	const absoluteRoot = resolve(root);
	assertGitRoot(absoluteRoot);
	assertCleanGitWorktree(absoluteRoot);
	const frozenHead = readFrozenHead(absoluteRoot);
	const baseline = readBaseline(absoluteRoot);
	assertBaselineSource(absoluteRoot, baseline.source_commit, frozenHead);

	const verification = verifyClaims(absoluteRoot);
	const freshnessViolations = verification.violations.filter(({ code }) =>
		COMPARE_ALLOWED_VIOLATIONS.has(code),
	);
	const blockingViolations = verification.violations.filter(
		({ code }) => !COMPARE_ALLOWED_VIOLATIONS.has(code),
	);
	let inventory = { schema_version: 1, claims: [], locators: [] };
	if (blockingViolations.length === 0) {
		inventory = collectClaimInventory(absoluteRoot);
	} else {
		try {
			inventory = collectClaimInventory(absoluteRoot);
		} catch {
			// Existing structural verifier failures are already exposed as tooling blockers.
		}
	}
	const locators = locatorMapFromInventory(inventory);
	const acceptedHashes = new Map(
		baseline.harness_snapshot.map(({ path, sha256 }) => [path, sha256]),
	);
	const diffBytes = runGit(absoluteRoot, [
		"diff",
		"--name-status",
		"-z",
		"-M",
		baseline.source_commit,
		frozenHead,
	]).stdout;
	const gitChanges = sortGitChanges(
		filterAcceptedSelfWrites(
			absoluteRoot,
			excludeInternalChanges(parseGitNameStatus(diffBytes)),
			acceptedHashes,
		),
	);
	const currentSnapshot =
		blockingViolations.length === 0
			? computeHarnessSnapshot(absoluteRoot, { allowSourceFreshnessViolations: true })
			: hashAcceptedPaths(absoluteRoot, baseline.harness_snapshot);
	const drift = discoveryDrift(baseline.harness_snapshot, currentSnapshot, blockingViolations);
	const freshness = freshnessDiagnostics(freshnessViolations, locators);
	const harnessPaths = new Set([
		...baseline.harness_snapshot.map(({ path }) => path),
		...currentSnapshot.map(({ path }) => path),
	]);
	const report = {
		schema_version: DISCOVERY_REPORT_SCHEMA_VERSION,
		status: drift.toolingBlockers.length === 0 ? "ready" : "blocked",
		baseline_source_commit: baseline.source_commit,
		frozen_head: frozenHead,
		git_changes: gitChanges,
		freshness_diagnostics: freshness,
		claim_impacts: claimImpacts(gitChanges, freshness, locators),
		unindexed_changes: unindexedChanges(gitChanges, locators, harnessPaths),
		markdown_review_seeds: drift.markdownReviewSeeds,
		tooling_blockers: drift.toolingBlockers,
	};
	assertCleanGitWorktree(absoluteRoot);
	if (readFrozenHead(absoluteRoot) !== frozenHead) {
		throw new Error("Git HEAD changed during update discovery");
	}
	return report;
}

function finalizeBaseline(root = process.cwd(), sourceCommit, options = {}) {
	assertKnownOptions(options, new Set(["clock"]), "finalizeBaseline");
	if (typeof sourceCommit !== "string" || !SOURCE_COMMIT_PATTERN.test(sourceCommit)) {
		throw new Error("source_commit must be a full lowercase 40- or 64-hex object ID");
	}
	const absoluteRoot = resolve(root);
	const clock = options.clock || (() => new Date());
	return withClaimContractLock(absoluteRoot, () => {
		readBaselineIfPresent(absoluteRoot);
		const completedAt = completedAtFromClock(clock);
		assertVerifierResult(verifyClaims(absoluteRoot, { final: true }));
		const baseline = canonicalBaseline({
			schema_version: UPDATE_BASELINE_SCHEMA_VERSION,
			source_commit: sourceCommit,
			completed_at: completedAt,
			harness_snapshot: collectHarnessSnapshot(absoluteRoot),
		});
		writeRepoFileAtomic(absoluteRoot, UPDATE_BASELINE_PATH, canonicalJSONStringify(baseline));
		return baseline;
	});
}

function parseCommandOptions(args, allowed) {
	const options = {};
	for (let index = 0; index < args.length; index += 1) {
		const name = args[index];
		if (!allowed.has(name)) throw new Error(`unknown argument: ${name}`);
		if (Object.hasOwn(options, name)) throw new Error(`${name} may be provided only once`);
		const value = args[index + 1];
		if (!value || value.startsWith("--")) throw new Error(`${name} requires a value`);
		options[name] = value;
		index += 1;
	}
	return options;
}

function usage() {
	return [
		"Usage:",
		"  node scripts/harness-update.cjs read [--root <repo>]",
		"  node scripts/harness-update.cjs compare [--root <repo>]",
		"  node scripts/harness-update.cjs discover [--root <repo>]",
		"  node scripts/harness-update.cjs finalize --source-commit <full-oid> [--root <repo>]",
		"",
		"Harness snapshot membership and hashes are derived from repository files; callers cannot supply them.",
	].join("\n");
}

function main(argv = process.argv.slice(2)) {
	if (argv.includes("--help") || argv.includes("-h")) {
		process.stdout.write(`${usage()}\n`);
		return;
	}
	const command = argv[0];
	if (!command || command.startsWith("--")) throw new Error("a command is required");
	if (command === "read" || command === "compare" || command === "discover") {
		const options = parseCommandOptions(argv.slice(1), new Set(["--root"]));
		const root = resolve(options["--root"] || process.cwd());
		const result =
			command === "read"
				? readBaseline(root)
				: command === "compare"
					? compareBaseline(root)
					: discoverUpdate(root);
		process.stdout.write(canonicalJSONStringify(result));
		if (command === "discover" && result.status === "blocked") process.exitCode = 1;
		return;
	}
	if (command === "finalize") {
		const options = parseCommandOptions(argv.slice(1), new Set(["--source-commit", "--root"]));
		if (!options["--source-commit"]) throw new Error("--source-commit is required");
		const root = resolve(options["--root"] || process.cwd());
		process.stdout.write(canonicalJSONStringify(finalizeBaseline(root, options["--source-commit"])));
		return;
	}
	throw new Error(`unknown command: ${command}`);
}

module.exports = {
	UPDATE_BASELINE_PATH,
	canonicalBaseline,
	compareBaseline,
	compareSnapshots,
	computeHarnessSnapshot,
	discoverUpdate,
	finalizeBaseline,
	isExcludedSnapshotPath,
	parseBaselineBytes,
	readBaseline,
};

if (require.main === module) {
	try {
		main();
	} catch (error) {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	}
}
