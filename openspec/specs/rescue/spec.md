# rescue Specification

## Purpose

The rescue capability provides task delegation to Codex via `/codex-pro:codex-rescue`, accepting a required task description plus optional `--context <path>` (repeatable), `--criteria <text>`, and the mutually-exclusive pair `--resume <session-id>` / `--fresh` for session continuity. Rescue invokes the `codex-call` HTTPS-direct wrapper with a hard timeout — explicitly NOT spawning the `codex` CLI subprocess — and therefore joins `review` as the canonical adherence example for codex-pro Design constraint #1, in deliberate contrast to the `batch` capability which is the only documented exception. Output is written to a structured Markdown file at `.codex-pro/rescue-<ISO8601-timestamp>.md` with a YAML frontmatter (eight fields including `outcome` enum of `completed` / `partial` / `unclear` / `requires_external`, plus optional `error` and `resume_from`) and a body containing three sections: `## Task Brief`, `## Outcome`, `## Suggested Next Steps`. Failures fail-fast across four classes — rate limit, OAuth invalid, hard timeout, and **task_unclear** (rescue-specific; Codex cannot commit an answer). The `task_unclear` class is the direct counter to upstream `openai/codex-plugin-cc` issue #324 silent-stub return: instead of stubbing a placeholder answer, the skill MUST emit `outcome: unclear` + `error: task_unclear` so the unanswerability becomes an explicit, machine-readable state. No class triggers retry, matching the no-retry circuit-breaker discipline shared with `review`. This v0.1 is single-oracle delegation; ensemble multi-reviewer pattern is reserved for v0.2.

## Requirements

### Requirement: Rescue skill registration and argument parsing

