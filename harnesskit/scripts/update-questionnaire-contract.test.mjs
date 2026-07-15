import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstat, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const require = createRequire(import.meta.url);
const updateScript = fileURLToPath(new URL("../templates/init/scripts/harness-update.cjs", import.meta.url));
const runStateTemplate = fileURLToPath(
	new URL("../templates/init/.harnesskit/audit/state/run-state.json", import.meta.url),
);
const protocolPath = fileURLToPath(new URL("../protocol/README.md", import.meta.url));
const update = require(updateScript);
const claims = require("../templates/init/scripts/claims-verify.cjs");

const ARTIFACT = "docs/A.md";
const SIDECAR = ".harnesskit/audit/claims/A.json";
const WEB_ARTIFACT = "docs/DESIGN_SYSTEM.md";
const WEB_SIDECAR = ".harnesskit/audit/claims/docs-DESIGN_SYSTEM.json";
const INPUT = "src/input.txt";
const FIXED_TIME = "2026-07-15T08:09:10.123Z";

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

function git(root, args) {
	const result = spawnSync("git", ["-C", root, ...args], { encoding: "utf8" });
	assert.equal(result.status, 0, `${args.join(" ")}: ${result.stderr}`);
	return result.stdout.trim();
}

function commitAll(root, message) {
	git(root, ["add", "-A"]);
	git(root, ["commit", "-m", message]);
	return git(root, ["rev-parse", "HEAD"]);
}

function idleState() {
	return {
		schema_version: 2,
		workflow: "bootstrap_or_adopt",
		status: "idle",
		frozen_head: null,
		current_step: "NEEDS_CLARIFICATION",
		current_artifact: "NEEDS_CLARIFICATION",
		round: null,
		question_declarations: [],
		answers: [],
		unsealed_outcomes: [],
		resume_context: {},
		dependency_scope: null,
		relevant_inputs: [],
		accepted_writes: [],
		confirmations: [],
		sealed_outcomes: [],
		open_questions: [],
	};
}

