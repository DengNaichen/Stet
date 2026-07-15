import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { lstat, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import { materializeInitTemplates } from "./init-materialize.mjs";

const harnesskitRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const skillRoot = join(harnesskitRoot, "skills");
const paths = {
	init: join(skillRoot, "harnesskit-init", "SKILL.md"),
	initAgent: join(skillRoot, "harnesskit-init", "agents", "harness-agent.yaml"),
	kickoff: join(skillRoot, "harnesskit-kickoff", "SKILL.md"),
	kickoffAgent: join(skillRoot, "harnesskit-kickoff", "agents", "harness-agent.yaml"),
	protocol: join(harnesskitRoot, "protocol", "README.md"),
};

const frontendArtifacts = ["docs/DESIGN_SYSTEM.md", "docs/INTERACTION_DESIGN.md"];

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
const baseArtifactOrder = [
	"docs/VALIDATION.md",
	"docs/DEVELOPMENT.md",
	"docs/ARCHITECTURE.md",
	"docs/rules/CODING.md",
	"docs/rules/RELIABILITY.md",
	"docs/rules/SECURITY.md",
	"docs/rules/PRODUCT_SENSE.md",
	"AGENTS.md",
];
const frontendArtifactOrder = [
	...baseArtifactOrder.slice(0, 3),
	...frontendArtifacts,
	...baseArtifactOrder.slice(3),
];
const baseReceiptGolden = {
	keys: [
		"checks",
		"config_path",
		"finished_at",
		"mode",
		"run_id",
		"schema_version",
		"started_at",
		"status",
		"trigger",
	],
	schema_version: 1,
	trigger: "manual",
	mode: "full",
	status: "passed",
	config_path: ".harnesskit/validation.json",
	checks: [
		{
			name: "claims-verify",
			command: "node scripts/claims-verify.cjs --json",
			status: "passed",
			exit_code: 0,
		},
	],
};

async function read(path) {
	return readFile(path, "utf8");
}

function section(markdown, heading) {
	const start = markdown.indexOf(heading);
	assert.notEqual(start, -1, `missing section: ${heading}`);
	const next = markdown.indexOf("\n## ", start + heading.length);
	return markdown.slice(start, next === -1 ? markdown.length : next);
}

function assertInOrder(contents, snippets) {
	let offset = 0;
	for (const snippet of snippets) {
		const index = contents.indexOf(snippet, offset);
		assert.notEqual(index, -1, `missing or out-of-order text: ${snippet}`);
		offset = index + snippet.length;
	}
}

function count(contents, needle) {
	return contents.split(needle).length - 1;
}

function artifactOrder(plan, label) {
	const line = plan.split("\n").find((candidate) => candidate.startsWith(`- **${label}`));
	assert.ok(line, `missing ${label} plan`);
	return [...line.matchAll(/`((?:AGENTS|docs\/[^`]+)\.md)`/g)].map(([, path]) => path);
}

function frontmatterName(skill) {
	const match = /^---\n[\s\S]*?^name:\s*(\S+)\s*$/m.exec(skill);
	assert.ok(match, "missing skill frontmatter name");
	return match[1];
}

async function assertMissing(path) {
	await assert.rejects(lstat(path), { code: "ENOENT" });
}

test("single-repository profile selection is evidence-first with positive, negative, and ambiguous fixtures", async () => {
	const kickoff = await read(paths.kickoff);
	const profile = section(kickoff, "## 单仓 Web frontend profile 识别");
	const fixtures = {
		positive: ["可运行的 browser UI entrypoint", "对应 build 或 serve 入口", "Web frontend"],
		negative: ["native app、CLI、backend service 或 library", "base"],
		ambiguous: ["只有 framework marker", "browser dependency", "证据互相冲突"],
	};

	assert.match(profile, /先读 repository evidence[\s\S]*再选择 profile/);
	for (const [name, snippets] of Object.entries(fixtures)) {
		for (const snippet of snippets) {
			assert.ok(profile.includes(snippet), `${name} fixture missing: ${snippet}`);
		}
	}
	assert.match(profile, /framework marker[\s\S]*只能帮助判断 repo 类型[\s\S]*不能证明[^\n]*artifact 内容/);
	assert.match(profile, /absence[^\n]*不能[^\n]*negative/);
	assert.match(profile, /sources\[\]\.path[^\n]*repo-relative evidence path/);
	assert.match(profile, /entrypoint、build\/serve target 与 UI surface[^\n]*关联/);
});

test("protocol, kickoff, and init settle repo shape before the one materialize", async () => {
	const [protocol, kickoff, init] = await Promise.all([
		read(paths.protocol),
		read(paths.kickoff),
		read(paths.init),
	]);
	const protocolWorkflow = section(protocol, "## Workflow Rounds");
	const kickoffPreflight = section(kickoff, "## Bootstrap eligibility preflight");
	const kickoffProfile = section(kickoff, "## 单仓 Web frontend profile 识别");
	const kickoffWorkflow = section(kickoff, "## Kickoff 流程");
	const initWorkflow = section(init, "## 主工作流");

	assertInOrder(protocolWorkflow, [
		"settle repository shape",
		"For a confirmed",
		"selects `base` or `web-frontend`",
		"exactly one missing-only materialize",
	]);
	assertInOrder(kickoffWorkflow, [
		"只读核实 repo shape",
		"首次 materialize 前必须得到 `single project | monorepo`",
		"已确认 single project",
		"选择 materialize profile",
		"运行一次 missing-only materialize",
	]);
	assertInOrder(kickoffPreflight, [
		"repo shape/profile 仍必须在首次 materialize 前单独收敛",
		"materialize 后复用已收敛结论且不重扫",
		"剩余 artifact 地图与整体计划 brief",
		"尚未确认的 part roots、project identity、build/test/operation entrypoint 与 validation entrypoint",
	]);
	assertInOrder(initWorkflow, [
		"只读核实 `single project | monorepo`",
		"首次 materialize 前必须收敛为 single project 或 monorepo",
		"Single project 才执行 profile 分类",
		"运行 missing-only materialize",
	]);
	assert.doesNotMatch(kickoffPreflight, /不代替 materialize 后的 repo-shape 与整体计划扫描/);
	assert.match(kickoffWorkflow, /复用 materialize 前已收敛的 repo-shape\/profile 结论，不重复这些轮次/);
	assert.match(initWorkflow, /复用 pre-materialize 已收敛的 repo-shape\/profile 结论，不重复这些轮次/);
	assert.match(kickoffPreflight, /profile 自动选择或回答收敛后[^\n]*检查所选 profile 将创建的每个路径/);
	assert.match(initWorkflow, /eligibility preflight 的 profile 无关部分/);
	assert.match(initWorkflow, /Profile 收敛前不检查 base\/profile manifest 的专属目标路径[^\n]*不因未选 profile 的既有目标文件停止/);
	assert.doesNotMatch(initWorkflow, /eligibility preflight：对照 HarnessKit asset 中的 base\/profile manifest 与现有目标路径/);
	assert.match(initWorkflow, /Profile 收敛后，Bootstrap 只对所选完整目标集合[^\n]*path safety check/);
	assert.doesNotMatch(kickoffProfile, /尚未收敛[^\n]*保持 base materialize/);
	assert.doesNotMatch(initWorkflow, /single\/monorepo 尚未收敛[^\n]*保持 base/);
	assert.match(protocolWorkflow, /only read-only pre-materialize routing[\s\S]*exception to Adopt's materialize-first flow/);
	assert.match(initWorkflow, /materialize-first 的唯一只读 pre-materialize 例外/);
	assert.match(protocolWorkflow, /artifact evidence scan[\s\S]*writes remain[\s\S]*materialize-first/);
	assert.match(initWorkflow, /不读取或选择现有 artifact 内容/);
});

test("ambiguous Bootstrap or Adopt selection emits one blocking profile question and resumes at the existing boundary", async () => {
	const [protocol, kickoff, init] = await Promise.all([
		read(paths.protocol),
		read(paths.kickoff),
		read(paths.init),
	]);
	const protocolResume = section(protocol, "## Runtime Wrapper and Backend Resume");
	const profile = section(kickoff, "## 单仓 Web frontend profile 识别");
	const workflow = section(init, "## 主工作流");
	const questionnaire = section(init, "## Questionnaire 编排");

	assert.match(profile, /Bootstrap 与选择性 Adopt/);
	assertInOrder(profile, [
		"证据不足或冲突",
		"只声明一次",
		"会改变 artifact 集合",
		"profile 问题",
	]);
	assert.match(profile, /Web frontend profile[\s\S]*`docs\/DESIGN_SYSTEM\.md`[\s\S]*`docs\/INTERACTION_DESIGN\.md`/);
	assert.match(questionnaire, /profile 问题[\s\S]*一道 `single_choice`[\s\S]*(?:不得|不生成)[^\n]*第二道/);
	assert.match(workflow, /输出 `needs_input` 后立即停止[\s\S]*repository 读写[\s\S]*零写入/);
	assert.match(profile, /自由文本[^\n]*普通语言[^\n]*base\/Web 选择/);
	assert.match(profile, /定向复核用户指出的 evidence[^\n]*不重发 profile 问题/);
	assert.match(workflow, /Profile answer 从同一 existing paused segment 恢复/);
	assert.match(workflow, /自由文本[^\n]*只定向复核[^\n]*证据及直接影响/);
	assert.match(protocolResume, /free-text answer[\s\S]*point to[\s\S]*repository evidence/);
	assert.match(protocolResume, /targeted evidence re-check[\s\S]*does not emit a second profile question/);
	assert.ok(workflow.indexOf("Profile answer") < workflow.indexOf("运行 missing-only materialize"));
	assert.match(workflow, /不新增 run-state、Questionnaire 字段或 backend lifecycle/);
});

test("selected Web frontend profile materializes both artifacts and routes each owner once", async () => {
	const [kickoff, init] = await Promise.all([read(paths.kickoff), read(paths.init)]);
	const routing = section(kickoff, "## Artifact 路由（全局硬规则）");
	const brief = section(kickoff, "## 整体计划 brief");
	const kickoffWorkflow = section(kickoff, "## Kickoff 流程");
	const materialize = section(init, "## Missing-only materialize");
	const plan = section(init, "## 单仓 artifact 计划");
	const initWorkflow = section(init, "## 主工作流");

	assert.match(
		materialize,
		/node \/opt\/harnesskit\/scripts\/init-materialize\.mjs --target "\$PWD" --profile web-frontend/,
	);
	assert.deepEqual(artifactOrder(plan, "Web frontend 单仓"), frontendArtifactOrder);
	assert.equal(count(plan, "$harnesskit-fill-design-system"), 1);
	assert.equal(count(plan, "$harnesskit-fill-interaction-design"), 1);
	assert.match(routing, /`docs\/DESIGN_SYSTEM\.md`[^\n]*semantic token[^\n]*共享组件外观/);
	assert.match(routing, /`docs\/INTERACTION_DESIGN\.md`[^\n]*用户行为[^\n]*转换/);
	assert.match(plan, /artifact 地图[\s\S]*整体计划 brief[\s\S]*逐 artifact loop/);
	for (const artifact of frontendArtifacts) {
		assert.ok(routing.includes(`\`${artifact}\``), `route missing ${artifact}`);
		assert.ok(brief.includes(`\`${artifact}\``), `brief handoff missing ${artifact}`);
		assert.ok(plan.includes(`\`${artifact}\``), `plan missing ${artifact}`);
	}
	assert.match(kickoffWorkflow, /artifact 地图与整体计划 brief 交给 init/);
	assert.match(initWorkflow, /按 kickoff artifact 地图[\s\S]*消费 kickoff 整体计划 brief/);

	const target = await mkdtemp(join(tmpdir(), "harnesskit-frontend-orchestration-"));
	const report = await materializeInitTemplates({ target, profile: "web-frontend" });
	assert.equal(report.profile, "web-frontend");
	assert.equal((await lstat(join(target, "docs/DESIGN_SYSTEM.md"))).isFile(), true);
	assert.equal((await lstat(join(target, "docs/INTERACTION_DESIGN.md"))).isFile(), true);
	const manifest = JSON.parse(
		await readFile(join(target, ".harnesskit/audit/artifact-manifest.json"), "utf8"),
	);
	assert.deepEqual(
		manifest.claim_artifacts
			.map(({ path }) => path)
			.filter((path) => frontendArtifacts.includes(path)),
		frontendArtifacts,
	);
});

