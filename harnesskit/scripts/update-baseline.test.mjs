import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { test } from "node:test";

const require = createRequire(import.meta.url);
const updateScript = fileURLToPath(new URL("../templates/init/scripts/harness-update.cjs", import.meta.url));
const update = require(updateScript);
const claims = require("../templates/init/scripts/claims-verify.cjs");

const SOURCE_COMMIT = "a".repeat(40);
const NEXT_SOURCE_COMMIT = "b".repeat(64);
const FIXED_TIME = "2026-07-15T08:09:10.123Z";
const BMP_ARTIFACT = "docs/\uE000.md";
const ASTRAL_ARTIFACT = "docs/\u{10000}.md";
const BMP_SIDECAR = ".harnesskit/audit/claims/\uE000.json";
const ASTRAL_SIDECAR = ".harnesskit/audit/claims/\u{10000}.json";
const USER_REF = ".harnesskit/audit/transcript/confirmations/update.json";
const OBSERVED_SOURCE = "src/evidence.bin";

function absolute(root, repoPath) {
	return join(root, ...repoPath.split("/"));
}

async function writeRepoFile(root, repoPath, contents) {
	const path = absolute(root, repoPath);
	await mkdir(dirname(path), { recursive: true });
	await writeFile(path, contents);
}

async function writeRepoJSON(root, repoPath, value) {
	await writeRepoFile(root, repoPath, claims.canonicalJSONStringify(value));
}

function sha256(contents) {
	return createHash("sha256").update(contents).digest("hex");
}

async function createFixture() {
	const root = await mkdtemp(join(tmpdir(), "stet-update-baseline-"));
	const sourceBytes = Buffer.from([0x62, 0x69, 0x6e, 0x0d, 0x0a, 0x00, 0xff]);
	await writeRepoFile(root, OBSERVED_SOURCE, sourceBytes);
	await writeRepoFile(
		root,
		BMP_ARTIFACT,
		"# BMP\n\n[BMP-0001]\n[BMP-0002]\n[BMP-0003]\n",
	);
	await writeRepoFile(root, ASTRAL_ARTIFACT, "# Astral\n\n[ASTRAL-0001]\n");
	await writeRepoFile(root, "docs/adr/0001-choice.md", "# Accepted choice\n");
	await writeRepoJSON(root, USER_REF, {
		schema_version: 1,
		confirmed_by: "Maintainer",
		date: "2026-07-15",
		claim_ids: ["ASTRAL-0001", "BMP-0001"],
	});
	await writeRepoJSON(root, claims.ARTIFACT_MANIFEST_PATH, {
		schema_version: 3,
		claim_namespaces: [
			{ namespace: "ASTRAL", display_name: "Astral", next_number: 2 },
			{ namespace: "BMP", display_name: "BMP", next_number: 4 },
		],
		claim_artifacts: [
			{ path: BMP_ARTIFACT, namespace: "BMP", sidecar: BMP_SIDECAR },
			{ path: ASTRAL_ARTIFACT, namespace: "ASTRAL", sidecar: ASTRAL_SIDECAR },
		],
	});
	await writeRepoJSON(root, BMP_SIDECAR, {
		schema_version: 4,
		artifact: BMP_ARTIFACT,
		items: [
			{
				id: "BMP-0001",
				kind: "intent",
				confirmed_by: { type: "user", ref: USER_REF, date: "2026-07-15" },
			},
			{
				id: "BMP-0002",
				kind: "intent",
				confirmed_by: { type: "adr", ref: "docs/adr/0001-choice.md", date: "2026-07-15" },
			},
			{
				id: "BMP-0003",
				kind: "observed",
				sources: [{ path: OBSERVED_SOURCE, sha256: sha256(sourceBytes) }],
			},
		],
	});
	await writeRepoJSON(root, ASTRAL_SIDECAR, {
		schema_version: 4,
		artifact: ASTRAL_ARTIFACT,
		items: [
			{
				id: "ASTRAL-0001",
				kind: "intent",
				confirmed_by: { type: "user", ref: USER_REF, date: "2026-07-15" },
			},
		],
	});
	await writeRepoJSON(root, ".harnesskit/audit/state/run-state.json", { schema_version: 1 });
	await writeRepoJSON(root, ".harnesskit/receipts/latest.json", { status: "passed" });
	return { root, sourceBytes };
}

