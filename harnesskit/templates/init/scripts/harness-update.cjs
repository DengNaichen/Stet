#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const { readFileSync, realpathSync } = require("node:fs");
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
const RUN_STATE_SCHEMA_VERSION = 2;
const CHECKPOINT_COMPARE_SCHEMA_VERSION = 1;
const UPDATE_BASELINE_PATH = ".harnesskit/audit/state/update-baseline.json";
const RUN_STATE_PATH = ".harnesskit/audit/state/run-state.json";
const CHECKPOINT_TOOLING_DEPENDENCY_PATHS = [ARTIFACT_MANIFEST_PATH, UPDATE_BASELINE_PATH].sort(
	compareText,
);
const CHECKPOINT_TOOLING_DEPENDENCY_SET = new Set(CHECKPOINT_TOOLING_DEPENDENCY_PATHS);
const RECEIPTS_DIR = ".harnesskit/receipts";
const TRANSCRIPT_DIR = ".harnesskit/audit/transcript";
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const SOURCE_COMMIT_PATTERN = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
const UTC_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const COMPARE_ALLOWED_VIOLATIONS = new Set(["source_hash_mismatch", "source_unavailable"]);
const GIT_OID_PATTERN = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
const RUN_STATE_KEYS = [
	"schema_version",
	"workflow",
	"status",
	"frozen_head",
	"current_step",
	"current_artifact",
	"round",
	"question_declarations",
	"answers",
	"unsealed_outcomes",
	"resume_context",
	"dependency_scope",
	"relevant_inputs",
	"accepted_writes",
	"confirmations",
	"sealed_outcomes",
	"open_questions",
];
const CHECKPOINT_INPUT_KEYS = new Set([
	"current_step",
	"current_artifact",
	"round",
	"question_declarations",
	"answers",
	"unsealed_outcomes",
	"resume_context",
	"relevant_inputs",
	"accepted_writes",
	"confirmations",
	"sealed_outcomes",
	"open_questions",
]);
const RUN_STATE_STATUSES = new Set(["idle", "pending", "complete", "completed"]);
const QUESTION_ADMISSIONS = new Set(["observed", "intent", "manual_markdown"]);
const CHECKPOINT_ALLOWED_VERIFIER_VIOLATIONS = new Set([
	"source_hash_mismatch",
	"source_unavailable",
	"sidecar_item_missing",
	"markdown_token_missing",
]);
const INVALIDATED_ROUND_FIELDS = [
	"answers",
	"open_questions",
	"question_declarations",
	"resume_context",
	"unsealed_outcomes",
];

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

function hasNonWhitespace(value) {
	return typeof value === "string" && /\S/.test(value);
}

function canonicalJSONValue(value, pointer) {
	if (value === null || typeof value === "string" || typeof value === "boolean") return value;
	if (typeof value === "number") {
		if (!Number.isFinite(value)) throw new Error(`${pointer} must contain only finite JSON numbers`);
		return value;
	}
	if (Array.isArray(value)) {
		return value.map((entry, index) => canonicalJSONValue(entry, `${pointer}[${index}]`));
	}
	if (!isPlainObject(value)) throw new Error(`${pointer} must contain only JSON values`);
	return Object.fromEntries(
		Object.keys(value)
			.sort(compareText)
			.map((key) => [key, canonicalJSONValue(value[key], `${pointer}.${key}`)]),
	);
}

function canonicalJSONList(value, pointer) {
	if (!Array.isArray(value)) throw new Error(`${pointer} must be an array`);
	return value.map((entry, index) => canonicalJSONValue(entry, `${pointer}[${index}]`));
}

function canonicalHashedPaths(value, pointer) {
	if (!Array.isArray(value)) throw new Error(`${pointer} must be an array`);
	const out = [];
	let previousPath = null;
	for (let index = 0; index < value.length; index += 1) {
		const entry = value[index];
		const entryPointer = `${pointer}[${index}]`;
		assertExactKeys(entry, ["path", "sha256"], entryPointer);
		if (!isRepoRelativePath(entry.path)) throw new Error(`${entryPointer}.path is unsafe`);
		if (previousPath !== null && compareText(previousPath, entry.path) >= 0) {
			throw new Error(`${pointer} paths must be unique and strictly code-point sorted`);
		}
		if (typeof entry.sha256 !== "string" || !SHA256_PATTERN.test(entry.sha256)) {
			throw new Error(`${entryPointer}.sha256 must be lowercase SHA-256 hex`);
		}
		previousPath = entry.path;
		out.push({ path: entry.path, sha256: entry.sha256 });
	}
	return out;
}