async function createFixture(t, { web = false } = {}) {
	const root = await mkdtemp(join(tmpdir(), "stet-update-questionnaire-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	git(root, ["init"]);
	git(root, ["config", "user.name", "HarnessKit Test"]);
	git(root, ["config", "user.email", "harnesskit@example.test"]);
	await writeRepoFile(root, "README.md", "target source\n");
	const sourceCommit = commitAll(root, "target source");
	await writeRepoFile(root, INPUT, "input\n");
	await writeRepoFile(root, ARTIFACT, "# A\n");
	await writeRepoJSON(root, SIDECAR, { schema_version: 4, artifact: ARTIFACT, items: [] });
	if (web) {
		await writeRepoFile(root, WEB_ARTIFACT, "# Design system\n");
		await writeRepoJSON(root, WEB_SIDECAR, {
			schema_version: 4,
			artifact: WEB_ARTIFACT,
			items: [],
		});
	}
	const namespaces = [{ namespace: "A", display_name: "A", next_number: 2 }];
	const artifacts = [{ path: ARTIFACT, namespace: "A", sidecar: SIDECAR }];
	if (web) {
		namespaces.push({ namespace: "DESIGN-SYSTEM", display_name: "Design system", next_number: 2 });
		namespaces.sort((left, right) => claims.compareText(left.namespace, right.namespace));
		artifacts.push({ path: WEB_ARTIFACT, namespace: "DESIGN-SYSTEM", sidecar: WEB_SIDECAR });
		artifacts.sort((left, right) => claims.compareText(left.path, right.path));
	}
	await writeRepoJSON(root, claims.ARTIFACT_MANIFEST_PATH, {
		schema_version: 3,
		claim_namespaces: namespaces,
		claim_artifacts: artifacts,
	});
	await writeRepoJSON(root, update.RUN_STATE_PATH, idleState());
	const snapshotPaths = [
		claims.ARTIFACT_MANIFEST_PATH,
		...artifacts.flatMap(({ path, sidecar }) => [path, sidecar]),
	].sort(claims.compareText);
	await writeRepoJSON(root, update.UPDATE_BASELINE_PATH, {
		schema_version: 1,
		source_commit: sourceCommit,
		completed_at: FIXED_TIME,
		harness_snapshot: await Promise.all(
			snapshotPaths.map(async (path) => ({ path, sha256: sha256(await readFile(absolute(root, path))) })),
		),
	});
	const head = commitAll(root, "baseline");
	return { root, head };
}

function round(title = "Architecture update") {
	return { title, summary: "Review one artifact" };
}

function intentQuestion(roundValue = round(), prompt = "我建议保持这一边界。对吗？") {
	return {
		kind: "single_choice",
		round: roundValue,
		prompt,
		rationale: "相关源码已改变，需要核对长期约束。",
		sources: [{ path: INPUT, summary: "Changed source" }],
		options: [{ id: "accept", label: "同意" }],
		allow_other: true,
	};
}

function declaration(admission, question, artifact = ARTIFACT, extra = {}) {
	return { admission, artifact, ...extra, question };
}

function checkpointInput(overrides = {}) {
	const roundValue = overrides.round || round();
	const artifact = overrides.current_artifact || ARTIFACT;
	return {
		current_step: "artifact_questionnaire",
		current_artifact: artifact,
		round: roundValue,
		question_declarations:
			overrides.question_declarations || [declaration("intent", intentQuestion(roundValue), artifact)],
		answers: [],
		unsealed_outcomes: [],
		resume_context: { anchor: "# A" },
		relevant_inputs: [INPUT, INPUT],
		accepted_writes: [SIDECAR, ARTIFACT, ARTIFACT],
		confirmations: [],
		sealed_outcomes: [],
		open_questions: [0],
		...overrides,
	};
}

test("v2 template is idle Bootstrap/Adopt state and strict canonical checkpoint build derives hashes", async (t) => {
	const templateBytes = await readFile(runStateTemplate);
	assert.deepEqual(update.parseRunStateBytes(templateBytes), idleState());

	const { root, head } = await createFixture(t);
	assert.throws(() => update.readQuestionnaireCheckpoint(root), /no pending Update/);
	const payload = checkpointInput();
	const cli = spawnSync(
		process.execPath,
		[updateScript, "checkpoint-build", "--stdin", "--root", root],
		{ encoding: "utf8", input: JSON.stringify(payload) },
	);
	assert.equal(cli.status, 0, cli.stderr);
	const state = JSON.parse(cli.stdout);
	assert.equal(state.schema_version, 2);
	assert.equal(state.workflow, "update");
	assert.equal(state.status, "pending");
	assert.equal(state.frozen_head, head);
	assert.deepEqual(state.dependency_scope, {
		kind: "current_pending_round",
		artifact: ARTIFACT,
	});
	assert.deepEqual(
		state.relevant_inputs.map(({ path }) => path),
		[claims.ARTIFACT_MANIFEST_PATH, update.UPDATE_BASELINE_PATH, INPUT].sort(claims.compareText),
	);
	for (const entry of state.relevant_inputs) {
		assert.equal(entry.sha256, sha256(await readFile(absolute(root, entry.path))));
	}
	assert.deepEqual(
		state.accepted_writes.map(({ path }) => path),
		[SIDECAR, ARTIFACT].sort(claims.compareText),
	);
	for (const entry of state.accepted_writes) {
		assert.equal(entry.sha256, sha256(await readFile(absolute(root, entry.path))));
	}
	assert.equal(await readFile(absolute(root, update.RUN_STATE_PATH), "utf8"), claims.canonicalJSONStringify(state));
	assert.deepEqual(update.readQuestionnaireCheckpoint(root), state);
	for (const command of ["checkpoint-read", "checkpoint-compare", "read", "compare"]) {
		const result = spawnSync(process.execPath, [updateScript, command, "--root", root], {
			encoding: "utf8",
		});
		assert.equal(result.status, 0, `${command}: ${result.stderr}`);
		assert.doesNotThrow(() => JSON.parse(result.stdout));
	}
});

test("pending-first requires explicit read/compare and never rewrites legacy v1", async (t) => {
	const { root } = await createFixture(t);
	update.buildQuestionnaireCheckpoint(root, checkpointInput());
	const before = await readFile(absolute(root, update.RUN_STATE_PATH));
	await writeRepoFile(root, INPUT, "stale input\n");
	let evaluated = false;
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(root, () => {
				evaluated = true;
				throw new Error("new input must not be evaluated");
			}),
		/pending Update checkpoint already exists.*checkpoint-read.*checkpoint-compare/,
	);
	assert.equal(evaluated, false);
	assert.deepEqual(update.compareQuestionnaireCheckpoint(root).relevant_input_mismatches.map(({ path }) => path), [INPUT]);
	await writeRepoFile(root, INPUT, "input\n");
	await writeRepoFile(root, "head-change.txt", "advance\n");
	git(root, ["add", "head-change.txt"]);
	git(root, ["commit", "-m", "advance pending head"]);
	assert.notEqual(update.compareQuestionnaireCheckpoint(root).frozen_head_mismatch, null);
	assert.throws(
		() => update.buildQuestionnaireCheckpoint(root, checkpointInput()),
		/pending Update checkpoint already exists/,
	);
	assert.deepEqual(await readFile(absolute(root, update.RUN_STATE_PATH)), before);

	const legacy = Buffer.from(
		claims.canonicalJSONStringify({
			schema_version: 1,
			status: "pending",
			current_step: "legacy",
			current_artifact: ARTIFACT,
			open_questions: [],
		}),
	);
	await writeRepoFile(root, update.RUN_STATE_PATH, legacy);
	assert.throws(
		() => update.buildQuestionnaireCheckpoint(root, checkpointInput()),
		/legacy schema_version 1.*not.*migrated/,
	);
	assert.deepEqual(await readFile(absolute(root, update.RUN_STATE_PATH)), legacy);

	const bootstrapRound = { title: "Bootstrap" };
	await writeRepoJSON(
		root,
		update.RUN_STATE_PATH,
		update.canonicalRunState({
			...idleState(),
			status: "pending",
			current_artifact: ARTIFACT,
			round: bootstrapRound,
			question_declarations: [declaration("intent", intentQuestion(bootstrapRound))],
		}),
	);
	assert.throws(
		() => update.buildQuestionnaireCheckpoint(root, checkpointInput()),
		/another workflow has a pending round/,
	);
});

test("accepted writes use exact repo-local base/Web membership and all hashed paths are safe regular files", async (t) => {
	const base = await createFixture(t);
	const before = await readFile(absolute(base.root, update.RUN_STATE_PATH));
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				base.root,
				checkpointInput({ accepted_writes: [INPUT] }),
			),
		/not accepted Harness membership/,
	);
	assert.deepEqual(await readFile(absolute(base.root, update.RUN_STATE_PATH)), before);
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				base.root,
				checkpointInput({ accepted_writes: [{ path: ARTIFACT, sha256: "0".repeat(64) }] }),
			),
		/accepted_writes\[0\] is unsafe/,
	);
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				base.root,
				checkpointInput({
					relevant_inputs: [
						{ path: claims.ARTIFACT_MANIFEST_PATH, sha256: "0".repeat(64) },
					],
				}),
			),
		/relevant_inputs\[0\] is unsafe/,
	);
	for (const excluded of [
		claims.ARTIFACT_MANIFEST_PATH,
		update.RUN_STATE_PATH,
		update.UPDATE_BASELINE_PATH,
		".harnesskit/receipts/latest.json",
	]) {
		assert.throws(
			() =>
				update.buildQuestionnaireCheckpoint(
					base.root,
					checkpointInput({ accepted_writes: [excluded] }),
				),
			/excluded|not accepted Harness membership|cannot name/,
			excluded,
		);
	}

	const fakeRef = ".harnesskit/audit/transcript/unreferenced.json";
	await writeRepoJSON(base.root, fakeRef, { arbitrary: true });
	const baseline = update.readBaseline(base.root);
	baseline.harness_snapshot.push({ path: fakeRef, sha256: sha256(await readFile(absolute(base.root, fakeRef))) });
	baseline.harness_snapshot.sort((left, right) => claims.compareText(left.path, right.path));
	await writeRepoJSON(base.root, update.UPDATE_BASELINE_PATH, baseline);
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				base.root,
				checkpointInput({ accepted_writes: [fakeRef] }),
			),
		/not accepted Harness membership/,
	);

	const topology = await createFixture(t);
	const expandedManifest = claims.loadArtifactManifest(topology.root);
	expandedManifest.claim_namespaces.push({ namespace: "B", display_name: "B", next_number: 1 });
	expandedManifest.claim_namespaces.sort((left, right) => claims.compareText(left.namespace, right.namespace));
	expandedManifest.claim_artifacts.push({
		path: "docs/B.md",
		namespace: "B",
		sidecar: ".harnesskit/audit/claims/B.json",
	});
	expandedManifest.claim_artifacts.sort((left, right) => claims.compareText(left.path, right.path));
	await writeRepoFile(topology.root, "docs/B.md", "# B\n");
	await writeRepoJSON(topology.root, ".harnesskit/audit/claims/B.json", {
		schema_version: 4,
		artifact: "docs/B.md",
		items: [],
	});
	await writeRepoJSON(topology.root, claims.ARTIFACT_MANIFEST_PATH, expandedManifest);
	assert.throws(
		() => update.buildQuestionnaireCheckpoint(topology.root, checkpointInput()),
		/manifest differs.*baseline topology/,
	);

	const web = await createFixture(t, { web: true });
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				web.root,
				checkpointInput({ accepted_writes: [WEB_ARTIFACT, WEB_SIDECAR] }),
			),
		/not accepted Harness membership/,
	);
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				web.root,
				checkpointInput({
					current_artifact: WEB_ARTIFACT,
					accepted_writes: [ARTIFACT, SIDECAR],
				}),
			),
		/not accepted Harness membership/,
	);
	const state = update.buildQuestionnaireCheckpoint(
		web.root,
		checkpointInput({
			current_artifact: WEB_ARTIFACT,
			accepted_writes: [WEB_SIDECAR, WEB_ARTIFACT],
		}),
	);
	assert.deepEqual(state.accepted_writes.map(({ path }) => path), [WEB_SIDECAR, WEB_ARTIFACT].sort(claims.compareText));

	const confirmation = await createFixture(t);
	const confirmationRef = ".harnesskit/audit/transcript/confirmations/new.json";
	await writeRepoFile(confirmation.root, ARTIFACT, "# A\n\n[A-0001]\n");
	await writeRepoJSON(confirmation.root, confirmationRef, {
		schema_version: 1,
		confirmed_by: "Maintainer",
		date: "2026-07-15",
		claim_ids: ["A-0001"],
	});
	await writeRepoJSON(confirmation.root, SIDECAR, {
		schema_version: 4,
		artifact: ARTIFACT,
		items: [
			{
				id: "A-0001",
				kind: "intent",
				confirmed_by: { type: "user", ref: confirmationRef, date: "2026-07-15" },
			},
		],
	});
	assert.equal(claims.verifyClaims(confirmation.root).valid, true);
	const confirmationState = update.buildQuestionnaireCheckpoint(
		confirmation.root,
		checkpointInput({ accepted_writes: [ARTIFACT, SIDECAR, confirmationRef] }),
	);
	assert.equal(confirmationState.accepted_writes.some(({ path }) => path === confirmationRef), true);

	const scoped = await createFixture(t, { web: true });
	const aRef = ".harnesskit/audit/transcript/confirmations/a.json";
	const webRef = ".harnesskit/audit/transcript/confirmations/design-system.json";
	await writeRepoFile(scoped.root, ARTIFACT, "# A\n\n[A-0001]\n");
	await writeRepoJSON(scoped.root, aRef, {
		schema_version: 1,
		confirmed_by: "Maintainer",
		date: "2026-07-15",
		claim_ids: ["A-0001"],
	});
	await writeRepoJSON(scoped.root, SIDECAR, {
		schema_version: 4,
		artifact: ARTIFACT,
		items: [
			{
				id: "A-0001",
				kind: "intent",
				confirmed_by: { type: "user", ref: aRef, date: "2026-07-15" },
			},
		],
	});
	await writeRepoFile(scoped.root, WEB_ARTIFACT, "# Design system\n\n[DESIGN-SYSTEM-0001]\n");
	await writeRepoJSON(scoped.root, webRef, {
		schema_version: 1,
		confirmed_by: "Maintainer",
		date: "2026-07-15",
		claim_ids: ["DESIGN-SYSTEM-0001"],
	});
	await writeRepoJSON(scoped.root, WEB_SIDECAR, {
		schema_version: 4,
		artifact: WEB_ARTIFACT,
		items: [
			{
				id: "DESIGN-SYSTEM-0001",
				kind: "intent",
				confirmed_by: { type: "user", ref: webRef, date: "2026-07-15" },
			},
		],
	});
	assert.equal(claims.verifyClaims(scoped.root).valid, true);
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				scoped.root,
				checkpointInput({ accepted_writes: [ARTIFACT, SIDECAR, webRef] }),
			),
		/not accepted Harness membership/,
	);
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				scoped.root,
				checkpointInput({
					current_artifact: WEB_ARTIFACT,
					accepted_writes: [WEB_ARTIFACT, WEB_SIDECAR, aRef],
				}),
			),
		/not accepted Harness membership/,
	);
	const scopedState = update.buildQuestionnaireCheckpoint(
		scoped.root,
		checkpointInput({
			current_artifact: WEB_ARTIFACT,
			accepted_writes: [WEB_ARTIFACT, WEB_SIDECAR, webRef],
		}),
	);
	assert.equal(scopedState.accepted_writes.some(({ path }) => path === webRef), true);

	const unsafe = await createFixture(t);
	await rm(absolute(unsafe.root, INPUT));
	await symlink("../docs/A.md", absolute(unsafe.root, INPUT));
	assert.throws(
		() => update.buildQuestionnaireCheckpoint(unsafe.root, checkpointInput()),
		/symlink/,
	);
});

