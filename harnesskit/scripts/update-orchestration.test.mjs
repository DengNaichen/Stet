import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { lstat, mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { materializeInitTemplates } from "./init-materialize.mjs";

const require = createRequire(import.meta.url);
const harnesskitRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const updateSkillRoot = join(harnesskitRoot, "skills/harnesskit-update");
const updateSkillPath = join(updateSkillRoot, "SKILL.md");
const updateMetadataPath = join(updateSkillRoot, "agents/harness-agent.yaml");
const initSkillPath = join(harnesskitRoot, "skills/harnesskit-init/SKILL.md");
const baselinePath = ".harnesskit/audit/state/update-baseline.json";
const updateHelper = require(join(harnesskitRoot, "templates/init/scripts/harness-update.cjs"));
const claimsHelper = require(join(harnesskitRoot, "templates/init/scripts/claims-verify.cjs"));

const checkpointFailureContract = {
	positive:
		/Checkpoint 保存失败时不得 emit `needs_input`；保持现有 run-state 与旧 baseline/,
	reversed:
		/(?:(?:并非|不是) Checkpoint 保存失败时不得 emit `needs_input`|Checkpoint 保存失败[^。；\n]*(?:(?:并非|不是)不得 emit `needs_input`|(?:仍可|可以) emit `needs_input`))/,
};
const updateFailureContract = {
	positive:
		/任一 verifier、receipt、HEAD recheck gate 或 finalize 失败都必须保留旧 baseline，且不得报告成功/,
	reversed:
		/(?:(?:并非|不是)任一 verifier、receipt、HEAD recheck gate 或 finalize 失败都必须保留旧 baseline，且不得报告成功|任一 verifier、receipt、HEAD recheck gate 或 finalize 失败[^。；\n]*(?:(?:并非|不是)必须保留旧 baseline|(?:并非|不是)不得报告成功|(?:仍可|可以)报告成功))/,
};
const bootstrapFailureContract = {
	positive:
		/任一 final verifier、root validation receipt 门禁或 finalize 失败都必须保持 baseline 缺失或原值，即不得创建或推进 baseline，且不得报告 Bootstrap 完成/,
	reversed:
		/(?:(?:并非|不是)任一 final verifier、root validation receipt 门禁或 finalize 失败都必须保持 baseline 缺失或原值，即不得创建或推进 baseline，且不得报告 Bootstrap 完成|任一 final verifier、root validation receipt 门禁或 finalize 失败[^。；\n]*(?:(?:并非|不是)必须保持 baseline 缺失或原值|(?:并非|不是)不得(?:创建或推进 baseline|报告 Bootstrap 完成)|(?:仍可|可以)(?:创建或推进 baseline|报告 Bootstrap 完成)))/,
};

function section(markdown, heading) {
	const start = markdown.indexOf(heading);
	assert.notEqual(start, -1, `missing section: ${heading}`);
	const next = markdown.indexOf("\n## ", start + heading.length);
	return markdown.slice(start, next === -1 ? markdown.length : next);
}

function assertInOrder(text, markers, label) {
	let cursor = -1;
	for (const marker of markers) {
		const index = text.indexOf(marker, cursor + 1);
		assert.notEqual(index, -1, `${label}: missing ${marker}`);
		assert.ok(index > cursor, `${label}: ${marker} is out of order`);
		cursor = index;
	}
}

async function assertMissing(path) {
	await assert.rejects(lstat(path), { code: "ENOENT" });
}

function followsContract(text, contract) {
	return contract.positive.test(text) && !contract.reversed.test(text);
}

function assertContract(text, contract, label) {
	assert.match(text, contract.positive, `${label}: missing positive contract`);
	assert.doesNotMatch(text, contract.reversed, `${label}: reversed contract`);
}

test("update skill uses repo-native metadata and stays in Stet canonical assets", async () => {
	const [skill, metadata] = await Promise.all([
		readFile(updateSkillPath, "utf8"),
		readFile(updateMetadataPath, "utf8"),
	]);
	assert.match(skill, /^---\nname: harnesskit-update\ndescription: [^\n]+\n---\n/);
	assert.deepEqual((await readdir(updateSkillRoot)).sort(), ["SKILL.md", "agents"].sort());
	assert.deepEqual((await readdir(join(updateSkillRoot, "agents"))).sort(), ["harness-agent.yaml"]);
	assert.match(metadata, /^interface:\n/);
	assert.match(metadata, /default_prompt: "使用 \$harnesskit-update /);
	assert.match(skill, /本 skill 只留在 Stet canonical assets/);
	assert.match(skill, /不要把 `harnesskit-update` skill 目录或 metadata 复制进目标 repo/);
	assert.match(skill, /不要建立 catalog/);
	assert.doesNotMatch(skill, /复制目标仓库到 skill|openai\.yaml/);
});

test("canonical v2 run-state gates every discovery and resumes Update pending", async () => {
	const skill = await readFile(updateSkillPath, "utf8");
	const entry = section(skill, "## 入口与版本边界");
	assert.match(entry, /用户主动调用 `\$harnesskit-update`/);
	assert.match(entry, /已有有效 baseline 的 base profile Update v1/);
	assert.match(entry, /Fresh run 必须从干净 worktree 开始/);
	assert.match(entry, /完整 object ID[\s\S]*`frozen full HEAD`/);
	assert.match(entry, /Web frontend 与 backend Update 尚未开放[\s\S]*`blocked`/);
	assert.match(entry, /Web frontend Bootstrap 仍可建立首个 baseline/);

	const pending = section(skill, "## Canonical run-state gate 与 pending-first");
	assertInOrder(
		pending,
		["parseRunStateBytes", "run-state.json", "checkpoint-read", "checkpoint-compare"],
		"pending-first",
	);
	assert.match(pending, /任何 `discover`、`checkpoint-build` 或其他 repository write 前/);
	assert.match(pending, /整份 v2 bytes[\s\S]*不要用宽松 JSON parse/);
	assert.match(pending, /任意 `status: pending` 且 `workflow: update`/);
	assert.match(
		pending,
		/任意 `status: pending` 且 workflow 不是 `update`[\s\S]*`workflow: bootstrap_or_adopt` pending[\s\S]*立即返回 `blocked`/,
	);
	assert.match(pending, /不得运行 `discover`、不得写 Update checkpoint[\s\S]*不得接管另一 workflow/);
	assert.match(pending, /`status: idle \| complete \| completed`[\s\S]*不存在任何 pending/);
	assert.match(pending, /legacy v1、invalid\/non-canonical v2[\s\S]*fail-closed[\s\S]*不得迁移/);
	assert.match(pending, /不要在 pending run 上重跑 `discover`/);
	assert.match(pending, /hash 完全匹配的 exact run-local writes/);
	assert.match(pending, /保留已封存 outcomes 和 confirmations/);
	assert.match(pending, /`invalidated`[\s\S]*只废弃[\s\S]*当前 pending round/);
	assert.match(pending, /tooling dependency drift[\s\S]*`blocked`/);
	assert.match(pending, /不要退回全仓 discovery/);
	assertInOrder(skill, ["parseRunStateBytes", "checkpoint-read", "harness-update.cjs discover"], "resume before discover");
});

test("a canonical bootstrap_or_adopt pending state is valid but blocks Update takeover", async () => {
	const round = { id: "bootstrap-round-1" };
	const canonical = updateHelper.canonicalRunState({
		schema_version: updateHelper.RUN_STATE_SCHEMA_VERSION,
		workflow: "bootstrap_or_adopt",
		status: "pending",
		frozen_head: null,
		current_step: "bootstrap_question",
		current_artifact: "AGENTS.md",
		round,
		question_declarations: [
			{
				admission: "intent",
				artifact: "AGENTS.md",
				question: { id: "bootstrap-question-1", round },
			},
		],
		answers: [],
		unsealed_outcomes: [],
		resume_context: {},
		dependency_scope: { kind: "current_pending_round", artifact: "AGENTS.md" },
		relevant_inputs: [],
		accepted_writes: [],
		confirmations: [],
		sealed_outcomes: [],
		open_questions: [],
	});
	const parsed = updateHelper.parseRunStateBytes(claimsHelper.canonicalJSONStringify(canonical));
	assert.equal(parsed.workflow, "bootstrap_or_adopt");
	assert.equal(parsed.status, "pending");
	assert.equal(parsed.question_declarations.length, 1);

	const skill = await readFile(updateSkillPath, "utf8");
	const gate = section(skill, "## Canonical run-state gate 与 pending-first");
	assert.match(gate, /`workflow: bootstrap_or_adopt` pending[\s\S]*立即返回 `blocked`/);
	assert.match(gate, /不得运行 `discover`、不得写 Update checkpoint[\s\S]*不得接管另一 workflow/);
});

test("fresh discovery has three deterministic routes and compressed kickoff", async () => {
	const skill = await readFile(updateSkillPath, "utf8");
	const discovery = section(skill, "## Fresh discovery 与三类路由");
	assert.match(
		discovery,
		/只有 canonical v2 run-state 已确认不存在任何 pending[\s\S]*`idle \| complete \| completed`[\s\S]*harness-update\.cjs discover/,
	);
	assert.match(discovery, /topology、tooling、Claim ID namespace、semantic owner[\s\S]*直接返回 `blocked`/);
	assert.match(discovery, /不要 full scan、baseline migration 或 topology migration/);
	assertInOrder(
		discovery,
		["Existing Claim impacts", "Unindexed/new paths", "High-impact surfaces"],
		"three routes",
	);
	assert.match(discovery, /`claim_impacts` 的 reverse-index `claim_ids` 与 `artifacts`/);
	assert.match(discovery, /`unindexed_changes`[\s\S]*kickoff owner map/);
	assert.match(discovery, /缺失或冲突 owner 返回局部 blocker/);
	for (const surface of [
		"workspace/project manifest",
		"CI binding",
		"README/project identity",
		"build-test-operation entrypoint",
		"repo shape",
		"part roots",
	]) {
		assert.ok(discovery.includes(surface), surface);
	}
	assert.match(discovery, /`\$harnesskit-kickoff Refresh` 做 compressed kickoff/);
	assert.match(discovery, /只规范化、合并并稳定排序 reasons/);
	assert.match(discovery, /不要分类 Claim 语义[\s\S]*不要创建 Questionnaire 文案/);
});

test("queue reaches a finite deduplicated fixpoint and delegates owner questions", async () => {
	const skill = await readFile(updateSkillPath, "utf8");
	const queue = section(skill, "## Deterministic queue 与有限 fixpoint");
	assert.match(queue, /deterministic affected-artifact queue/);
	assert.match(queue, /canonical code-point order 去重/);
	assert.match(queue, /CODING → RELIABILITY → SECURITY → PRODUCT_SENSE[\s\S]*一份一份/);
	assert.match(queue, /`AGENTS\.md` 永远最后/);
	assert.match(queue, /impact signature/);
	assert.match(queue, /相同 signature 只处理一次/);
	assert.match(queue, /累计 reason set 严格增长[\s\S]*重新入队/);
	assert.match(queue, /有限的 discovery report、compressed kickoff 与 sealed owner outcomes/);
	assert.match(queue, /队列为空且没有新的唯一 signature 时达到 fixpoint/);
	assert.match(queue, /循环必须终止/);

	const owners = section(skill, "## Owner Refresh loop");
	for (const owner of [
		"$harnesskit-fill-validation Refresh",
		"$harnesskit-fill-development Refresh",
		"$harnesskit-fill-architecture Refresh",
		"$harnesskit-fill-rules Refresh",
		"$harnesskit-fill-agents Refresh",
	]) {
		assert.ok(owners.includes(`\`${owner}\``), owner);
	}
	for (const input of [
		"changed paths",
		"affected Claim IDs",
		"verifier diagnostics",
		"Markdown drift classification",
		"sealed upstream outcomes",
	]) {
		assert.ok(owners.includes(`\`${input}\``), input);
	}
	assert.match(owners, /sealed outcome 和 `direct semantic downstream impacts`/);
	assert.match(owners, /不要接管 owner[\s\S]*Questionnaire[\s\S]*问题措辞/);
	assert.match(owners, /当前 artifact 的局部 blocker[\s\S]*终止为 `blocked`/);
	assertInOrder(owners, ["checkpoint-build --stdin", "emit `needs_input`", "立即停止"], "pause");
	assertContract(owners, checkpointFailureContract, "checkpoint failure");
});

test("no-impact and impacted runs share strict final gates and four summaries", async () => {
	const skill = await readFile(updateSkillPath, "utf8");
	const noImpact = section(skill, "## No-impact");
	assert.match(noImpact, /不提问/);
	assert.match(noImpact, /不修改任何 Claim-bearing Markdown、sidecar 或 confirmation/);
	assert.match(noImpact, /仍执行全部 final gates/);
	assert.match(noImpact, /`completed` 的 no-impact/);

	const gates = section(skill, "## Final gates 与 baseline 推进");
	assertInOrder(
		gates,
		[
			"全部受影响 artifact 已 sealed",
			"claims-verify.cjs verify --final --json",
			"root validation runner",
			"HEAD^{commit}",
			"harness-update.cjs finalize --source-commit <frozen-full-HEAD>",
			"输出 summary",
		],
		"final gates",
	);
	assertContract(gates, updateFailureContract, "Update final failure");

	const summary = section(skill, "## 终态 summary");
	for (const field of ["scope", "results", "unresolved items", "validation"]) {
		assert.ok(summary.includes(`\`${field}\``), field);
	}
	for (const status of ["completed", "needs_input", "blocked", "failed"]) {
		assert.ok(summary.includes(`\`${status}\``), status);
	}
	assert.match(summary, /只有 finalize 成功的 `completed` 可以称为成功/);
});

test("init finalizes the first baseline only after successful whole Bootstrap gates", async () => {
	const init = await readFile(initSkillPath, "utf8");
	const workflow = section(init, "## 主工作流");
	assertInOrder(
		workflow,
		[
			"claims-verify.cjs verify --final --json",
			"root validation runner",
			"当前目标仓库 `HEAD^{commit}`",
			"harness-update.cjs finalize --source-commit <full-HEAD>",
			"发送一段简洁完成说明",
		],
		"Bootstrap baseline gate",
	);
	assert.match(workflow, /仅当本次\*\*整体运行是 Bootstrap\*\*/);
	assert.match(workflow, /Base 与 `web-frontend` Bootstrap 都执行本门禁/);
	assert.match(workflow, /选择性 Adopt、`needs_input`、`blocked`、`failed`[\s\S]*都不得调用 finalize/);
	assert.match(workflow, /Missing-only materialize 本身仍不创建空 baseline/);
	assertContract(workflow, bootstrapFailureContract, "Bootstrap final failure");
	assert.match(workflow, /选择性 Adopt[\s\S]*不创建或推进 baseline/);
});

test("failure polarity guards reject double-negative mutations", () => {
	const fixtures = [
		{
			label: "checkpoint failure",
			contract: checkpointFailureContract,
			positive:
				"Checkpoint 保存失败时不得 emit `needs_input`；保持现有 run-state 与旧 baseline。",
			mutations: [
				"并非 Checkpoint 保存失败时不得 emit `needs_input`；保持现有 run-state 与旧 baseline。",
				"Checkpoint 保存失败并非不得 emit `needs_input`；保持现有 run-state 与旧 baseline。",
				"Checkpoint 保存失败仍可 emit `needs_input`；保持现有 run-state 与旧 baseline。",
			],
		},
		{
			label: "Update final failure",
			contract: updateFailureContract,
			positive:
				"任一 verifier、receipt、HEAD recheck gate 或 finalize 失败都必须保留旧 baseline，且不得报告成功。",
			mutations: [
				"并非任一 verifier、receipt、HEAD recheck gate 或 finalize 失败都必须保留旧 baseline，且不得报告成功。",
				"任一 verifier、receipt、HEAD recheck gate 或 finalize 失败并非必须保留旧 baseline，且不得报告成功。",
				"任一 verifier、receipt、HEAD recheck gate 或 finalize 失败都必须保留旧 baseline，但并非不得报告成功。",
			],
		},
		{
			label: "Bootstrap final failure",
			contract: bootstrapFailureContract,
			positive:
				"任一 final verifier、root validation receipt 门禁或 finalize 失败都必须保持 baseline 缺失或原值，即不得创建或推进 baseline，且不得报告 Bootstrap 完成。",
			mutations: [
				"并非任一 final verifier、root validation receipt 门禁或 finalize 失败都必须保持 baseline 缺失或原值，即不得创建或推进 baseline，且不得报告 Bootstrap 完成。",
				"任一 final verifier、root validation receipt 门禁或 finalize 失败并非必须保持 baseline 缺失或原值，即不得创建或推进 baseline，且不得报告 Bootstrap 完成。",
				"任一 final verifier、root validation receipt 门禁或 finalize 失败都必须保持 baseline 缺失或原值，即不得创建或推进 baseline，但并非不得报告 Bootstrap 完成。",
			],
		},
	];

	for (const { label, contract, positive, mutations } of fixtures) {
		assert.equal(followsContract(positive, contract), true, `${label}: positive fixture`);
		for (const mutation of mutations) {
			assert.equal(contract.reversed.test(mutation), true, `${label}: reversed guard`);
			assert.equal(followsContract(mutation, contract), false, `${label}: ${mutation}`);
		}
	}
});

test("base and Web materialization install the helper without an empty baseline", async (t) => {
	for (const [name, profile] of [
		["base", undefined],
		["web", "web-frontend"],
	]) {
		await t.test(name, async (st) => {
			const target = await mkdtemp(join(tmpdir(), `harnesskit-update-${name}-`));
			st.after(() => rm(target, { recursive: true, force: true }));
			const report = await materializeInitTemplates({ target, profile });
			assert.equal(report.conflicts.length, 0);
			assert.equal(report.created.includes("scripts/harness-update.cjs"), true);
			assert.equal((await lstat(join(target, "scripts/harness-update.cjs"))).isFile(), true);
			await assertMissing(join(target, ...baselinePath.split("/")));

			const help = spawnSync(process.execPath, ["scripts/harness-update.cjs", "--help"], {
				cwd: target,
				encoding: "utf8",
			});
			assert.equal(help.status, 0, help.stderr);
			assert.match(help.stdout, /checkpoint-read/);
			assert.match(help.stdout, /finalize --source-commit <full-oid>/);
			const read = spawnSync(process.execPath, ["scripts/harness-update.cjs", "read"], {
				cwd: target,
				encoding: "utf8",
			});
			assert.equal(read.status, 1);
			assert.equal(read.stdout, "");
			assert.match(read.stderr, /update-baseline\.json: missing/);
		});
	}
});
