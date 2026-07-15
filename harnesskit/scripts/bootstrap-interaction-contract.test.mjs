import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const harnesskitRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const skillRoot = join(harnesskitRoot, "skills");

const paths = {
	init: join(skillRoot, "harnesskit-init", "SKILL.md"),
	kickoff: join(skillRoot, "harnesskit-kickoff", "SKILL.md"),
	protocol: join(harnesskitRoot, "protocol", "README.md"),
	fills: [
		"harnesskit-fill-validation",
		"harnesskit-fill-development",
		"harnesskit-fill-architecture",
		"harnesskit-fill-design-system",
		"harnesskit-fill-rules",
		"harnesskit-fill-agents",
	].map((name) => join(skillRoot, name, "SKILL.md")),
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

test("Bootstrap rejects unsafe inputs before materialize writes", async () => {
	const [init, kickoff, protocol] = await Promise.all([
		read(paths.init),
		read(paths.kickoff),
		read(paths.protocol),
	]);
	const workflow = section(init, "## 主工作流");
	const preflight = section(kickoff, "## Bootstrap eligibility preflight");

	assert.ok(
		workflow.indexOf("只读 eligibility preflight") <
			workflow.indexOf("运行 missing-only materialize"),
		"Bootstrap preflight must precede materialize",
	);
	assert.match(workflow, /路径冲突时立即停止[\s\S]*preflight 不创建、覆盖或修改任何目标文件/);
	assert.match(preflight, /materialize 之前[\s\S]*立即停止[\s\S]*不得先创建/);
	assert.match(protocol, /read-only eligibility preflight before materialize[\s\S]*without creating files/);
});

test("every fill skill declares one optional claim.rows scan review", async () => {
	for (const path of paths.fills) {
		const skill = await read(path);
		const scanReview = section(skill, "## Bootstrap 扫描核对");
		const workflow = section(skill, "## Markdown-first workflow");

		assert.match(scanReview, /至多一道[\s\S]*claim\.rows/);
		assert.match(scanReview, /仍是[\s\S]*`observed`[\s\S]*不得写 `confirm-user`/);
		assert.match(scanReview, /整组被否定时丢弃当前(?: rule)? artifact[\s\S]*全部 observed drafts/);
		assert.match(scanReview, /退休这些 IDs[\s\S]*重扫整个当前(?: rule)? artifact[\s\S]*不再发第二道扫描核对/);
		assert.match(scanReview, /扫描核对解决或跳过后再写入 observed/);
		assert.match(workflow, /Bootstrap 先保留[\s\S]*drafts[\s\S]*核对解决或跳过前不得写入 target/);
		assert.match(workflow, /Adopt 保持原流程[\s\S]*Adopt 跳过此步/);
	}
});

test("orchestration keeps scan review artifact-scoped and out of Adopt", async () => {
	const [init, protocol] = await Promise.all([read(paths.init), read(paths.protocol)]);
	const questionnaire = section(init, "## Questionnaire 编排");
	const workflow = section(init, "## 主工作流");
	const protocolWorkflow = section(protocol, "## Workflow Rounds");

	assert.match(questionnaire, /每个 artifact[\s\S]*至多一道 scan review[\s\S]*claim\.rows/);
	assert.match(questionnaire, /Adopt 保持原有 intent 流程/);
	assert.match(workflow, /整组否定时丢弃当前 artifact[\s\S]*全部 observed drafts[\s\S]*退休其 IDs[\s\S]*重扫整个当前 artifact/);
	assert.match(protocol, /at most one[\s\S]*scan review question per artifact/);
	assert.match(protocol, /Accepting the scan review keeps every conclusion `observed`[\s\S]*does not create[\s\S]*confirmation record/);
	assert.match(protocol, /Rejecting the whole group discards all unsealed observed drafts[\s\S]*retires their IDs[\s\S]*re-runs the whole artifact scan[\s\S]*without emitting a second scan review/);
	const compactWorkflow = protocolWorkflow.replace(/\s+/g, " ");
	const observedWrite = compactWorkflow.indexOf("writes the settled observed conclusions");
	const intentAsk = compactWorkflow.indexOf("asks any remaining intent questions");
	assert.notEqual(observedWrite, -1);
	assert.notEqual(intentAsk, -1);
	assert.ok(
		observedWrite < intentAsk,
		"settled observed conclusions must be written before intent questions",
	);
});

test("workflow does not offer agent_decide", async () => {
	const workflowFiles = [paths.init, paths.kickoff, ...paths.fills];
	const contents = await Promise.all(workflowFiles.map(read));
	for (let index = 0; index < contents.length; index += 1) {
		assert.doesNotMatch(contents[index], /agent_decide/, workflowFiles[index]);
	}

	const protocol = await read(paths.protocol);
	assert.match(protocol, /Workflow skills do not offer `agent_decide` as a[\s\S]*user choice/);
});