test("checkpoint compare reports stable local mismatches without rejecting unrelated dirt", async (t) => {
	const { root } = await createFixture(t);
	const confirmations = [{ claim_ids: ["A-0000"], ref: "already-recorded" }];
	const sealedOutcomes = [{ artifact: "docs/previous.md", status: "sealed" }];
	update.buildQuestionnaireCheckpoint(
		root,
		checkpointInput({ confirmations, sealed_outcomes: sealedOutcomes }),
	);
	assert.deepEqual(update.compareQuestionnaireCheckpoint(root), {
		schema_version: 1,
		status: "matched",
		matched: true,
		frozen_head_mismatch: null,
		relevant_input_mismatches: [],
		accepted_write_mismatches: [],
		tooling_blockers: [],
		invalidation_plan: {
			scope: "none",
			artifact: ARTIFACT,
			invalidate_fields: [],
			preserve: { confirmations, sealed_outcomes: sealedOutcomes },
		},
	});

	await writeRepoFile(root, "unrelated.txt", "ignored by local checkpoint\n");
	assert.equal(update.compareQuestionnaireCheckpoint(root).matched, true);
	await writeRepoFile(root, INPUT, "changed input\n");
	const relevant = update.compareQuestionnaireCheckpoint(root);
	assert.equal(relevant.matched, false);
	assert.deepEqual(relevant.relevant_input_mismatches.map(({ path }) => path), [INPUT]);
	assert.deepEqual(relevant.accepted_write_mismatches, []);
	assert.deepEqual(relevant.invalidation_plan, {
		scope: "current_pending_round",
		artifact: ARTIFACT,
		invalidate_fields: [
			"answers",
			"open_questions",
			"question_declarations",
			"resume_context",
			"unsealed_outcomes",
		],
		preserve: { confirmations, sealed_outcomes: sealedOutcomes },
	});

	await writeRepoFile(root, INPUT, "input\n");
	await writeRepoFile(root, ARTIFACT, "# changed A\n");
	const accepted = update.compareQuestionnaireCheckpoint(root);
	assert.deepEqual(accepted.relevant_input_mismatches, []);
	assert.deepEqual(accepted.accepted_write_mismatches.map(({ path }) => path), [ARTIFACT]);

	await writeRepoFile(root, ARTIFACT, "# A\n");
	git(root, ["add", "unrelated.txt"]);
	git(root, ["commit", "-m", "advance head"]);
	const head = update.compareQuestionnaireCheckpoint(root);
	assert.equal(head.matched, false);
	assert.notEqual(head.frozen_head_mismatch, null);
	assert.equal(head.invalidation_plan.scope, "current_pending_round");
	assert.deepEqual(head.invalidation_plan.preserve, {
		confirmations,
		sealed_outcomes: sealedOutcomes,
	});
});

