import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

import { materializeInitTemplates } from "./init-materialize.mjs";

const checklistBlockPattern =
	/<!--\s*harnesskit:todo-checklist:start\s*-->[\s\S]*?<!--\s*harnesskit:todo-checklist:end\s*-->\n?/g;

test("final Claim verification rejects authoring checklists until owner skills remove them", async () => {
	const target = await mkdtemp(join(tmpdir(), "harnesskit-final-verification-"));
	await materializeInitTemplates({ target });

	const require = createRequire(import.meta.url);
	const verifierPath = join(target, "scripts", "claims-verify.cjs");
	const verifier = require(verifierPath);

	assert.equal(verifier.verifyClaims(target).status, "passed");

	const failed = spawnSync(
		process.execPath,
		[verifierPath, "verify", "--final", "--json", "--root", target],
		{ encoding: "utf8" },
	);
	assert.equal(failed.status, 1);
	const failedReport = JSON.parse(failed.stdout);
	assert.equal(failedReport.status, "failed");
	assert.ok(failedReport.violations.length > 0);
	assert.ok(
		failedReport.violations.every(({ code }) => code === "authoring_checklist_remaining"),
	);

	const manifest = verifier.loadArtifactManifest(target);
	for (const artifact of manifest.claim_artifacts) {
		const path = join(target, ...artifact.path.split("/"));
		const before = await readFile(path, "utf8");
		const after = before.replace(checklistBlockPattern, "");
		assert.notEqual(after, before, `${artifact.path} should contain an authoring checklist`);
		await writeFile(path, after);
	}

	const passedReport = verifier.verifyClaims(target, { final: true });
	assert.equal(passedReport.status, "passed");
	assert.deepEqual(passedReport.violations, []);
});
