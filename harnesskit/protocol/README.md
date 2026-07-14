# HarnessKit Questionnaire UX and Protocol Notes

This directory owns the runtime/backend Questionnaire wire contract. The UX
model below is workflow policy layered on top of `question-v1.json` and the
runtime `needs_input` wrapper.

## Default Content Model

Questionnaire asks content questions only. It must not ask for stage approval,
write approval, permission to continue, or process consent.

The default question shape is an agent-recommended conclusion plus the choices
`同意` and `要修改`:

- Use `kind: "single_choice"`.
- Use `options: [{ "id": "accept", "label": "同意" }]`.
- Set `allow_other: true`; UI convention renders this alternate path as
  `要修改`.
- Do not add `other_label`; the label is a UI convention, not protocol data.
- Answer validation is unchanged: accepted conclusions use `option_id`; custom
  corrections use `text`; agent judgment uses `kind: "agent_decide"`.

The prompt should be a concrete recommendation, normally `我建议 X。对吗？`,
where `X` is the durable content claim that would enter context artifacts.
When `X` is easier to read as a list or table, keep `prompt` as a short title
sentence and put the structured body in optional `claim.rows`.

`claim.rows` is an array of `{ "label"?: string, "value": string }`; when
`claim` is present it must contain at least one row, every `value` must be
non-empty, and any `label` must be non-empty. Rendering convention:

- rows without labels render as a bullet list.
- any row with a label renders the whole claim as a two-column table
  (`label | value`), with unlabeled rows leaving the label cell blank.

## Workflow Rounds

A run may begin with an optional warm-up round hosted by kickoff. It contains
only repository-specific questions whose answers are shared across artifacts,
such as repository shape, project identity, or the validation entrypoint. When
repository evidence already resolves them, emit no warm-up round.

After warm-up, init expands the artifact plan from the kickoff map and the
repository-local manifest. Each artifact then completes its own scan, draft,
confirmation, write, and seal loop. A per-artifact round is emitted only when
that artifact has pending intent that repository evidence cannot resolve. An
artifact with no pending intent seals without a pause, and pending intent from
different artifacts must never be merged into one round.

Questions are not divided into global workflow categories. Answers that can be
verified from repository evidence are recorded as observed; answers that the
repository cannot decide proceed through intent confirmation for their owning
artifact.

Question admission is evaluated per candidate. Common engineering knowledge
that would apply to any comparable project does not become a Claim. Comparable
projects are judged within the target project's language and ecosystem, so
guidance universal across that ecosystem is still common engineering knowledge.
Current repository behavior may be recorded as observed, but its normative
shadow is neither tracked nor asked. There is no fixed question count, minimum
quota, or confidence threshold; question count is the result of filtering
admitted candidates, not a target.

When one artifact has more admitted questions than the runtime batch limit,
continue in artifact-scoped overflow rounds split at semantic boundaries.

## Runtime Wrapper and Backend Resume

Protocol v1.1 requires a `needs_input` segment result to carry one complete
waiting round:

- single-question rounds use `question`.
- multi-question rounds use `questions` with 1 to 8 questions.
- do not include both `question` and `questions`.
- one round creates one `waiting_for_input` pause.
- question-level answers may be saved independently.
- the job resumes only after the whole round is submitted.
- backend re-enqueues only when the submitted round has no pending questions.
- resume is unified through PromptEnvelope `question_answer` parts; the runtime
  continues from the paused segment instead of restarting the workflow.

No extra backend lifecycle mechanism is required for v1.1 beyond the existing
question round pause/submit/resume path.

## Round Metadata Boundary

Current `question-v1.json` keeps `round` as required per-question display
metadata. Runtime batch validation requires every question in `questions[]` to
carry matching `round.title` and `round.summary`.

This `round` object is display metadata, not backend grouping authority. The
backend creates and owns the persistent question-round identity and lifecycle
when it stores the segment result. If a future protocol moves round metadata to
a wrapper-level object, update the schema, runtime validation, backend parser,
API tests, and frontend display together. Do not silently treat the current
per-question `round` field as a stable grouping key.

## Rationale and Sources

Every question must include `rationale` and `sources` so the user can see why
the interruption exists. These fields support display and audit discipline; they
must not leak raw evidence, secrets, private conversation text, large excerpts,
or unreviewed transcripts. Use short summaries and paths when useful.

Tests and reviews should check that source summaries are present, concise, and
safe to show. Raw evidence belongs in audit artifacts or repository files, not
inside the question payload.

## v1.1 Implementation Split

Implementation tickets can split along these boundaries:

- runtime wrapper validation/prompting: `needs_input` with `question` or a full
  round `questions[]`, max 8, shared round display metadata.
- backend parser/storage/lifecycle: persist one round, allow question-level
  answers, submit round, reject incomplete/expired/submitted rounds, re-enqueue
  only after all questions are answered.
- frontend round review: render the round as one review surface, map
  `allow_other` to `要修改`, save per-question answers, submit the round
  explicitly. TOK-232 owns this frontend implementation work.
- workflow skills/prompts: generate only content questions, use an optional
  kickoff warm-up followed by per-artifact rounds only for artifacts with
  pending intent, and filter out common engineering knowledge so question count
  is the result of filtering rather than a target.

Future or related decisions deliberately left out of v1.1: notification, expiry
UX details, answer mutability after submit, respondent permissions, domain
routing, assignees, inbox behavior, and final product semantics for
`agent_decide` / skip beyond the existing answer payload.