test("checkpoint compare blocks manifest and canonical baseline topology drift without writes", async (t) => {
	const { root } = await createFixture(t);
	update.buildQuestionnaireCheckpoint(root, checkpointInput());
	const runStateBefore = await readFile(absolute(root, update.RUN_STATE_PATH));

	const manifest = claims.loadArtifactManifest(root);
	manifest.claim_namespaces[0].display_name = "Changed A";
	await writeRepoJSON(root, claims.ARTIFACT_MANIFEST_PATH, manifest);
	const manifestOnly = update.compareQuestionnaireCheckpoint(root);
	assert.equal(manifestOnly.status, "blocked");
	assert.equal(manifestOnly.matched, false);
	assert.deepEqual(manifestOnly.tooling_blockers, [
		{
			code: "checkpoint_tooling_dependency_mismatch",
			path: claims.ARTIFACT_MANIFEST_PATH,
			message: "saved Update checkpoint tooling dependency no longer matches (sha256_mismatch)",
		},
	]);
	assert.equal(manifestOnly.invalidation_plan.scope, "tooling_blocked");
	assert.deepEqual(manifestOnly.invalidation_plan.invalidate_fields, []);

	const baseline = update.readBaseline(root);
	baseline.harness_snapshot.find(
		({ path }) => path === claims.ARTIFACT_MANIFEST_PATH,
	).sha256 = sha256(await readFile(absolute(root, claims.ARTIFACT_MANIFEST_PATH)));
	await writeRepoJSON(root, update.UPDATE_BASELINE_PATH, baseline);
	const maskedTopology = update.compareQuestionnaireCheckpoint(root);
	assert.equal(maskedTopology.status, "blocked");
	assert.deepEqual(
		maskedTopology.relevant_input_mismatches.map(({ path }) => path),
		[claims.ARTIFACT_MANIFEST_PATH, update.UPDATE_BASELINE_PATH].sort(claims.compareText),
	);
	assert.deepEqual(
		maskedTopology.tooling_blockers.map(({ code, path }) => ({ code, path })),
		[claims.ARTIFACT_MANIFEST_PATH, update.UPDATE_BASELINE_PATH]
			.sort(claims.compareText)
			.map((path) => ({ code: "checkpoint_tooling_dependency_mismatch", path })),
	);
	assert.equal(maskedTopology.invalidation_plan.scope, "tooling_blocked");
	assert.deepEqual(maskedTopology.invalidation_plan.invalidate_fields, []);
	assert.deepEqual(await readFile(absolute(root, update.RUN_STATE_PATH)), runStateBefore);
});