function canonicalQuestionDeclarations(value, round, currentArtifact = null) {
	if (!Array.isArray(value)) throw new Error("run_state.question_declarations must be an array");
	if (value.length > 8) throw new Error("run_state.question_declarations must contain at most 8 questions");
	const declarations = value.map((entry, index) => {
		if (!isPlainObject(entry)) {
			throw new Error(`run_state.question_declarations[${index}] must be an object`);
		}
		const pointer = `run_state.question_declarations[${index}]`;
		if (!QUESTION_ADMISSIONS.has(entry.admission)) {
			throw new Error(`${pointer}.admission must be observed, intent, or manual_markdown`);
		}
		const expectedKeys =
			entry.admission === "manual_markdown"
				? ["admission", "artifact", "phase", "question"]
				: ["admission", "artifact", "question"];
		assertExactKeys(entry, expectedKeys, pointer);
		if (!isRepoRelativePath(entry.artifact)) throw new Error(`${pointer}.artifact is unsafe`);
		if (currentArtifact !== null && entry.artifact !== currentArtifact) {
			throw new Error(`run_state.question_declarations[${index}] belongs to another artifact`);
		}
		if (!isPlainObject(entry.question)) throw new Error(`${pointer}.question must be an object`);
		const question = canonicalJSONValue(entry.question, `${pointer}.question`);
		if (!Object.hasOwn(question, "round")) throw new Error(`${pointer}.question.round is required`);
		if (canonicalJSONStringify(question.round) !== canonicalJSONStringify(round)) {
			throw new Error(`${pointer}.question.round must match run_state.round`);
		}
		if (entry.admission === "observed") {
			if (
				!isPlainObject(question.claim) ||
				!Array.isArray(question.claim.rows) ||
				question.claim.rows.length === 0
			) {
				throw new Error(`${pointer}.question.claim.rows must contain the observed review batch`);
			}
		} else if (Object.hasOwn(question, "claim")) {
			throw new Error(`${pointer} mixes ${entry.admission} with observed claim rows`);
		}
		if (entry.admission === "manual_markdown" && entry.phase !== "reason") {
			throw new Error(`${pointer}.phase must equal reason`);
		}
		return entry.admission === "manual_markdown"
			? {
					admission: entry.admission,
					artifact: entry.artifact,
					phase: entry.phase,
					question,
				}
			: { admission: entry.admission, artifact: entry.artifact, question };
	});
	const admissions = new Set(declarations.map(({ admission }) => admission));
	if (admissions.size > 1) {
		throw new Error("observed, intent, and manual Markdown questions must use separate rounds");
	}
	if (admissions.has("observed") && declarations.length !== 1) {
		throw new Error("an observed review must be the only question in its artifact round");
	}
	return declarations;
}

function canonicalDependencyScope(value, currentArtifact) {
	if (value === null) return null;
	assertExactKeys(value, ["kind", "artifact"], "run_state.dependency_scope");
	if (value.kind !== "current_pending_round") {
		throw new Error("run_state.dependency_scope.kind must equal current_pending_round");
	}
	if (!isRepoRelativePath(value.artifact) || value.artifact !== currentArtifact) {
		throw new Error("run_state.dependency_scope.artifact must equal current_artifact");
	}
	return { kind: "current_pending_round", artifact: value.artifact };
}

