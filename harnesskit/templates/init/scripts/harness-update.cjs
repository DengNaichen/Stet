#!/usr/bin/env node
"use strict";

const { resolve } = require("node:path");

const {
	ARTIFACT_MANIFEST_PATH,
	canonicalJSONStringify,
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
const UPDATE_BASELINE_PATH = ".harnesskit/audit/state/update-baseline.json";
const RUN_STATE_PATH = ".harnesskit/audit/state/run-state.json";
const RECEIPTS_DIR = ".harnesskit/receipts";
const SHA256_PATTERN = /^[a-f0-9]{64}$/;
const SOURCE_COMMIT_PATTERN = /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/;
const UTC_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const COMPARE_ALLOWED_VIOLATIONS = new Set(["source_hash_mismatch", "source_unavailable"]);

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
	if (command === "read" || command === "compare") {
		const options = parseCommandOptions(argv.slice(1), new Set(["--root"]));
		const root = resolve(options["--root"] || process.cwd());
		const result = command === "read" ? readBaseline(root) : compareBaseline(root);
		process.stdout.write(canonicalJSONStringify(result));
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