test("validation and atomic failures preserve prior run-state bytes", async (t) => {
	const { root } = await createFixture(t);
	const before = await readFile(absolute(root, update.RUN_STATE_PATH));
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(root, checkpointInput(), {
				beforeRename() {
					throw new Error("injected atomic failure");
				},
			}),
		/injected atomic failure/,
	);
	assert.deepEqual(await readFile(absolute(root, update.RUN_STATE_PATH)), before);
	assert.equal(
		(await readdir(dirname(absolute(root, update.RUN_STATE_PATH)))).some((name) => name.includes(".tmp-")),
		false,
	);

	const tooMany = Array.from({ length: 9 }, (_, index) =>
		declaration("intent", intentQuestion(round(), `Question ${index}`)),
	);
	assert.throws(
		() => update.buildQuestionnaireCheckpoint(root, checkpointInput({ question_declarations: tooMany })),
		/at most 8/,
	);
	const observedQuestion = {
		...intentQuestion(round()),
		claim: { rows: [{ value: "Observed" }] },
	};
	const observed = declaration("observed", observedQuestion);
	assert.throws(
		() =>
			update.buildQuestionnaireCheckpoint(
				root,
				checkpointInput({
					question_declarations: [observed, declaration("intent", intentQuestion(round()))],
				}),
			),
		/must use separate rounds/,
	);
	for (const [name, questionDeclarations, expected] of [
		["missing admission", [{ artifact: ARTIFACT, question: intentQuestion(round()) }], /admission/],
		[
			"provenance admission",
			[declaration("provenance", intentQuestion(round()))],
			/admission must be observed, intent, or manual_markdown/,
		],
		[
			"observed without rows",
			[declaration("observed", intentQuestion(round()))],
			/claim\.rows must contain/,
		],
		[
			"intent with rows",
			[declaration("intent", observedQuestion)],
			/mixes intent with observed claim rows/,
		],
		[
			"manual change first",
			[declaration("manual_markdown", intentQuestion(round()), ARTIFACT, { phase: "change" })],
			/phase must equal reason/,
		],
		[
			"manual mixed with intent",
			[
				declaration("manual_markdown", intentQuestion(round()), ARTIFACT, { phase: "reason" }),
				declaration("intent", intentQuestion(round(), "Intent")),
			],
			/must use separate rounds/,
		],
	]) {
		assert.throws(
			() =>
				update.buildQuestionnaireCheckpoint(
					root,
					checkpointInput({ question_declarations: questionDeclarations }),
				),
			expected,
			name,
		);
	}
	assert.deepEqual(await readFile(absolute(root, update.RUN_STATE_PATH)), before);

	const manual = await createFixture(t);
	const manualState = update.buildQuestionnaireCheckpoint(
		manual.root,
		checkpointInput({
			question_declarations: [
				declaration("manual_markdown", intentQuestion(round()), ARTIFACT, { phase: "reason" }),
			],
		}),
	);
	assert.equal(manualState.question_declarations[0].phase, "reason");
});