function canonicalRunState(value) {
	assertExactKeys(value, RUN_STATE_KEYS, "run_state");
	if (value.schema_version !== RUN_STATE_SCHEMA_VERSION) {
		throw new Error(`run_state.schema_version must equal ${RUN_STATE_SCHEMA_VERSION}`);
	}
	if (value.workflow !== "bootstrap_or_adopt" && value.workflow !== "update") {
		throw new Error("run_state.workflow must equal bootstrap_or_adopt or update");
	}
	if (!RUN_STATE_STATUSES.has(value.status)) throw new Error("run_state.status is invalid");
	if (value.frozen_head !== null && !GIT_OID_PATTERN.test(value.frozen_head || "")) {
		throw new Error("run_state.frozen_head must be null or a full lowercase Git object ID");
	}
	if (value.current_step !== null && !hasNonWhitespace(value.current_step)) {
		throw new Error("run_state.current_step must be null or contain non-whitespace text");
	}
	if (value.current_artifact !== null && !isRepoRelativePath(value.current_artifact)) {
		throw new Error("run_state.current_artifact must be null or a safe repo-relative path");
	}
	const round = value.round === null ? null : canonicalJSONValue(value.round, "run_state.round");
	if (round !== null && !isPlainObject(round)) throw new Error("run_state.round must be null or an object");
	const questionDeclarations = canonicalQuestionDeclarations(
		value.question_declarations,
		round,
		value.current_artifact,
	);
	const dependencyScope = canonicalDependencyScope(value.dependency_scope, value.current_artifact);
	const state = {
		schema_version: RUN_STATE_SCHEMA_VERSION,
		workflow: value.workflow,
		status: value.status,
		frozen_head: value.frozen_head,
		current_step: value.current_step,
		current_artifact: value.current_artifact,
		round,
		question_declarations: questionDeclarations,
		answers: canonicalJSONList(value.answers, "run_state.answers"),
		unsealed_outcomes: canonicalJSONList(value.unsealed_outcomes, "run_state.unsealed_outcomes"),
		resume_context: canonicalJSONValue(value.resume_context, "run_state.resume_context"),
		dependency_scope: dependencyScope,
		relevant_inputs: canonicalHashedPaths(value.relevant_inputs, "run_state.relevant_inputs"),
		accepted_writes: canonicalHashedPaths(value.accepted_writes, "run_state.accepted_writes"),
		confirmations: canonicalJSONList(value.confirmations, "run_state.confirmations"),
		sealed_outcomes: canonicalJSONList(value.sealed_outcomes, "run_state.sealed_outcomes"),
		open_questions: canonicalJSONList(value.open_questions, "run_state.open_questions"),
	};
	if (!isPlainObject(state.resume_context)) throw new Error("run_state.resume_context must be an object");
	if (
		state.status === "idle" &&
		(state.round !== null || state.question_declarations.length !== 0 || state.dependency_scope !== null)
	) {
		throw new Error("an idle run_state cannot contain a waiting round");
	}
	if (state.workflow === "update" && state.status === "pending") {
		if (
			state.frozen_head === null ||
			state.current_step === null ||
			state.current_artifact === null ||
			state.round === null ||
			state.dependency_scope === null ||
			state.question_declarations.length === 0
		) {
			throw new Error("a pending Update checkpoint must contain frozen context and a complete round");
		}
		const relevantInputPaths = new Set(state.relevant_inputs.map(({ path }) => path));
		for (const path of CHECKPOINT_TOOLING_DEPENDENCY_PATHS) {
			if (!relevantInputPaths.has(path)) {
				throw new Error(`a pending Update checkpoint must bind tooling dependency ${path}`);
			}
		}
	}
	return state;
}

