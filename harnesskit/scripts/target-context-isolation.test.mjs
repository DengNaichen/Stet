import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

test("target guidance templates do not publish HarnessKit completion machinery", async () => {
	const validation = await readFile(
		new URL("../templates/init/docs/VALIDATION.md", import.meta.url),
		"utf8",
	);
	const agents = await readFile(
		new URL("../templates/init/AGENTS.md", import.meta.url),
		"utf8",
	);

	for (const forbidden of [
		".harnesskit/",
		"scripts/claims-verify.cjs",
		"Claim provenance",
		"claim contract",
	]) {
		assert.equal(validation.includes(forbidden), false, `VALIDATION.md contains ${forbidden}`);
		assert.equal(agents.includes(forbidden), false, `AGENTS.md contains ${forbidden}`);
	}
});