function fixedClock() {
	return new Date(FIXED_TIME);
}

function baselineFixture() {
	return {
		schema_version: 1,
		source_commit: SOURCE_COMMIT,
		completed_at: FIXED_TIME,
		harness_snapshot: [
			{ path: claims.ARTIFACT_MANIFEST_PATH, sha256: "c".repeat(64) },
		],
	};
}

test("snapshot membership is exact, deduplicated, code-point sorted, and whole-file hashed", async () => {
	const { root } = await createFixture();
	const snapshot = update.computeHarnessSnapshot(root);
	const expectedPaths = [
		claims.ARTIFACT_MANIFEST_PATH,
		BMP_SIDECAR,
		ASTRAL_SIDECAR,
		USER_REF,
		BMP_ARTIFACT,
		ASTRAL_ARTIFACT,
	].sort(claims.compareText);

	assert.deepEqual(snapshot.map(({ path }) => path), expectedPaths);
	assert.equal(snapshot.filter(({ path }) => path === USER_REF).length, 1);
	assert.ok(expectedPaths.indexOf(BMP_ARTIFACT) < expectedPaths.indexOf(ASTRAL_ARTIFACT));
	for (const entry of snapshot) {
		assert.equal(entry.sha256, sha256(await readFile(absolute(root, entry.path))), entry.path);
	}
	for (const excluded of [
		"docs/adr/0001-choice.md",
		OBSERVED_SOURCE,
		".harnesskit/audit/state/run-state.json",
		".harnesskit/receipts/latest.json",
		update.UPDATE_BASELINE_PATH,
	]) {
		assert.equal(snapshot.some(({ path }) => path === excluded), false, excluded);
	}
});

test("baseline reader enforces strict schema, canonical bytes, paths, hashes, and ordering", () => {
	const valid = baselineFixture();
	const validBytes = Buffer.from(claims.canonicalJSONStringify(valid));
	assert.deepEqual(update.parseBaselineBytes(validBytes), valid);

	const cases = [
		["unknown field", { ...valid, extra: true }, /unknown field/],
		["bad source commit", { ...valid, source_commit: "A".repeat(40) }, /source_commit/],
		["noncanonical time", { ...valid, completed_at: "2026-07-15T08:09:10Z" }, /completed_at/],
		[
			"bad hash",
			{ ...valid, harness_snapshot: [{ path: claims.ARTIFACT_MANIFEST_PATH, sha256: "C".repeat(64) }] },
			/lowercase SHA-256/,
		],
		[
			"unsafe path",
			{
				...valid,
				harness_snapshot: [
					...valid.harness_snapshot,
					{ path: "../escape", sha256: "d".repeat(64) },
				],
			},
			/unsafe/,
		],
		[
			"excluded path",
			{
				...valid,
				harness_snapshot: [
					...valid.harness_snapshot,
					{ path: ".harnesskit/receipts/latest.json", sha256: "d".repeat(64) },
				],
			},
			/excluded/,
		],
		[
			"duplicate path",
			{ ...valid, harness_snapshot: [...valid.harness_snapshot, ...valid.harness_snapshot] },
			/unique and strictly/,
		],
	];
	for (const [name, value, expected] of cases) {
		assert.throws(
			() => update.parseBaselineBytes(Buffer.from(claims.canonicalJSONStringify(value))),
			expected,
			name,
		);
	}
	assert.throws(() => update.parseBaselineBytes(Buffer.from(JSON.stringify(valid))), /not in canonical form/);

	const unicode = {
		...valid,
		harness_snapshot: [
			...valid.harness_snapshot,
			{ path: BMP_ARTIFACT, sha256: "d".repeat(64) },
			{ path: ASTRAL_ARTIFACT, sha256: "e".repeat(64) },
		],
	};
	assert.deepEqual(
		update.parseBaselineBytes(Buffer.from(claims.canonicalJSONStringify(unicode))),
		unicode,
	);
	assert.throws(
		() =>
			update.parseBaselineBytes(
				Buffer.from(
					claims.canonicalJSONStringify({
						...unicode,
						harness_snapshot: [
							unicode.harness_snapshot[0],
							unicode.harness_snapshot[2],
							unicode.harness_snapshot[1],
						],
					}),
				),
			),
		/strictly code-point sorted/,
	);
});