test("kickoff and init agent metadata route to their declared skill names", async () => {
	const [kickoff, kickoffAgent, init, initAgent] = await Promise.all([
		read(paths.kickoff),
		read(paths.kickoffAgent),
		read(paths.init),
		read(paths.initAgent),
	]);
	for (const [skill, agent] of [
		[kickoff, kickoffAgent],
		[init, initAgent],
	]) {
		const name = frontmatterName(skill);
		assert.match(agent, new RegExp(`default_prompt: "[^"]*\\$${name}(?: |\\.)`));
		assert.match(agent, /short_description: "[^\n]*profile[^\n]*"/);
	}
});

test("non-frontend single repositories retain the base artifact golden and owner order", async () => {
	const init = await read(paths.init);
	const plan = section(init, "## 单仓 artifact 计划");
	const target = await mkdtemp(join(tmpdir(), "harnesskit-base-orchestration-"));
	const webOnlyBytes = "# Existing Web-only design guidance\n";
	await mkdir(join(target, "docs"), { recursive: true });
	await writeFile(join(target, "docs/DESIGN_SYSTEM.md"), webOnlyBytes);
	const report = await materializeInitTemplates({ target });

	assert.deepEqual(artifactOrder(plan, "base 单仓"), baseArtifactOrder);
	assert.match(plan, /base 单仓[\s\S]*保持既有顺序/);
	assert.equal(Object.hasOwn(report, "profile"), false);
	assert.deepEqual(report.created, baseCreatedGolden);
	assert.equal(await readFile(join(target, "docs/DESIGN_SYSTEM.md"), "utf8"), webOnlyBytes);
	assert.equal(report.skipped_existing.includes("docs/DESIGN_SYSTEM.md"), false);
	await assertMissing(join(target, "docs/INTERACTION_DESIGN.md"));
});