The plugin SHALL expose a `/codex-pro:codex-rescue` skill registered at `plugins/codex-pro/skills/codex-rescue/SKILL.md` with a YAML frontmatter declaring `name: codex-rescue`, a descriptive `description` block, and an `allowed-tools` list containing at least `Bash` (for `codex-call` invocation) and `Read` (for context file collection). The skill SHALL accept a required positional task description argument and two optional flags: `--context <path>` (may repeat) for additional context files and `--criteria <text>` for completion criteria. The skill SHALL abort with a usage hint when invoked with an empty task description. Every invocation is a stateless single-shot codex-call (no session continuity); the `--resume` / `--fresh` flags from v0.1 are removed in v0.1.1 because the underlying `codex-call` Swift wrapper has no `--session` flag and cannot support session continuation without upstream changes.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-rescue/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-rescue`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: Task description with optional flags is parsed

- **WHEN** a user invokes `/codex-pro:codex-rescue 修復 .codex/auth.json TCC 問題 --context plugins/codex-pro/skills/codex-setup/SKILL.md --criteria "OAuth check returns ✓"`
- **THEN** the skill SHALL extract `修復 .codex/auth.json TCC 問題` as the task description
- **AND** the skill SHALL collect the contents of `plugins/codex-pro/skills/codex-setup/SKILL.md` as additional context
- **AND** the skill SHALL incorporate `OAuth check returns ✓` into the codex-call instructions as the success rubric

#### Scenario: Empty task description aborts with usage hint

- **WHEN** a user invokes `/codex-pro:codex-rescue` with no positional task description argument (only flags or completely empty)
- **THEN** the skill SHALL abort without invoking codex-call
- **AND** the skill SHALL emit a usage hint listing the required and optional argument forms (task description plus `--context`, `--criteria`)

#### Scenario: Session continuity flags are not accepted

- **WHEN** a user invokes `/codex-pro:codex-rescue <task> --resume sess_xyz` or `/codex-pro:codex-rescue <task> --fresh`
- **THEN** the skill SHALL emit a clear error explaining that session continuity is removed in v0.1.1 because `codex-call` has no `--session` flag
- **AND** the error message SHALL mention that the limitation is tracked for future restoration when upstream `codex-call` gains session-tagging support
- **AND** the skill SHALL NOT invoke codex-call


<!-- @trace
source: rename-skills-codex-prefix
updated: 2026-07-07
code:
  - tests/adversarial-review.sh
  - plugins/codex-pro/skills/adversarial-review/SKILL.md
  - tests/result.sh
  - plugins/codex-pro/skills/codex-setup/SKILL.md
  - tests/status.sh
  - CLAUDE.md
  - tests/cancel.sh
  - tests/static.sh
  - plugins/codex-pro/skills/result/SKILL.md
  - tests/rescue.sh
  - plugins/codex-pro/skills/codex-batch/SKILL.md
  - plugins/codex-pro/skills/codex-review/SKILL.md
  - tests/batch.sh
  - tests/e2e-checklist.md
  - plugins/codex-pro/skills/codex-batch/references/script-template.sh
  - plugins/codex-pro/skills/codex-cancel/SKILL.md
  - README.md
  - plugins/codex-pro/skills/batch/SKILL.md
  - plugins/codex-pro/skills/codex-rescue/SKILL.md
  - plugins/codex-pro/skills/rescue/SKILL.md
  - tests/config.sh
  - tests/review.sh
  - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
  - plugins/codex-pro/skills/cancel/SKILL.md
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - tests/setup.sh
  - plugins/codex-pro/skills/config/SKILL.md
  - plugins/codex-pro/skills/status/SKILL.md
  - plugins/codex-pro/skills/codex-config/SKILL.md
  - plugins/codex-pro/skills/setup/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
  - plugins/codex-pro/skills/review/SKILL.md
  - plugins/codex-pro/skills/batch/references/script-template.sh
-->

---
### Requirement: Rescue invocation uses codex-call HTTPS direct without subprocess for Codex

The skill SHALL invoke the `codex-call` Swift wrapper (provided by the `parallel-ai-agents` runtime dependency) to delegate the task to Codex. The skill MUST NOT spawn the `codex` CLI as a subprocess. This requirement places `rescue` alongside `review` as the canonical adherence pattern for codex-pro Design constraint #1 ("No subprocess spawn for Codex"), in deliberate contrast to the `batch` capability which is the documented explicit exception. The skill MUST pass `--model`, `--effort`, and `--max-time` flags to `codex-call` whose values come from the resolved profile (per the `config` capability). When no profile is set or the field is absent, hardcoded defaults SHALL apply: `--model gpt-5.6-sol` / `--effort xhigh` / `--max-time 600` (the 2026-07 default bump per issue #3: `gpt-5.6-sol` is the only 5.6-generation model the codex-call ChatGPT-account backend-api path accepts — verified empirically 2026-07-10; users with a profile override are unaffected, 100% backward compatible). The frontmatter description block in SKILL.md SHALL contain the literal substring `v0.2 — profile-aware` to make the v0.1.1 → v0.2 version bump discoverable. Rescue remains stateless per-invocation (no session continuity; the `--resume` / `--fresh` flags from v0.1 remain removed per the v0.1.1 fix because `codex-call` has no `--session` flag).

#### Scenario: SKILL.md contains codex-call invocation

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-rescue/SKILL.md`
- **THEN** the body SHALL contain at least one occurrence of the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec` (the subprocess form is the batch exception, not allowed here)

#### Scenario: codex-call invocation includes hard timeout flag (default 600)

- **WHEN** the skill body documents the codex-call invocation
- **THEN** the documented invocation MUST include the `--max-time` flag with the literal substring `600` (the default fallback when the resolved profile has no `max_time` override)
- **AND** the documented invocation MUST NOT reference `--resume` / `--fresh` flag handling (those flags were removed in v0.1.1 and have not been restored)

#### Scenario: SKILL.md frontmatter announces v0.2 — profile-aware

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-rescue/SKILL.md`
- **THEN** the frontmatter `description` MUST contain the literal substring `v0.2 — profile-aware`