test("finalize creates canonical state and compare reports deterministic drift", async () => {
	const { root } = await createFixture();
	const first = update.finalizeBaseline(root, SOURCE_COMMIT, { clock: fixedClock });
	assert.deepEqual(update.readBaseline(root), first);
	assert.equal(first.completed_at, FIXED_TIME);
	assert.equal(first.harness_snapshot.some(({ path }) => path === update.UPDATE_BASELINE_PATH), false);
	assert.deepEqual(update.compareBaseline(root), {
		schema_version: 1,
		matched: true,
		added: [],
		modified: [],
		removed: [],
	});

	await writeRepoFile(root, BMP_ARTIFACT, "# BMP edited\n\n[BMP-0001]\n[BMP-0002]\n[BMP-0003]\n");
	const drift = update.compareBaseline(root);
	assert.equal(drift.matched, false);
	assert.deepEqual(drift.modified.map(({ path }) => path), [BMP_ARTIFACT]);
	assert.deepEqual(drift.added, []);
	assert.deepEqual(drift.removed, []);
	assert.deepEqual(
		update.compareSnapshots(
			[
				{ path: "a", sha256: "a".repeat(64) },
				{ path: "b", sha256: "b".repeat(64) },
			],
			[
				{ path: "b", sha256: "c".repeat(64) },
				{ path: "c", sha256: "d".repeat(64) },
			],
		),
		{
			schema_version: 1,
			matched: false,
			added: [{ path: "c", sha256: "d".repeat(64) }],
			modified: [{ path: "b", baseline_sha256: "b".repeat(64), current_sha256: "c".repeat(64) }],
			removed: [{ path: "a", sha256: "a".repeat(64) }],
		},
	);
});

test("unsafe, symlinked, and excluded registered paths block snapshot generation", async (t) => {
	await t.test("unsafe manifest path", async () => {
		const { root } = await createFixture();
		const manifest = claims.loadArtifactManifest(root);
		manifest.claim_artifacts[0].path = "../escape.md";
		await writeRepoJSON(root, claims.ARTIFACT_MANIFEST_PATH, manifest);
		assert.throws(() => update.computeHarnessSnapshot(root), /Claim verifier gate failed: manifest_invalid/);
	});

	await t.test("symlinked artifact", async () => {
		const { root } = await createFixture();
		const outside = await mkdtemp(join(tmpdir(), "stet-update-outside-"));
		const outsideFile = join(outside, "outside.md");
		await writeFile(outsideFile, "# Outside\n");
		await rm(absolute(root, BMP_ARTIFACT));
		await symlink(outsideFile, absolute(root, BMP_ARTIFACT));
		assert.throws(() => update.computeHarnessSnapshot(root), /Claim verifier gate failed: artifact_unavailable/);
	});

	await t.test("registered receipt artifact", async () => {
		const { root } = await createFixture();
		const manifest = claims.loadArtifactManifest(root);
		const receiptArtifact = ".harnesskit/receipts/final.md";
		await writeRepoFile(root, receiptArtifact, await readFile(absolute(root, BMP_ARTIFACT)));
		manifest.claim_artifacts[0].path = receiptArtifact;
		manifest.claim_artifacts.sort((left, right) => claims.compareText(left.path, right.path));
		await writeRepoJSON(root, claims.ARTIFACT_MANIFEST_PATH, manifest);
		const sidecar = JSON.parse(await readFile(absolute(root, BMP_SIDECAR), "utf8"));
		sidecar.artifact = receiptArtifact;
		await writeRepoJSON(root, BMP_SIDECAR, sidecar);
		assert.throws(() => update.computeHarnessSnapshot(root), /excluded from Harness snapshots/);
	});
});