test("selective Adopt resolves once, preserves human docs, and keeps mixed artifacts independent", async () => {
	const [protocol, kickoff, init] = await Promise.all([
		read(paths.protocol),
		read(paths.kickoff),
		read(paths.init),
	]);
	const protocolWorkflow = section(protocol, "## Workflow Rounds");
	const profile = section(kickoff, "## 单仓 Web frontend profile 识别");
	const workflow = section(init, "## 主工作流");
	const target = await mkdtemp(join(tmpdir(), "harnesskit-frontend-adopt-"));
	const designBytes = "# Existing design guidance\n\nKeep this human text.\n";
	const interactionBytes = "# Existing interaction guidance\n\nKeep this too.\n";
	await mkdir(join(target, "docs"), { recursive: true });
	await writeFile(join(target, "docs/DESIGN_SYSTEM.md"), designBytes);
	await writeFile(join(target, "docs/INTERACTION_DESIGN.md"), interactionBytes);

	assert.match(profile, /两种模式都在 materialize 前[^\n]*只读 profile routing/);
	assert.match(profile, /Adopt materialize-first 的唯一只读 routing 例外/);
	assert.match(workflow, /选择性 Adopt[^\n]*repo-shape\/profile routing[^\n]*pre-materialize 例外/);
	assert.match(workflow, /选择性 Adopt[^\n]*不读取或选择现有 artifact 内容/);
	assert.match(workflow, /`skipped_existing` 人工内容走 Adopt 最小选择\/写入保护/);
	assert.match(workflow, /Profile answer 从同一 existing paused segment 恢复[^\n]*只定向复核[^\n]*不重发 profile 问题/);
	assert.match(workflow, /混合结果逐 artifact 分流并各调用一次对应 owner/);
	assert.match(workflow, /`created` skeleton 走 Bootstrap loop[^\n]*`skipped_existing` 人工内容走 Adopt/);
	assert.match(protocolWorkflow, /After the profile is settled, Adopt runs exactly one missing-only materialize/);
	assert.match(protocolWorkflow, /Questionnaire wrapper[\s\S]*missing-only behavior are unchanged/);

	const report = await materializeInitTemplates({ target, profile: "web-frontend" });
	assert.equal(report.profile, "web-frontend");
	assert.equal(report.skipped_existing.includes("docs/DESIGN_SYSTEM.md"), true);
	assert.equal(report.skipped_existing.includes("docs/INTERACTION_DESIGN.md"), true);
	assert.equal(await readFile(join(target, "docs/DESIGN_SYSTEM.md"), "utf8"), designBytes);
	assert.equal(
		await readFile(join(target, "docs/INTERACTION_DESIGN.md"), "utf8"),
		interactionBytes,
	);

	const mixedTarget = await mkdtemp(join(tmpdir(), "harnesskit-frontend-adopt-mixed-"));
	await mkdir(join(mixedTarget, "docs"), { recursive: true });
	await writeFile(join(mixedTarget, "docs/DESIGN_SYSTEM.md"), designBytes);
	const mixedReport = await materializeInitTemplates({
		target: mixedTarget,
		profile: "web-frontend",
	});
	assert.equal(mixedReport.skipped_existing.includes("docs/DESIGN_SYSTEM.md"), true);
	assert.equal(mixedReport.created.includes("docs/INTERACTION_DESIGN.md"), true);
	assert.equal(
		await readFile(join(mixedTarget, "docs/DESIGN_SYSTEM.md"), "utf8"),
		designBytes,
	);
	assert.equal((await lstat(join(mixedTarget, "docs/INTERACTION_DESIGN.md"))).isFile(), true);
});

