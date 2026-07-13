import assert from "node:assert/strict";
import { lstat, mkdir, mkdtemp, readFile, readlink, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { materializeInitTemplates } from "./init-materialize.mjs";

async function createFixture() {
	const root = await mkdtemp(join(tmpdir(), "harnesskit-init-companion-"));
	const source = join(root, "source");
	const target = join(root, "target");
	await mkdir(source, { recursive: true });
	await mkdir(target, { recursive: true });
	await writeFile(join(source, "AGENTS.md"), "template agents\n");
	return { source, target };
}

test("creates the exact Claude companion alias without a Claim inventory", async () => {
	const { source, target } = await createFixture();

	const report = await materializeInitTemplates({ source, target });

	assert.deepEqual(report.created, ["AGENTS.md", "CLAUDE.md"]);
	assert.deepEqual(report.skipped_existing, []);
	assert.deepEqual(report.conflicts, []);
	assert.equal((await lstat(join(target, "CLAUDE.md"))).isSymbolicLink(), true);
	assert.equal(await readlink(join(target, "CLAUDE.md")), "AGENTS.md");

	const manifest = JSON.parse(
		await readFile(new URL("../templates/init/.harnesskit/audit/artifact-manifest.json", import.meta.url), "utf8"),
	);
	assert.equal(manifest.claim_artifacts.some(({ path }) => path === "CLAUDE.md"), false);
});

test("preserves an existing user-owned Claude companion file", async () => {
	const { source, target } = await createFixture();
	const sentinel = "user-owned Claude guidance\n";
	await writeFile(join(target, "CLAUDE.md"), sentinel);

	const report = await materializeInitTemplates({ source, target });

	assert.deepEqual(report.created, ["AGENTS.md"]);
	assert.deepEqual(report.skipped_existing, ["CLAUDE.md"]);
	assert.deepEqual(report.conflicts, []);
	assert.equal(await readFile(join(target, "CLAUDE.md"), "utf8"), sentinel);
});

test("preserves an existing exact Claude companion alias", async () => {
	const { source, target } = await createFixture();
	await symlink("AGENTS.md", join(target, "CLAUDE.md"));

	const report = await materializeInitTemplates({ source, target });

	assert.deepEqual(report.created, ["AGENTS.md"]);
	assert.deepEqual(report.skipped_existing, ["CLAUDE.md"]);
	assert.deepEqual(report.conflicts, []);
	assert.equal(await readlink(join(target, "CLAUDE.md")), "AGENTS.md");
});

test("rejects wrong or unsafe Claude companion aliases", async () => {
	for (const actualTarget of ["README.md", "../AGENTS.md"]) {
		const { source, target } = await createFixture();
		await symlink(actualTarget, join(target, "CLAUDE.md"));

		const report = await materializeInitTemplates({ source, target });

		assert.deepEqual(report.conflicts, [
			{ path: "CLAUDE.md", reason: "target symlink must point to AGENTS.md" },
		]);
		assert.equal(await readlink(join(target, "CLAUDE.md")), actualTarget);
	}
});

test("rejects a non-file Claude companion shape", async () => {
	const { source, target } = await createFixture();
	await mkdir(join(target, "CLAUDE.md"));

	const report = await materializeInitTemplates({ source, target });

	assert.deepEqual(report.conflicts, [
		{
			path: "CLAUDE.md",
			reason: "target exists and is neither a regular file nor the expected symlink",
		},
	]);
});