#### Scenario: Producer reads profile via inline python3 before codex-call

- **WHEN** the SKILL.md Step 4 body documents the codex-call invocation
- **THEN** the body MUST contain an inline `python3` block that reads `~/.codex-pro/profile.yaml` and `.codex-pro/profile.yaml`
- **AND** the documented invocation MUST pass `--model "$MODEL"` / `--effort "$EFFORT"` / `--max-time "$MAX_TIME"` (or equivalent shell-variable expansion from the python3 output)
- **AND** the body MUST mention the hardcoded defaults `gpt-5.6-sol` / `xhigh` / `600` as fallbacks


<!-- @trace
source: bump-default-model-gpt56sol
updated: 2026-07-11
code:
  - plugins/codex-pro/skills/codex-rescue/SKILL.md
  - tests/adversarial-review.sh
  - plugins/codex-pro/skills/codex-batch/references/script-template.sh
  - CLAUDE.md
  - plugins/codex-pro/skills/codex-batch/SKILL.md
  - plugins/codex-pro/skills/codex-config/SKILL.md
  - tests/static.sh
  - plugins/codex-pro/skills/codex-review/SKILL.md
  - tests/status.sh
  - tests/config.sh
  - tests/batch.sh
  - README.md
  - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
-->

---
### Requirement: Rescue output is a structured Markdown result file

