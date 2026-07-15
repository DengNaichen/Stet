import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { lstat, mkdir, mkdtemp, readFile, readdir, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { materializeInitTemplates } from "./init-materialize.mjs";

const materializerPath = fileURLToPath(new URL("./init-materialize.mjs", import.meta.url));
const baseManifestURL = new URL(
	"../templates/init/.harnesskit/audit/artifact-manifest.json",
	import.meta.url,
);
const checklistBlockPattern =
	/<!--\s*harnesskit:todo-checklist:start\s*-->[\s\S]*?<!--\s*harnesskit:todo-checklist:end\s*-->\n?/g;
const baseCreatedGolden = [
	".gitignore",
	".harnesskit/audit/artifact-manifest.json",
	".harnesskit/audit/claims/AGENTS.json",
	".harnesskit/audit/claims/ARCHITECTURE.json",
	".harnesskit/audit/claims/docs-DEVELOPMENT.json",
	".harnesskit/audit/claims/docs-rules-CODING.json",
	".harnesskit/audit/claims/docs-rules-PRODUCT_SENSE.json",
	".harnesskit/audit/claims/docs-rules-RELIABILITY.json",
	".harnesskit/audit/claims/docs-rules-SECURITY.json",
	".harnesskit/audit/claims/verification.json",
	".harnesskit/audit/state/run-state.json",
	".harnesskit/audit/transcript/README.md",
	".harnesskit/validation.json",
	"AGENTS.md",
	"CLAUDE.md",
	"docs/ARCHITECTURE.md",
	"docs/DEVELOPMENT.md",
	"docs/VALIDATION.md",
	"docs/rules/CODING.md",
	"docs/rules/PRODUCT_SENSE.md",
	"docs/rules/RELIABILITY.md",
	"docs/rules/SECURITY.md",
	"scripts/claims-verify.cjs",
	"scripts/verify",
	"scripts/verify.cjs",
];
const frontendRegistrations = [
	{
		path: "docs/DESIGN_SYSTEM.md",
		namespace: "DESIGN-SYSTEM",
		sidecar: ".harnesskit/audit/claims/docs-DESIGN_SYSTEM.json",
	},
	{
		path: "docs/INTERACTION_DESIGN.md",
		namespace: "INTERACTION-DESIGN",
		sidecar: ".harnesskit/audit/claims/docs-INTERACTION_DESIGN.json",
	},
];
const frontendFiles = [
	".harnesskit/audit/claims/docs-DESIGN_SYSTEM.json",
	".harnesskit/audit/claims/docs-INTERACTION_DESIGN.json",
	"docs/DESIGN_SYSTEM.md",
	"docs/INTERACTION_DESIGN.md",
];

async function createTarget(prefix) {
	return mkdtemp(join(tmpdir(), prefix));
}

async function assertMissing(path) {
	await assert.rejects(lstat(path), { code: "ENOENT" });
}

test("default materialization keeps the base golden and omits Web frontend artifacts", async () => {
	const target = await createTarget("harnesskit-base-profile-");
	const report = await materializeInitTemplates({ target });

	assert.deepEqual(report.created, baseCreatedGolden);
	assert.equal(Object.hasOwn(report, "profile"), false);
	for (const path of frontendFiles) await assertMissing(join(target, ...path.split("/")));

	const actualManifestBytes = await readFile(
		join(target, ".harnesskit/audit/artifact-manifest.json"),
		"utf8",
	);
	assert.equal(actualManifestBytes, await readFile(baseManifestURL, "utf8"));
	const manifest = JSON.parse(actualManifestBytes);
	assert.equal(manifest.claim_namespaces.some(({ namespace }) => namespace === "DESIGN-SYSTEM"), false);
	assert.equal(
		manifest.claim_namespaces.some(({ namespace }) => namespace === "INTERACTION-DESIGN"),
		false,
	);
});

test("explicit Web frontend profile materializes registered templates and empty sidecars", async () => {
	const target = await createTarget("harnesskit-web-profile-");
	const report = await materializeInitTemplates({ target, profile: "web-frontend" });

	assert.equal(report.profile, "web-frontend");
	assert.deepEqual(
		report.created,
		[...baseCreatedGolden, ...frontendFiles].sort(),
	);
	assert.deepEqual(report.conflicts, []);

	const manifest = JSON.parse(
		await readFile(join(target, ".harnesskit/audit/artifact-manifest.json"), "utf8"),
	);
	const baseManifest = JSON.parse(await readFile(baseManifestURL, "utf8"));
	for (const namespace of baseManifest.claim_namespaces) {
		assert.deepEqual(
			manifest.claim_namespaces.find((entry) => entry.namespace === namespace.namespace),
			namespace,
		);
	}
	for (const artifact of baseManifest.claim_artifacts) {
		assert.deepEqual(
			manifest.claim_artifacts.find((entry) => entry.path === artifact.path),
			artifact,
		);
	}
	assert.deepEqual(
		manifest.claim_namespaces.filter(({ namespace }) =>
			["DESIGN-SYSTEM", "INTERACTION-DESIGN"].includes(namespace),
		),
		[
			{ namespace: "DESIGN-SYSTEM", display_name: "Design system", next_number: 1 },
			{ namespace: "INTERACTION-DESIGN", display_name: "Interaction design", next_number: 1 },
		],
	);
	assert.deepEqual(
		manifest.claim_artifacts.filter(({ path }) =>
			frontendRegistrations.some((registration) => registration.path === path),
		),
		frontendRegistrations,
	);
	for (const registration of frontendRegistrations) {
		assert.deepEqual(
			JSON.parse(await readFile(join(target, ...registration.sidecar.split("/")), "utf8")),
			{ schema_version: 4, artifact: registration.path, items: [] },
		);
	}

	const verifier = createRequire(import.meta.url)(join(target, "scripts/claims-verify.cjs"));
	assert.equal(verifier.verifyClaims(target).status, "passed");
	for (const artifact of manifest.claim_artifacts) {
		const path = join(target, ...artifact.path.split("/"));
		const before = await readFile(path, "utf8");
		const after = before.replace(checklistBlockPattern, "");
		assert.notEqual(after, before, `${artifact.path} should contain an authoring checklist`);
		await writeFile(path, after);
	}
	assert.equal(verifier.verifyClaims(target, { final: true }).status, "passed");
});

test("profile reruns preserve human-authored frontend files and allocated manifest state", async () => {
	const target = await createTarget("harnesskit-web-profile-rerun-");
	await materializeInitTemplates({ target, profile: "web-frontend" });
	const designSystem = "# Human design system\n\nKeep these bytes.\n";
	const interactionDesign = "# Human interaction design\n\nKeep these bytes too.\n";
	await writeFile(join(target, "docs/DESIGN_SYSTEM.md"), designSystem);
	await writeFile(join(target, "docs/INTERACTION_DESIGN.md"), interactionDesign);

	const verifier = createRequire(import.meta.url)(join(target, "scripts/claims-verify.cjs"));
	assert.deepEqual(verifier.allocateClaimIds(target, "docs/DESIGN_SYSTEM.md", 1), [
		"DESIGN-SYSTEM-0001",
	]);
	const manifestPath = join(target, ".harnesskit/audit/artifact-manifest.json");
	const manifestBefore = await readFile(manifestPath, "utf8");

	const report = await materializeInitTemplates({ target, profile: "web-frontend" });
	assert.deepEqual(report.created, []);
	assert.deepEqual(report.conflicts, []);
	assert.equal(report.skipped_existing.includes("docs/DESIGN_SYSTEM.md"), true);
	assert.equal(report.skipped_existing.includes("docs/INTERACTION_DESIGN.md"), true);
	assert.equal(await readFile(join(target, "docs/DESIGN_SYSTEM.md"), "utf8"), designSystem);
	assert.equal(
		await readFile(join(target, "docs/INTERACTION_DESIGN.md"), "utf8"),
		interactionDesign,
	);
	assert.equal(await readFile(manifestPath, "utf8"), manifestBefore);
});

test("a base-only target rejects a later profile without partial writes", async () => {
	const target = await createTarget("harnesskit-stale-profile-");
	await materializeInitTemplates({ target });
	const manifestPath = join(target, ".harnesskit/audit/artifact-manifest.json");
	const manifestBefore = await readFile(manifestPath, "utf8");

	const report = await materializeInitTemplates({ target, profile: "web-frontend" });
	assert.deepEqual(report.created, []);
	assert.deepEqual(report.skipped_existing, []);
	assert.deepEqual(report.conflicts, [
		{
			path: ".harnesskit/audit/artifact-manifest.json",
			reason: "existing manifest does not contain the required web-frontend registrations",
		},
	]);
	assert.equal(await readFile(manifestPath, "utf8"), manifestBefore);
	for (const path of frontendFiles) await assertMissing(join(target, ...path.split("/")));
});

test("invalid profiles and conflicting target paths fail clearly", async () => {
	const invalidTarget = await createTarget("harnesskit-invalid-profile-");
	await assert.rejects(
		materializeInitTemplates({ target: invalidTarget, profile: "frontend" }),
		/unknown profile: frontend; supported profiles: web-frontend/,
	);
	assert.deepEqual(await readdir(invalidTarget), []);

	const invalidCLI = spawnSync(
		process.execPath,
		[materializerPath, "--target", invalidTarget, "--profile", "frontend"],
		{ encoding: "utf8" },
	);
	assert.equal(invalidCLI.status, 1);
	assert.match(invalidCLI.stderr, /unknown profile: frontend; supported profiles: web-frontend/);
	assert.deepEqual(await readdir(invalidTarget), []);

	const conflictTarget = await createTarget("harnesskit-conflicting-profile-");
	await mkdir(join(conflictTarget, "docs/DESIGN_SYSTEM.md"), { recursive: true });
	const conflictCLI = spawnSync(
		process.execPath,
		[materializerPath, "--target", conflictTarget, "--profile", "web-frontend"],
		{ encoding: "utf8" },
	);
	assert.equal(conflictCLI.status, 1, conflictCLI.stderr);
	const report = JSON.parse(conflictCLI.stdout);
	assert.deepEqual(report.conflicts, [
		{ path: "docs/DESIGN_SYSTEM.md", reason: "target exists and is not a regular file" },
	]);
	assert.equal((await lstat(join(conflictTarget, "docs/DESIGN_SYSTEM.md"))).isDirectory(), true);
});