test("protocol fixes Update admission and save-before-needs_input ordering", async () => {
	const protocol = await readFile(protocolPath, "utf8");
	assert.match(protocol, /Update Questionnaire Checkpoints/);
	assert.match(protocol, /Do not ask[\s\S]*provenance metadata/);
	assert.match(protocol, /`observed`[\s\S]*one optional review batch/);
	assert.match(protocol, /every `intent` declaration is one independent/);
	assert.match(protocol, /`manual_markdown`[\s\S]*phase: "reason"/);
	assert.match(protocol, /at most 8 questions/);
	assert.match(protocol, /dependency_scope[\s\S]*current artifact's pending round/);
	assert.match(protocol, /automatically injects the artifact manifest and Update[\s\S]*whole-file tooling dependencies/);
	assert.match(protocol, /membership is limited to the current artifact, its sidecar[\s\S]*current sidecar/);
	assert.match(protocol, /tooling_blockers[\s\S]*status: "blocked"[\s\S]*not downgraded/);
	assert.match(protocol, /invalidation_plan[\s\S]*preserves `confirmations` and `sealed_outcomes`/);
	assert.match(protocol, /Before emitting `needs_input`[\s\S]*atomically saves the full round/);
	assert.match(protocol, /Once `needs_input` is emitted, stop all repository reads and writes immediately/);
});