function parseRunStateBytes(contents, { requireUpdatePending = false } = {}) {
	const bytes = Buffer.isBuffer(contents) ? contents : Buffer.from(contents);
	let parsed;
	try {
		parsed = JSON.parse(bytes.toString("utf8"));
	} catch {
		throw new Error(`${RUN_STATE_PATH}: invalid JSON`);
	}
	if (isPlainObject(parsed) && parsed.schema_version === 1) {
		throw new Error(`${RUN_STATE_PATH}: legacy schema_version 1 is not an Update checkpoint and will not be migrated`);
	}
	const state = canonicalRunState(parsed);
	if (!bytes.equals(Buffer.from(canonicalJSONStringify(state), "utf8"))) {
		throw new Error(`${RUN_STATE_PATH}: JSON is not in canonical form`);
	}
	if (requireUpdatePending && !(state.workflow === "update" && state.status === "pending")) {
		throw new Error(`${RUN_STATE_PATH}: no pending Update checkpoint`);
	}
	return state;
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

function readRunStateIfPresent(root) {
	const file = safeRegularFile(root, RUN_STATE_PATH);
	if (!file.ok) {
		if (file.reason === "missing") return null;
		throw new Error(`${RUN_STATE_PATH}: ${file.reason}`);
	}
	return parseRunStateBytes(readRepoFile(root, RUN_STATE_PATH));
}

function readQuestionnaireCheckpoint(root = process.cwd()) {
	const absoluteRoot = resolve(root);
	const file = safeRegularFile(absoluteRoot, RUN_STATE_PATH);
	if (!file.ok) throw new Error(`${RUN_STATE_PATH}: ${file.reason}`);
	return parseRunStateBytes(readRepoFile(absoluteRoot, RUN_STATE_PATH), {
		requireUpdatePending: true,
	});
}

function normalizeCheckpointPaths(value, pointer) {
	if (!Array.isArray(value)) throw new Error(`${pointer} must be an array of repo-relative paths`);
	const paths = [];
	for (let index = 0; index < value.length; index += 1) {
		const path = value[index];
		if (!isRepoRelativePath(path)) throw new Error(`${pointer}[${index}] is unsafe`);
		if (path === RUN_STATE_PATH) throw new Error(`${pointer}[${index}] cannot name ${RUN_STATE_PATH}`);
		paths.push(path);
	}
	return [...new Set(paths)].sort(compareText);
}

function canonicalCheckpointInput(value) {
	if (!isPlainObject(value)) throw new Error("checkpoint input must be an object");
	for (const key of Object.keys(value)) {
		if (!CHECKPOINT_INPUT_KEYS.has(key)) throw new Error(`checkpoint input has unknown field ${key}`);
	}
	if (!hasNonWhitespace(value.current_step)) {
		throw new Error("checkpoint input current_step must contain non-whitespace text");
	}
	if (!isRepoRelativePath(value.current_artifact)) {
		throw new Error("checkpoint input current_artifact must be a safe repo-relative path");
	}
	if (!isPlainObject(value.round)) throw new Error("checkpoint input round must be an object");
	if (!Array.isArray(value.question_declarations) || value.question_declarations.length === 0) {
		throw new Error("checkpoint input question_declarations must contain a complete waiting round");
	}
	const field = (key, fallback) => (Object.hasOwn(value, key) ? value[key] : fallback);
	const roundValue = canonicalJSONValue(value.round, "checkpoint input.round");
	const resumeContext = canonicalJSONValue(field("resume_context", {}), "checkpoint input.resume_context");
	if (!isPlainObject(resumeContext)) throw new Error("checkpoint input.resume_context must be an object");
	return {
		current_step: value.current_step,
		current_artifact: value.current_artifact,
		round: roundValue,
		question_declarations: canonicalQuestionDeclarations(
			value.question_declarations,
			roundValue,
			value.current_artifact,
		),
		answers: canonicalJSONList(field("answers", []), "checkpoint input.answers"),
		unsealed_outcomes: canonicalJSONList(
			field("unsealed_outcomes", []),
			"checkpoint input.unsealed_outcomes",
		),
		resume_context: resumeContext,
		relevant_inputs: normalizeCheckpointPaths(
			field("relevant_inputs", []),
			"checkpoint input.relevant_inputs",
		),
		accepted_writes: normalizeCheckpointPaths(
			field("accepted_writes", []),
			"checkpoint input.accepted_writes",
		),
		confirmations: canonicalJSONList(field("confirmations", []), "checkpoint input.confirmations"),
		sealed_outcomes: canonicalJSONList(
			field("sealed_outcomes", []),
			"checkpoint input.sealed_outcomes",
		),
		open_questions: canonicalJSONList(field("open_questions", []), "checkpoint input.open_questions"),
	};
}

function assertCheckpointVerifierCompatible(root) {
	const verification = verifyClaims(root);
	const blockers = verification.violations.filter(
		({ code }) => !CHECKPOINT_ALLOWED_VERIFIER_VIOLATIONS.has(code),
	);
	if (blockers.length === 0) return;
	const codes = [...new Set(blockers.map(({ code }) => code))].sort(compareText).join(", ");
	throw new Error(`Claim verifier gate failed${codes ? `: ${codes}` : ""}`);
}

function currentUserConfirmationRefs(root, artifact) {
	const refs = new Set();
	const sidecar = readRepoJSON(root, artifact.sidecar);
	for (const item of sidecar.items) {
		if (item.kind !== "intent" || item.confirmed_by.type !== "user") continue;
		const ref = item.confirmed_by.ref;
		if (
			!isRepoRelativePath(ref) ||
			!ref.startsWith(`${TRANSCRIPT_DIR}/`) ||
			!ref.endsWith(".json") ||
			isExcludedSnapshotPath(ref)
		) {
			throw new Error(`${artifact.sidecar}: invalid user confirmation membership`);
		}
		refs.add(ref);
	}
	return refs;
}

function checkpointHarnessMembership(root, manifest, baseline, frozenHead, currentArtifact) {
	assertBaselineSource(root, baseline.source_commit, frozenHead);
	const baselineManifestEntry = baseline.harness_snapshot.find(
		({ path }) => path === ARTIFACT_MANIFEST_PATH,
	);
	if (
		!baselineManifestEntry ||
		hashRepoFile(root, ARTIFACT_MANIFEST_PATH) !== baselineManifestEntry.sha256
	) {
		throw new Error("artifact manifest differs from the accepted baseline topology");
	}
	const baselinePaths = new Set(baseline.harness_snapshot.map(({ path }) => path));
	for (const artifact of manifest.claim_artifacts) {
		for (const path of [artifact.path, artifact.sidecar]) {
			if (!baselinePaths.has(path) || isExcludedSnapshotPath(path)) {
				throw new Error(`accepted baseline does not contain registered Harness path ${path}`);
			}
		}
	}
	assertCheckpointVerifierCompatible(root);
	const membership = new Set([currentArtifact.path, currentArtifact.sidecar]);
	for (const ref of currentUserConfirmationRefs(root, currentArtifact)) membership.add(ref);
	return membership;
}

function hashCheckpointPaths(root, paths, pointer, membership = null) {
	return paths.map((path) => {
		if (pointer === "accepted write" && (path === ARTIFACT_MANIFEST_PATH || isExcludedSnapshotPath(path))) {
			throw new Error(`${pointer} path is excluded from Update checkpoint membership: ${path}`);
		}
		if (membership !== null && !membership.has(path)) {
			throw new Error(`${pointer} path is not accepted Harness membership: ${path}`);
		}
		return { path, sha256: hashRepoFile(root, path) };
	});
}

function buildQuestionnaireCheckpoint(root = process.cwd(), input, options = {}) {
	assertKnownOptions(options, new Set(["beforeRename"]), "buildQuestionnaireCheckpoint");
	const absoluteRoot = resolve(root);
	const inputProvider = typeof input === "function" ? input : () => input;
	return withClaimContractLock(absoluteRoot, () => {
		const existing = readRunStateIfPresent(absoluteRoot);
		if (existing !== null) {
			if (existing.workflow === "update" && existing.status === "pending") {
				throw new Error(
					`${RUN_STATE_PATH}: a pending Update checkpoint already exists; use checkpoint-read and checkpoint-compare`,
				);
			}
			if (existing.status === "pending") {
				throw new Error(`${RUN_STATE_PATH}: another workflow has a pending round`);
			}
		}

		const semantic = canonicalCheckpointInput(inputProvider());
		assertGitRoot(absoluteRoot);
		const frozenHead = readFrozenHead(absoluteRoot);
		const manifest = loadArtifactManifest(absoluteRoot);
		const registeredArtifact = manifest.claim_artifacts.find(
			({ path }) => path === semantic.current_artifact,
		);
		if (registeredArtifact === undefined) {
			throw new Error(`checkpoint artifact is not registered: ${semantic.current_artifact}`);
		}
		const currentArtifact = safeRegularFile(absoluteRoot, semantic.current_artifact);
		if (!currentArtifact.ok) {
			throw new Error(`${semantic.current_artifact}: ${currentArtifact.reason}`);
		}
		const baseline = readBaseline(absoluteRoot);
		const membership = checkpointHarnessMembership(
			absoluteRoot,
			manifest,
			baseline,
			frozenHead,
			registeredArtifact,
		);
		const relevantInputPaths = [...new Set([
			...semantic.relevant_inputs,
			...CHECKPOINT_TOOLING_DEPENDENCY_PATHS,
		])].sort(compareText);
		const relevantInputs = hashCheckpointPaths(
			absoluteRoot,
			relevantInputPaths,
			"relevant input",
		);
		const acceptedWrites = hashCheckpointPaths(
			absoluteRoot,
			semantic.accepted_writes,
			"accepted write",
			membership,
		);
		if (readFrozenHead(absoluteRoot) !== frozenHead) {
			throw new Error("Git HEAD changed while building the Update checkpoint");
		}
		const state = canonicalRunState({
			schema_version: RUN_STATE_SCHEMA_VERSION,
			workflow: "update",
			status: "pending",
			frozen_head: frozenHead,
			current_step: semantic.current_step,
			current_artifact: semantic.current_artifact,
			round: semantic.round,
			question_declarations: semantic.question_declarations,
			answers: semantic.answers,
			unsealed_outcomes: semantic.unsealed_outcomes,
			resume_context: semantic.resume_context,
			dependency_scope: {
				kind: "current_pending_round",
				artifact: semantic.current_artifact,
			},
			relevant_inputs: relevantInputs,
			accepted_writes: acceptedWrites,
			confirmations: semantic.confirmations,
			sealed_outcomes: semantic.sealed_outcomes,
			open_questions: semantic.open_questions,
		});
		writeRepoFileAtomic(absoluteRoot, RUN_STATE_PATH, canonicalJSONStringify(state), {
			beforeRename: options.beforeRename,
		});
		return state;
	});
}

function checkpointPathMismatches(root, entries) {
	return entries
		.map(({ path, sha256 }) => {
			const file = safeRegularFile(root, path);
			if (!file.ok) {
				return { path, reason: file.reason, expected_sha256: sha256, current_sha256: null };
			}
			let current;
			try {
				current = hashRepoFile(root, path);
			} catch {
				return { path, reason: "unreadable", expected_sha256: sha256, current_sha256: null };
			}
			if (current === sha256) return null;
			return {
				path,
				reason: "sha256_mismatch",
				expected_sha256: sha256,
				current_sha256: current,
			};
		})
		.filter(Boolean)
		.sort((left, right) => compareText(left.path, right.path) || compareText(left.reason, right.reason));
}

function checkpointToolingBlockers(mismatches) {
	return mismatches.map(({ path, reason }) => ({
		code: "checkpoint_tooling_dependency_mismatch",
		path,
		message: `saved Update checkpoint tooling dependency no longer matches (${reason})`,
	}));
}

function compareQuestionnaireCheckpoint(root = process.cwd()) {
	const absoluteRoot = resolve(root);
	const checkpoint = readQuestionnaireCheckpoint(absoluteRoot);
	assertGitRoot(absoluteRoot);
	const currentHead = readFrozenHead(absoluteRoot);
	const relevantInputMismatches = checkpointPathMismatches(
		absoluteRoot,
		checkpoint.relevant_inputs,
	);
	const toolingBlockers = checkpointToolingBlockers(
		relevantInputMismatches.filter(({ path }) => CHECKPOINT_TOOLING_DEPENDENCY_SET.has(path)),
	);
	const acceptedWriteMismatches = checkpointPathMismatches(
		absoluteRoot,
		checkpoint.accepted_writes,
	);
	if (readFrozenHead(absoluteRoot) !== currentHead) {
		throw new Error("Git HEAD changed during Update checkpoint comparison");
	}
	const frozenHeadMismatch =
		currentHead === checkpoint.frozen_head
			? null
			: { expected: checkpoint.frozen_head, current: currentHead };
	const matched =
		frozenHeadMismatch === null &&
		relevantInputMismatches.length === 0 &&
		acceptedWriteMismatches.length === 0 &&
		toolingBlockers.length === 0;
	const status = toolingBlockers.length > 0 ? "blocked" : matched ? "matched" : "invalidated";
	return {
		schema_version: CHECKPOINT_COMPARE_SCHEMA_VERSION,
		status,
		matched,
		frozen_head_mismatch: frozenHeadMismatch,
		relevant_input_mismatches: relevantInputMismatches,
		accepted_write_mismatches: acceptedWriteMismatches,
		tooling_blockers: toolingBlockers,
		invalidation_plan: {
			scope: toolingBlockers.length > 0 ? "tooling_blocked" : matched ? "none" : "current_pending_round",
			artifact: checkpoint.dependency_scope.artifact,
			invalidate_fields: matched || toolingBlockers.length > 0 ? [] : INVALIDATED_ROUND_FIELDS,
			preserve: {
				confirmations: checkpoint.confirmations,
				sealed_outcomes: checkpoint.sealed_outcomes,
			},
		},
	};
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

function parseCheckpointBuildOptions(args) {
	const options = {};
	let stdinCount = 0;
	for (let index = 0; index < args.length; index += 1) {
		const name = args[index];
		if (name === "--stdin") {
			stdinCount += 1;
			continue;
		}
		if (name !== "--root") throw new Error(`unknown argument: ${name}`);
		if (Object.hasOwn(options, name)) throw new Error(`${name} may be provided only once`);
		const value = args[index + 1];
		if (!value || value.startsWith("--")) throw new Error(`${name} requires a value`);
		options[name] = value;
		index += 1;
	}
	if (stdinCount !== 1) throw new Error("--stdin must be provided exactly once");
	return options;
}

function parseCheckpointInputBytes(contents) {
	try {
		return JSON.parse(Buffer.isBuffer(contents) ? contents.toString("utf8") : String(contents));
	} catch {
		throw new Error("checkpoint stdin contains invalid JSON");
	}
}

function usage() {
	return [
		"Usage:",
		"  node scripts/harness-update.cjs read [--root <repo>]",
		"  node scripts/harness-update.cjs compare [--root <repo>]",
		"  node scripts/harness-update.cjs discover [--root <repo>]",
		"  node scripts/harness-update.cjs checkpoint-build --stdin [--root <repo>]",
		"  node scripts/harness-update.cjs checkpoint-read [--root <repo>]",
		"  node scripts/harness-update.cjs checkpoint-compare [--root <repo>]",
		"  node scripts/harness-update.cjs finalize --source-commit <full-oid> [--root <repo>]",
		"",
		"Harness snapshot membership and checkpoint hashes are derived from repository files; callers cannot supply them.",
	].join("\n");
}

function main(argv = process.argv.slice(2)) {
	if (argv.includes("--help") || argv.includes("-h")) {
		process.stdout.write(`${usage()}\n`);
		return;
	}
	const command = argv[0];
	if (!command || command.startsWith("--")) throw new Error("a command is required");
	if (command === "checkpoint-build") {
		const options = parseCheckpointBuildOptions(argv.slice(1));
		const root = resolve(options["--root"] || process.cwd());
		const result = buildQuestionnaireCheckpoint(root, () =>
			parseCheckpointInputBytes(readFileSync(0, "utf8")),
		);
		process.stdout.write(canonicalJSONStringify(result));
		return;
	}
	if (command === "checkpoint-read" || command === "checkpoint-compare") {
		const options = parseCommandOptions(argv.slice(1), new Set(["--root"]));
		const root = resolve(options["--root"] || process.cwd());
		const result =
			command === "checkpoint-read"
				? readQuestionnaireCheckpoint(root)
				: compareQuestionnaireCheckpoint(root);
		process.stdout.write(canonicalJSONStringify(result));
		if (command === "checkpoint-compare" && result.matched === false) process.exitCode = 1;
		return;
	}
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
	RUN_STATE_PATH,
	RUN_STATE_SCHEMA_VERSION,
	UPDATE_BASELINE_PATH,
	buildQuestionnaireCheckpoint,
	canonicalBaseline,
	canonicalRunState,
	compareBaseline,
	compareQuestionnaireCheckpoint,
	compareSnapshots,
	computeHarnessSnapshot,
	discoverUpdate,
	finalizeBaseline,
	isExcludedSnapshotPath,
	parseBaselineBytes,
	parseRunStateBytes,
	readBaseline,
	readQuestionnaireCheckpoint,
};

if (require.main === module) {
	try {
		main();
	} catch (error) {
		process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
		process.exitCode = 1;
	}
}