The skill SHALL write the Codex rescue output to a Markdown file at `.codex-pro/rescue-<ISO8601-timestamp>.md` inside the project root. The directory `.codex-pro/` MUST be created on first run if absent. The result file MUST contain a YAML frontmatter block with the required fields `task_description`, `session_id`, `model`, `effort`, `timestamp`, and `outcome`; and an optional `error` field when a fail-fast condition fires. The `session_id` field records whatever conversation identifier codex-call surfaces from its HTTP response (or `null` when codex-call does not surface one); it does NOT imply any session-continuation capability. The `resume_from` field from v0.1 remains removed because session continuity is not supported (per the v0.1.1 fix). An optional v0.2 `profile_source` field MAY appear with one of four enum values: `default` (all 3 producer-relevant fields hardcoded), `global` (at least one field from global, none from project), `project` (at least one field from project, no global-only fields), or `mixed` (at least one global field AND at least one project field). v0.1.1 result files without `profile_source` remain valid (`/codex-pro:codex-status` and `/codex-pro:codex-result` MUST tolerate missing `profile_source`). The `outcome` field MUST be one of the four enum values: `completed`, `partial`, `unclear`, `requires_external`. On success (any outcome except fail-fast), the body MUST contain three sections: `## Task Brief`, `## Outcome`, and `## Suggested Next Steps`. The skill MUST NOT return the outcome inline to Claude as the primary delivery path; the result file is the contract — this discipline prevents the silent-stub failure mode (issue #324 from upstream `openai/codex-plugin-cc`).

#### Scenario: Success case writes structured result file

- **WHEN** a rescue completes (outcome `completed`, `partial`, or `requires_external`)
- **THEN** `.codex-pro/rescue-<timestamp>.md` MUST exist with YAML frontmatter containing the six required fields plus `outcome` (one of the four enum values)
- **AND** the body MUST contain `## Task Brief`, `## Outcome`, and `## Suggested Next Steps` sections

##### Example: minimal success frontmatter

| Field            | Example value                                  |
| ---------------- | ---------------------------------------------- |
| task_description | `修復 .codex/auth.json TCC 問題`               |
| session_id       | `null`                                         |
| model            | `gpt-5.6-sol`                                  |
| effort           | `xhigh`                                        |
| timestamp        | `2026-06-01T22:00:48+08:00`                    |
| outcome          | `completed`                                    |

#### Scenario: profile_source frontmatter field reflects resolution source

- **WHEN** a rescue runs with no profile set
- **THEN** the result file frontmatter MAY include `profile_source: default` (v0.2 producer SHOULD emit it; v0.1.1 compat layer for missing-field reads is intact)
- **WHEN** a rescue runs with a project profile that only sets `model`
- **THEN** the result file frontmatter `profile_source` MAY be `project`

#### Scenario: First run creates output directory

- **WHEN** the skill runs and `.codex-pro/` does not exist
- **THEN** the skill SHALL create the directory before writing the result file
- **AND** the directory creation failure (permissions, read-only filesystem) MUST abort the skill with a clear error and MUST NOT silently fall back to writing elsewhere


<!-- @trace
source: bump-default-model-gpt56sol
updated: 2026-07-11
code:
  - plugins/codex-pro/skills/codex-rescue/SKILL.md
  - tests/adversarial-review.sh
  - plugins/codex-pro/skills/codex-batch/references/script-template.sh
  - CLAUDE.md
  - plugins/codex-pro/skills/codex-batch/SKILL.md
  - plugins/codex-pro/skills/codex-config/SKILL.md
  - tests/static.sh
  - plugins/codex-pro/skills/codex-review/SKILL.md
  - tests/status.sh
  - tests/config.sh
  - tests/batch.sh
  - README.md
  - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
-->

---
### Requirement: Rescue failures trigger circuit-breaker fail-fast across four classes

When the underlying `codex-call` invocation fails or Codex itself reports the task as unanswerable, the skill SHALL fail fast across four classes — rate-limit response, OAuth-invalid response, hard-timeout exhaustion, and task-unclear (Codex unable to commit an answer). The skill MUST NOT retry the request, MUST still write the result file with a YAML frontmatter `error` field naming the failure class (`rate_limit` / `oauth_invalid` / `timeout` / `task_unclear`), MUST set the `outcome` field to `unclear` for the `task_unclear` case (or leave `outcome` consistent with the partial state for the other three classes), and MUST report a remediation message to the user identifying the failure class. The `task_unclear` class is rescue-specific and directly counters the silent-stub failure mode (upstream issue #324) by making "Codex does not have an answer" an explicit and machine-readable state instead of a stubbed placeholder string.

#### Scenario: Rate-limit response writes error frontmatter and stops

- **WHEN** `codex-call` exits non-zero with output containing "rate limit" or HTTP status 429
- **THEN** the result file MUST be written with YAML frontmatter `error: rate_limit`
- **AND** the skill MUST NOT retry the codex-call invocation

#### Scenario: OAuth-invalid response writes error frontmatter and stops

- **WHEN** `codex-call` exits non-zero with output containing "auth" or HTTP status 401
- **THEN** the result file MUST be written with YAML frontmatter `error: oauth_invalid`
- **AND** the skill MUST emit a remediation message directing the user to run `/codex-pro:codex-setup`

#### Scenario: Timeout exhaustion writes error frontmatter and stops

- **WHEN** `codex-call` exceeds the `--max-time 600` hard timeout
- **THEN** the result file MUST be written with YAML frontmatter `error: timeout`
- **AND** the skill MUST emit a remediation message suggesting a narrower task scope or splitting the task into sub-tasks

#### Scenario: Task-unclear response writes error and outcome unclear

- **WHEN** Codex output indicates it cannot commit an answer (outcome `unclear` or explicit refusal)
- **THEN** the result file MUST be written with YAML frontmatter `error: task_unclear` AND `outcome: unclear`
- **AND** the skill MUST emit a remediation message suggesting the user add completion criteria via `--criteria` or break the task into smaller sub-tasks
- **AND** the skill MUST NOT silently substitute a stubbed answer in the body

<!-- @trace
source: rescue-minimal
updated: 2026-06-01
code:
  - README.md
  - plugins/codex-pro/skills/rescue/SKILL.md
  - tests/rescue.sh
  - CLAUDE.md
  - tests/run.sh
-->
