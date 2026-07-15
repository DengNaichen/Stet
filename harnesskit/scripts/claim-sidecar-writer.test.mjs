import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import {
	appendFile,
	lstat,
	mkdir,
	mkdtemp,
	readFile,
	readdir,
	writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import { test } from "node:test";

import { materializeInitTemplates } from "./init-materialize.mjs";

const artifact = "docs/ARCHITECTURE.md";
const sidecar = ".harnesskit/audit/claims/ARCHITECTURE.json";
const lock = ".harnesskit/audit/.claim-contract.lock";
const checklistBlockPattern =
	/<!--\s*harnesskit:todo-checklist:start\s*-->[\s\S]*?<!--\s*harnesskit:todo-checklist:end\s*-->\n?/g;

async function createTarget({ existingArchitecture } = {}) {
	const target = await mkdtemp(join(tmpdir(), "harnesskit-claim-writer-"));
	if (existingArchitecture !== undefined) {
		await mkdir(join(target, "docs"), { recursive: true });
		await writeFile(join(target, artifact), existingArchitecture);
	}
	const report = await materializeInitTemplates({ target });
	const verifierPath = join(target, "scripts", "claims-verify.cjs");
	const verifier = createRequire(import.meta.url)(verifierPath);
	return { target, report, verifierPath, verifier };
}

function writerArgs(target, extra = []) {
	return ["write-sidecar", "--artifact", artifact, "--stdin", "--root", target, ...extra];
}

function runWriter(target, verifierPath, input, args = writerArgs(target)) {
	return spawnSync(process.execPath, [verifierPath, ...args], {
		encoding: "utf8",
		input,
	});
}

function spawnWriter(target, verifierPath) {
	const child = spawn(process.execPath, [verifierPath, ...writerArgs(target)], {
		stdio: ["pipe", "pipe", "pipe"],
	});
	const stdout = [];
	const stderr = [];
	child.stdout.on("data", (chunk) => stdout.push(chunk));
	child.stderr.on("data", (chunk) => stderr.push(chunk));
	const completed = once(child, "close").then(([code, signal]) => ({
		code,
		signal,
		stdout: Buffer.concat(stdout).toString("utf8"),
		stderr: Buffer.concat(stderr).toString("utf8"),
	}));
	return { child, completed };
}

function canonicalJSON(value) {
	return `${JSON.stringify(value, null, 2)}\n`;
}

function sha256(value) {
	return createHash("sha256").update(value).digest("hex");
}

async function sidecarBytes(target) {
	return readFile(join(target, sidecar), "utf8");
}

async function assertNoWriterResidue(target) {
	const entries = await readdir(join(target, ".harnesskit/audit/claims"));
	assert.equal(entries.some((name) => name.includes(".tmp-")), false);
	await assert.rejects(lstat(join(target, lock)), { code: "ENOENT" });
}

test("waits for stdin EOF before atomically sealing the inventory", async () => {
	const { target, verifierPath, verifier } = await createTarget();
	const [id] = verifier.allocateClaimIds(target, artifact, 1);
	const source = "repository-source.txt";
	const contents = "repository evidence\n";
	await writeFile(join(target, source), contents);
	await appendFile(join(target, artifact), `\n- [${id}] observed statement\n`);
	const before = await sidecarBytes(target);

	const { child, completed } = spawnWriter(target, verifierPath);
	child.stdin.write('{"items":[');
	await new Promise((resolve) => setTimeout(resolve, 25));
	assert.equal(child.exitCode, null);
	assert.equal(await sidecarBytes(target), before);
	child.stdin.end(JSON.stringify({ id, kind: "observed", sources: [source] }) + "]}");

	const result = await completed;
	assert.equal(result.code, 0, result.stderr);
	const expected = {
		schema_version: 4,
		artifact,
		items: [{ id, kind: "observed", sources: [{ path: source, sha256: sha256(contents) }] }],
	};
	assert.equal(result.stdout, canonicalJSON(expected));
	assert.equal(await sidecarBytes(target), canonicalJSON(expected));
	assert.equal(verifier.verifyClaims(target).status, "passed");
	await assertNoWriterResidue(target);
});

test("canonicalizes unsorted observed and confirmed intent inventory from stdin", async () => {
	const { target, verifierPath, verifier } = await createTarget();
	const [observedId, intentId] = verifier.allocateClaimIds(target, artifact, 2);
	const sourceA = "source-a.txt";
	const sourceB = "source-b.txt";
	const contentsA = "alpha\n";
	const contentsB = "beta\n";
	await writeFile(join(target, sourceA), contentsA);
	await writeFile(join(target, sourceB), contentsB);
	await appendFile(
		join(target, artifact),
		`\n- [${intentId}] intent statement\n- [${observedId}] observed statement\n`,
	);
	const confirmationRef = ".harnesskit/audit/transcript/confirmations/test-architecture.json";
	verifier.writeUserConfirmation(target, {
		ref: confirmationRef,
		confirmed_by: "Test User",
		date: "2026-07-14",
		claim_ids: [intentId],
	});

	const inventory = [
		{
			id: intentId,
			kind: "intent",
			confirmed_by: { type: "user", ref: confirmationRef, date: "2026-07-14" },
		},
		{ id: observedId, kind: "observed", sources: [sourceB, sourceA] },
	];
	const result = runWriter(target, verifierPath, JSON.stringify(inventory));
	assert.equal(result.status, 0, result.stderr);
	const expected = {
		schema_version: 4,
		artifact,
		items: [
			{
				id: observedId,
				kind: "observed",
				sources: [
					{ path: sourceA, sha256: sha256(contentsA) },
					{ path: sourceB, sha256: sha256(contentsB) },
				],
			},
			{
				id: intentId,
				kind: "intent",
				confirmed_by: { type: "user", ref: confirmationRef, date: "2026-07-14" },
			},
		],
	};
	assert.equal(result.stdout, canonicalJSON(expected));
	assert.equal(await sidecarBytes(target), canonicalJSON(expected));
	assert.equal(verifier.verifyClaims(target).status, "passed");
});

test("accepts an empty direct inventory", async () => {
	const { target, verifierPath } = await createTarget();
	const result = runWriter(target, verifierPath, '{"items":[]}');
	assert.equal(result.status, 0, result.stderr);
	assert.equal(
		await sidecarBytes(target),
		canonicalJSON({ schema_version: 4, artifact, items: [] }),
	);
});

test("rejects invalid direct inventories without changing the sidecar", async () => {
	const { target, verifierPath, verifier } = await createTarget();
	const [id] = verifier.allocateClaimIds(target, artifact, 1);
	await writeFile(join(target, "source.txt"), "source\n");
	const before = await sidecarBytes(target);
	const cases = [
		["empty stdin", "", "stdin: invalid JSON"],
		["malformed JSON", "{", "stdin: invalid JSON"],
		["wrong envelope", "{}", "items must be an array"],
		[
			"duplicate ID",
			JSON.stringify([
				{ id, kind: "observed", sources: ["source.txt"] },
				{ id, kind: "observed", sources: ["source.txt"] },
			]),
			"duplicate claim ID",
		],
		[
			"unallocated ID",
			JSON.stringify([{ id: "ARCHITECTURE-9999", kind: "observed", sources: ["source.txt"] }]),
			"ID was not allocated",
		],
		[
			"unsafe source",
			JSON.stringify([{ id, kind: "observed", sources: ["../source.txt"] }]),
			"unsafe_path",
		],
		[
			"missing source",
			JSON.stringify([{ id, kind: "observed", sources: ["missing.txt"] }]),
			"missing",
		],
		[
			"invalid confirmation",
			JSON.stringify([
				{
					id,
					kind: "intent",
					confirmed_by: {
						type: "user",
						ref: ".harnesskit/audit/transcript/confirmations/missing.json",
						date: "2026-07-14",
					},
				},
			]),
			"confirmation ref missing",
		],
	];

	for (const [name, input, message] of cases) {
		const result = runWriter(target, verifierPath, input);
		assert.equal(result.status, 1, name);
		assert.match(result.stderr, new RegExp(message), name);
		assert.equal(await sidecarBytes(target), before, name);
		await assertNoWriterResidue(target);
	}

	const repeated = runWriter(
		target,
		verifierPath,
		'{"items":[]}',
		["write-sidecar", "--artifact", artifact, "--stdin", "--stdin", "--root", target],
	);
	assert.equal(repeated.status, 1);
	assert.match(repeated.stderr, /--stdin may be provided only once/);
	assert.equal(await sidecarBytes(target), before);
});

test("deterministically rejects the removed file-input interface", async () => {
	const { target, verifierPath } = await createTarget();
	const inputPath = ".harnesskit/audit/evidence/legacy-sidecar-input.json";
	await mkdir(join(target, ".harnesskit/audit/evidence"), { recursive: true });
	await writeFile(join(target, inputPath), '{"items":[]}\n');
	const before = await sidecarBytes(target);
	const result = runWriter(
		target,
		verifierPath,
		undefined,
		["write-sidecar", "--artifact", artifact, "--input", inputPath, "--root", target],
	);
	assert.equal(result.status, 1);
	assert.match(result.stderr, /unknown argument: --input/);
	assert.equal(await sidecarBytes(target), before);
});

test("reseals stale source hashes", async () => {
	const { target, verifierPath, verifier } = await createTarget();
	const [id] = verifier.allocateClaimIds(target, artifact, 1);
	const source = "mutable-source.txt";
	await writeFile(join(target, source), "v1\n");
	await appendFile(join(target, artifact), `\n- [${id}] observed statement\n`);
	const inventory = JSON.stringify([{ id, kind: "observed", sources: [source] }]);
	assert.equal(runWriter(target, verifierPath, inventory).status, 0);
	assert.equal(verifier.verifyClaims(target).status, "passed");

	await writeFile(join(target, source), "v2\n");
	const stale = verifier.verifyClaims(target);
	assert.equal(stale.status, "failed");
	assert.equal(stale.violations.some(({ code }) => code === "source_hash_mismatch"), true);

	assert.equal(runWriter(target, verifierPath, inventory).status, 0);
	assert.equal(verifier.verifyClaims(target).status, "passed");
});

test("serializes concurrent direct writers without torn output", async () => {
	const { target, verifierPath, verifier } = await createTarget();
	const [id] = verifier.allocateClaimIds(target, artifact, 1);
	await writeFile(join(target, "source-a.txt"), "alpha\n");
	await writeFile(join(target, "source-b.txt"), "beta\n");
	await appendFile(join(target, artifact), `\n- [${id}] observed statement\n`);

	const lockPath = join(target, lock);
	const holderScript = [
		'const fs = require("node:fs");',
		"const lockPath = process.argv[1];",
		"fs.mkdirSync(lockPath, { mode: 0o700 });",
		'fs.writeFileSync(`${lockPath}/owner.json`, JSON.stringify({ pid: process.pid }));',
		'process.stdout.write("ready\\n");',
		"setTimeout(() => fs.rmSync(lockPath, { recursive: true, force: true }), 100);",
	].join("");
	const holder = spawn(process.execPath, ["-e", holderScript, lockPath], {
		stdio: ["ignore", "pipe", "inherit"],
	});
	const holderCompleted = once(holder, "close");
	await once(holder.stdout, "data");

	const writerA = spawnWriter(target, verifierPath);
	const writerB = spawnWriter(target, verifierPath);
	writerA.child.stdin.end(JSON.stringify([{ id, kind: "observed", sources: ["source-a.txt"] }]));
	writerB.child.stdin.end(JSON.stringify([{ id, kind: "observed", sources: ["source-b.txt"] }]));
	const [resultA, resultB] = await Promise.all([writerA.completed, writerB.completed]);
	assert.equal(resultA.code, 0, resultA.stderr);
	assert.equal(resultB.code, 0, resultB.stderr);
	await holderCompleted;

	const finalSidecar = JSON.parse(await sidecarBytes(target));
	assert.equal(finalSidecar.items.length, 1);
	assert.equal(["source-a.txt", "source-b.txt"].includes(finalSidecar.items[0].sources[0].path), true);
	assert.equal(verifier.verifyClaims(target).status, "passed");
	await assertNoWriterResidue(target);
});

test("does not write when a process ends before stdin is complete", async () => {
	const { target, verifierPath } = await createTarget();
	const before = await sidecarBytes(target);
	const { child, completed } = spawnWriter(target, verifierPath);
	child.stdin.write('{"items":[');
	await new Promise((resolve) => setTimeout(resolve, 25));
	assert.equal(await sidecarBytes(target), before);
	child.kill("SIGTERM");
	const result = await completed;
	assert.equal(result.signal, "SIGTERM");
	assert.equal(await sidecarBytes(target), before);
	await assertNoWriterResidue(target);
});

test("materializes direct sealing for clean Bootstrap and selective Adopt", async () => {
	const bootstrap = await createTarget();
	await assert.rejects(lstat(join(bootstrap.target, ".harnesskit/audit/evidence")), { code: "ENOENT" });
	const manifest = bootstrap.verifier.loadArtifactManifest(bootstrap.target);
	const actualSidecars = (await readdir(join(bootstrap.target, ".harnesskit/audit/claims"))).sort();
	const expectedSidecars = manifest.claim_artifacts
		.map(({ sidecar: path }) => path.split("/").at(-1))
		.sort();
	assert.deepEqual(actualSidecars, expectedSidecars);
	for (const claimArtifact of manifest.claim_artifacts) {
		const result = runWriter(
			bootstrap.target,
			bootstrap.verifierPath,
			'{"items":[]}',
			[
				"write-sidecar",
				"--artifact",
				claimArtifact.path,
				"--stdin",
				"--root",
				bootstrap.target,
			],
		);
		assert.equal(result.status, 0, `${claimArtifact.path}: ${result.stderr}`);
		const path = join(bootstrap.target, ...claimArtifact.path.split("/"));
		const before = await readFile(path, "utf8");
		await writeFile(path, before.replace(checklistBlockPattern, ""));
	}
	assert.equal(bootstrap.verifier.verifyClaims(bootstrap.target, { final: true }).status, "passed");

	const original = "# Existing architecture\n\nHuman-authored context.\n";
	const adopt = await createTarget({ existingArchitecture: original });
	assert.equal(adopt.report.skipped_existing.includes(artifact), true);
	assert.equal(await readFile(join(adopt.target, artifact), "utf8"), original);
	const [id] = adopt.verifier.allocateClaimIds(adopt.target, artifact, 1);
	await writeFile(join(adopt.target, "source.txt"), "source\n");
	await appendFile(join(adopt.target, artifact), `\n- [${id}] adopted statement\n`);
	const result = runWriter(
		adopt.target,
		adopt.verifierPath,
		JSON.stringify({ items: [{ id, kind: "observed", sources: ["source.txt"] }] }),
	);
	assert.equal(result.status, 0, result.stderr);
	assert.equal(adopt.verifier.verifyClaims(adopt.target).status, "passed");
	await assert.rejects(lstat(join(adopt.target, ".harnesskit/audit/evidence")), { code: "ENOENT" });
});

test("Web frontend profile artifacts use independent Claim contracts", async () => {
	const target = await mkdtemp(join(tmpdir(), "harnesskit-frontend-claims-"));
	const report = await materializeInitTemplates({ target, profile: "web-frontend" });
	assert.deepEqual(report.conflicts, []);
	const verifierPath = join(target, "scripts", "claims-verify.cjs");
	const verifier = createRequire(import.meta.url)(verifierPath);
	const contracts = [
		{
			artifact: "docs/DESIGN_SYSTEM.md",
			namespace: "DESIGN-SYSTEM",
			sidecar: ".harnesskit/audit/claims/docs-DESIGN_SYSTEM.json",
			source: "design-system-source.txt",
		},
		{
			artifact: "docs/INTERACTION_DESIGN.md",
			namespace: "INTERACTION-DESIGN",
			sidecar: ".harnesskit/audit/claims/docs-INTERACTION_DESIGN.json",
			source: "interaction-design-source.txt",
		},
	];

	const allocated = [];
	for (const contract of contracts) {
		const [id] = verifier.allocateClaimIds(target, contract.artifact, 1);
		assert.equal(id, `${contract.namespace}-0001`);
		allocated.push(id);
		await writeFile(join(target, contract.source), `${contract.namespace} evidence\n`);
		await appendFile(join(target, contract.artifact), `\n- [${id}] tracked frontend statement\n`);
	}

	const crossNamespace = runWriter(
		target,
		verifierPath,
		JSON.stringify([{ id: allocated[0], kind: "observed", sources: [contracts[1].source] }]),
		[
			"write-sidecar",
			"--artifact",
			contracts[1].artifact,
			"--stdin",
			"--root",
			target,
		],
	);
	assert.equal(crossNamespace.status, 1);
	assert.match(crossNamespace.stderr, /invalid ID for namespace INTERACTION-DESIGN/);

	for (let index = 0; index < contracts.length; index += 1) {
		const contract = contracts[index];
		const result = runWriter(
			target,
			verifierPath,
			JSON.stringify([{ id: allocated[index], kind: "observed", sources: [contract.source] }]),
			[
				"write-sidecar",
				"--artifact",
				contract.artifact,
				"--stdin",
				"--root",
				target,
			],
		);
		assert.equal(result.status, 0, `${contract.artifact}: ${result.stderr}`);
		const sealed = JSON.parse(await readFile(join(target, contract.sidecar), "utf8"));
		assert.equal(sealed.artifact, contract.artifact);
		assert.deepEqual(sealed.items.map(({ id }) => id), [allocated[index]]);
	}

	assert.equal(verifier.verifyClaims(target).status, "passed");
});

test("repo-owned orchestration and owner skills use only direct inventory", async () => {
	const skillPaths = [
		"harnesskit-init",
		"harnesskit-fill-agents",
		"harnesskit-fill-architecture",
		"harnesskit-fill-design-system",
		"harnesskit-fill-development",
		"harnesskit-fill-rules",
		"harnesskit-fill-validation",
	];
	for (const skill of skillPaths) {
		const contents = await readFile(new URL(`../skills/${skill}/SKILL.md`, import.meta.url), "utf8");
		assert.equal(contents.includes("write-sidecar"), true, skill);
		assert.equal(contents.includes("--stdin"), true, skill);
		if (skill === "harnesskit-init") {
			assert.equal(contents.includes("claims-verify.cjs --help"), true, "init lacks the migration preflight");
		}
		for (const removed of ["--input", "sidecar-input", ".harnesskit/audit/evidence"]) {
			assert.equal(contents.includes(removed), false, `${skill} still contains ${removed}`);
		}
	}
});