test("final Claim verification and root validation receipt stay independent of profile routing", async () => {
	const init = await read(paths.init);
	const workflow = section(init, "## 主工作流");
	const finalVerification = workflow.indexOf("verify --final --json");
	const rootReceipt = workflow.indexOf("root validation runner");

	assert.notEqual(finalVerification, -1);
	assert.notEqual(rootReceipt, -1);
	assert.ok(finalVerification < rootReceipt);
	assert.match(workflow, /final verifier 与 root validation receipt 是两个独立门禁/i);
	assert.match(workflow, /profile 不改变[^\n]*receipt[^\n]*路径、状态语义或报告要求/i);

	const receiptContracts = [];
	for (const profile of [undefined, "web-frontend"]) {
		const target = await mkdtemp(join(tmpdir(), `harnesskit-receipt-${profile || "base"}-`));
		await materializeInitTemplates({ target, ...(profile ? { profile } : {}) });
		const final = spawnSync(
			process.execPath,
			["scripts/claims-verify.cjs", "verify", "--final", "--json"],
			{ cwd: target, encoding: "utf8" },
		);
		assert.equal(final.status, 1);
		assert.equal(JSON.parse(final.stdout).status, "failed");

		const root = spawnSync("./scripts/verify", ["--mode", "full"], {
			cwd: target,
			encoding: "utf8",
		});
		assert.equal(root.status, 0, root.stderr);
		const receipt = JSON.parse(
			await readFile(join(target, ".harnesskit/receipts/latest.json"), "utf8"),
		);
		receiptContracts.push({
			keys: Object.keys(receipt).sort(),
			schema_version: receipt.schema_version,
			trigger: receipt.trigger,
			mode: receipt.mode,
			status: receipt.status,
			config_path: receipt.config_path,
			checks: receipt.checks.map(({ name, command, status, exit_code }) => ({
				name,
				command,
				status,
				exit_code,
			})),
		});
	}
	assert.deepEqual(receiptContracts[0], baseReceiptGolden);
	assert.deepEqual(receiptContracts[1], receiptContracts[0]);
});

test("monorepo and mixed-profile routing remain explicitly unsupported", async () => {
	const kickoff = await read(paths.kickoff);
	const profile = section(kickoff, "## 单仓 Web frontend profile 识别");

	assert.match(profile, /只有 shape 已确认为 `single project`[^\n]*Web profile 分类/);
	assert.match(profile, /Web part\/mixed profile[^\n]*当前范围外/i);
	assert.match(profile, /无法收敛[^\n]*repo-shape 预热问题[^\n]*不能用 base materialize 抢跑/);
	assert.match(profile, /已确认 monorepo[^\n]*既有 base 路由/);
	assert.match(profile, /不要为其中某个 part 自动选择或询问 `web-frontend`/);
	assert.match(profile, /不要声称其 Design System 或 Interaction Design 已被覆盖/);
});