test("failed final gates and atomic writes preserve the prior baseline bytes", async (t) => {
	await t.test("source freshness final gate", async () => {
		const { root } = await createFixture();
		update.finalizeBaseline(root, SOURCE_COMMIT, { clock: fixedClock });
		const path = absolute(root, update.UPDATE_BASELINE_PATH);
		const before = await readFile(path);
		await writeRepoFile(root, OBSERVED_SOURCE, "stale source\n");
		assert.deepEqual(update.compareBaseline(root).matched, true);
		assert.throws(
			() => update.finalizeBaseline(root, NEXT_SOURCE_COMMIT, { clock: fixedClock }),
			/source_hash_mismatch/,
		);
		assert.deepEqual(await readFile(path), before);
	});

	await t.test("authoring checklist final gate", async () => {
		const { root } = await createFixture();
		update.finalizeBaseline(root, SOURCE_COMMIT, { clock: fixedClock });
		const path = absolute(root, update.UPDATE_BASELINE_PATH);
		const before = await readFile(path);
		await writeRepoFile(
			root,
			BMP_ARTIFACT,
			"<!-- harnesskit:todo-checklist:start -->\n<!-- harnesskit:todo-checklist:end -->\n[BMP-0001]\n[BMP-0002]\n[BMP-0003]\n",
		);
		assert.throws(
			() => update.finalizeBaseline(root, NEXT_SOURCE_COMMIT, { clock: fixedClock }),
			/authoring_checklist_remaining/,
		);
		assert.deepEqual(await readFile(path), before);
	});

	await t.test("clock side effects run before the final gate", async () => {
		const { root } = await createFixture();
		update.finalizeBaseline(root, SOURCE_COMMIT, { clock: fixedClock });
		const path = absolute(root, update.UPDATE_BASELINE_PATH);
		const before = await readFile(path);
		const sidecar = JSON.parse(await readFile(absolute(root, BMP_SIDECAR), "utf8"));
		assert.throws(
			() =>
				update.finalizeBaseline(root, NEXT_SOURCE_COMMIT, {
					clock() {
						claims.writeRepoFileAtomic(
							root,
							BMP_SIDECAR,
							claims.canonicalJSONStringify({ ...sidecar, unexpected: true }),
						);
						return new Date(FIXED_TIME);
					},
				}),
			/Claim verifier gate failed: schema_invalid/,
		);
		assert.deepEqual(await readFile(path), before);
	});

	await t.test("invalid existing baseline and injected atomic failure", async () => {
		const { root } = await createFixture();
		const path = absolute(root, update.UPDATE_BASELINE_PATH);
		const invalid = Buffer.from('{"schema_version":1}\n');
		await writeRepoFile(root, update.UPDATE_BASELINE_PATH, invalid);
		assert.throws(
			() => update.finalizeBaseline(root, NEXT_SOURCE_COMMIT, { clock: fixedClock }),
			/missing field/,
		);
		assert.deepEqual(await readFile(path), invalid);
		assert.throws(
			() =>
				claims.writeRepoFileAtomic(root, update.UPDATE_BASELINE_PATH, "replacement\n", {
					beforeRename() {
						throw new Error("injected write failure");
					},
				}),
			/injected write failure/,
		);
		assert.deepEqual(await readFile(path), invalid);
	});

	await t.test("lock cleanup cannot replace a successful callback result", async () => {
		const { root } = await createFixture();
		const result = claims.withClaimContractLock(root, () => "committed", {
			removeLock() {
				throw new Error("injected cleanup failure");
			},
		});
		assert.equal(result, "committed");
	});
});

test("CLI read, compare, and finalize reject caller-supplied snapshot state", async () => {
	const { root } = await createFixture();
	const finalize = spawnSync(
		process.execPath,
		[updateScript, "finalize", "--source-commit", SOURCE_COMMIT, "--root", root],
		{ encoding: "utf8" },
	);
	assert.equal(finalize.status, 0, finalize.stderr);
	assert.equal(JSON.parse(finalize.stdout).source_commit, SOURCE_COMMIT);

	for (const command of ["read", "compare"]) {
		const result = spawnSync(process.execPath, [updateScript, command, "--root", root], {
			encoding: "utf8",
		});
		assert.equal(result.status, 0, `${command}: ${result.stderr}`);
		assert.doesNotThrow(() => JSON.parse(result.stdout));
	}

	const before = await readFile(absolute(root, update.UPDATE_BASELINE_PATH));
	const injected = spawnSync(
		process.execPath,
		[
			updateScript,
			"finalize",
			"--source-commit",
			NEXT_SOURCE_COMMIT,
			"--snapshot",
			"caller-controlled",
			"--root",
			root,
		],
		{ encoding: "utf8" },
	);
	assert.equal(injected.status, 1);
	assert.match(injected.stderr, /unknown argument: --snapshot/);
	assert.deepEqual(await readFile(absolute(root, update.UPDATE_BASELINE_PATH)), before);
});
