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
	kickoff: join(skillRoot, "harnesskit-kickoff", "SKILL.md"),
};

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
	"docs/DESIGN_SYSTEM.md",
	"docs/INTERACTION_DESIGN.md",
	...baseArtifactOrder.slice(3),
];

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

test("ambiguous Bootstrap or Adopt selection emits one blocking profile question and resumes at the existing boundary", async () => {
	const [kickoff, init] = await Promise.all([read(paths.kickoff), read(paths.init)]);
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
	assertInOrder(workflow, [
		"existing paused segment",
		"profile selection",
		"不重复已完成轮次",
		"missing-only materialize",
	]);
	assert.match(workflow, /不新增 run-state、Questionnaire 字段或 backend lifecycle/);
});

test("selected Web frontend profile materializes both artifacts and routes each owner once", async () => {
	const [kickoff, init] = await Promise.all([read(paths.kickoff), read(paths.init)]);
	const routing = section(kickoff, "## Artifact 路由（全局硬规则）");
	const materialize = section(init, "## Missing-only materialize");
	const plan = section(init, "## 单仓 artifact 计划");

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

	const target = await mkdtemp(join(tmpdir(), "harnesskit-frontend-orchestration-"));
	const report = await materializeInitTemplates({ target, profile: "web-frontend" });
	assert.equal(report.profile, "web-frontend");
	assert.equal((await lstat(join(target, "docs/DESIGN_SYSTEM.md"))).isFile(), true);
	assert.equal((await lstat(join(target, "docs/INTERACTION_DESIGN.md"))).isFile(), true);
});

test("non-frontend single repositories retain the base artifact golden and owner order", async () => {
	const init = await read(paths.init);
	const plan = section(init, "## 单仓 artifact 计划");
	const target = await mkdtemp(join(tmpdir(), "harnesskit-base-orchestration-"));
	const report = await materializeInitTemplates({ target });

	assert.deepEqual(artifactOrder(plan, "base 单仓"), baseArtifactOrder);
	assert.match(plan, /base 单仓[\s\S]*保持既有顺序/);
	assert.equal(Object.hasOwn(report, "profile"), false);
	assert.deepEqual(report.created, baseCreatedGolden);
	await assertMissing(join(target, "docs/DESIGN_SYSTEM.md"));
	await assertMissing(join(target, "docs/INTERACTION_DESIGN.md"));
});

test("selective Adopt resolves once, preserves human docs, and keeps mixed artifacts independent", async () => {
	const [kickoff, init] = await Promise.all([read(paths.kickoff), read(paths.init)]);
	const profile = section(kickoff, "## 单仓 Web frontend profile 识别");
	const workflow = section(init, "## 主工作流");
	const target = await mkdtemp(join(tmpdir(), "harnesskit-frontend-adopt-"));
	const designBytes = "# Existing design guidance\n\nKeep this human text.\n";
	const interactionBytes = "# Existing interaction guidance\n\nKeep this too.\n";
	await mkdir(join(target, "docs"), { recursive: true });
	await writeFile(join(target, "docs/DESIGN_SYSTEM.md"), designBytes);
	await writeFile(join(target, "docs/INTERACTION_DESIGN.md"), interactionBytes);

	assert.match(profile, /Adopt[^\n]*materialize 前[^\n]*只读 profile routing/);
	assert.match(workflow, /选择性 Adopt[^\n]*profile[^\n]*首次 materialize/);
	assert.match(workflow, /选择性 Adopt[^\n]*不读取或选择现有 artifact 内容/);
	assert.match(workflow, /overlay[^\n]*人写 Markdown[^\n]*`skipped_existing`/);
	assert.match(workflow, /选择性 Adopt 的 profile continuation[^\n]*existing paused segment[^\n]*不重复/);
	assert.match(workflow, /逐 artifact 按 materialize result 分流/);
	assert.match(workflow, /`created` skeleton 走 Bootstrap loop[^\n]*`skipped_existing` 人工内容走 Adopt/);

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
	assert.deepEqual(receiptContracts[1], receiptContracts[0]);
});

test("monorepo and mixed-profile routing remain explicitly unsupported", async () => {
	const kickoff = await read(paths.kickoff);
	const profile = section(kickoff, "## 单仓 Web frontend profile 识别");

	assert.match(profile, /只适用于[^\n]*single project/);
	assert.match(profile, /monorepo、part 与 mixed profile(?: routing)?[^\n]*当前范围外/i);
	assert.match(profile, /single project \/ monorepo 尚未收敛[^\n]*保持 base[^\n]*不发 Web profile 问题/);
	assert.match(profile, /不要为其中某个 part 自动选择或询问 `web-frontend`/);
	assert.match(profile, /不要声称其 Design System 或 Interaction Design 已被覆盖/);
});
