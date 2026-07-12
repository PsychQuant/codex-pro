# cancel Specification

## Purpose

TBD - created by archiving change 'status-result-cancel'. Update Purpose after archive.

## Requirements

### Requirement: Cancel skill registration with zero-argument acceptance

The plugin SHALL expose a `/codex-pro:codex-cancel` skill registered at `plugins/codex-pro/skills/codex-cancel/SKILL.md` with a YAML frontmatter declaring `name: codex-cancel`, a descriptive `description` block whose trigger keywords MUST include the literal substring `informational only` (mental-model anchor for users so they do not expect real cancellation), and an `allowed-tools` list containing at least `Bash`. The skill SHALL accept zero arguments. Any argument (positional or flag) SHALL be rejected with a usage hint that re-states the "informational only" nature, but the skill SHALL still exit 0 even when given arguments — because cancel is never an error, only a displayed limitation.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-cancel/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-cancel`
- **AND** the frontmatter `description` MUST contain the literal substring `informational only`

#### Scenario: Zero-argument invocation succeeds

- **WHEN** a user invokes `/codex-pro:codex-cancel` with no arguments
- **THEN** the skill SHALL emit the explainer plus three remediation lines to stdout
- **AND** the skill SHALL exit 0

#### Scenario: Argument is rejected with usage but still exit 0

- **WHEN** a user invokes `/codex-pro:codex-cancel pid 12345` or `/codex-pro:codex-cancel --job abc`
- **THEN** the skill SHALL emit a usage hint stating that cancel accepts no arguments and is informational only
- **AND** the skill SHALL exit 0 (cancel never errors)


<!-- @trace
source: rename-skills-codex-prefix
updated: 2026-07-07
code:
  - tests/adversarial-review.sh
  - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
  - tests/result.sh
  - plugins/codex-pro/skills/codex-setup/SKILL.md
  - tests/status.sh
  - CLAUDE.md
  - tests/cancel.sh
  - tests/static.sh
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - tests/rescue.sh
  - plugins/codex-pro/skills/codex-batch/SKILL.md
  - plugins/codex-pro/skills/codex-review/SKILL.md
  - tests/batch.sh
  - tests/e2e-checklist.md
  - plugins/codex-pro/skills/codex-batch/references/script-template.sh
  - plugins/codex-pro/skills/codex-cancel/SKILL.md
  - README.md
  - plugins/codex-pro/skills/codex-rescue/SKILL.md
  - tests/config.sh
  - tests/review.sh
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - tests/setup.sh
  - plugins/codex-pro/skills/codex-config/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
-->

---
### Requirement: Cancel is an informational read-only no-op

The skill SHALL NOT invoke `codex-call`. The skill SHALL NOT spawn the `codex` CLI. The skill SHALL NOT send any HTTPS request. The skill SHALL NOT signal any process (no SIGTERM, no SIGKILL, no `kill` invocation). The skill SHALL NOT write, modify, or delete any file. The skill SHALL NOT create `.codex-pro/`. The skill body in `SKILL.md` MUST NOT contain the literal strings `codex-call` or `codex exec` (it does not invoke codex). The skill body MUST NOT contain the literal strings `kill`, `SIGTERM`, or `SIGKILL` invoked as commands (mentions of these terms in the explainer prose to *deny* their use are permitted only if they make the no-op contract explicit). This places `cancel` alongside `status` and `result` in the codex-pro read-only category, with the additional constraint that cancel is strictly stdout-only — no filesystem reads beyond loading SKILL.md itself.

#### Scenario: SKILL.md does not invoke codex-call or codex exec

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-cancel/SKILL.md`
- **THEN** the body MUST NOT contain the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec`

#### Scenario: Skill does not signal or mutate

- **WHEN** the skill runs end-to-end
- **THEN** no process MUST be signalled (no `kill` invocation, no SIGTERM, no SIGKILL)
- **AND** no file MUST be created, modified, or deleted anywhere
- **AND** no HTTPS request MUST be sent


<!-- @trace
source: status-result-cancel
updated: 2026-06-01
code:
  - README.md
  - CLAUDE.md
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/skills/codex-cancel/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - tests/status.sh
  - tests/cancel.sh
  - tests/run.sh
  - tests/result.sh
-->

---
### Requirement: Cancel output contains the stateless-explainer plus three remediation lines

The skill SHALL print an explainer paragraph stating that codex-pro v0.2 is single-shot stateless, codex-call is synchronous HTTPS, no background job exists, no upstream cancel API on chatgpt.com/backend-api — therefore there is nothing for cancel to terminate. The skill SHALL follow the explainer with three numbered remediation lines: (1) press Ctrl-C in the Claude Code session, (2) wait for the `--max-time 600` hard timeout, (3) wait for future codex-pro v0.3+ background-job mode. The skill SHALL close with the literal sentence `This message is not an error. exit 0.` The output SHALL be deterministic — identical wording on every invocation — so users can recognise it as a known displayed limitation rather than a transient failure.

#### Scenario: Explainer contains required substrings

- **WHEN** a user invokes `/codex-pro:codex-cancel`
- **THEN** stdout MUST contain the substring `stateless`
- **AND** stdout MUST contain the substring `Ctrl-C`
- **AND** stdout MUST contain the substring `--max-time 600`
- **AND** stdout MUST contain the substring `v0.3` or `future`
- **AND** stdout MUST contain the substring `not an error`

#### Scenario: Output is deterministic across invocations

- **WHEN** a user invokes `/codex-pro:codex-cancel` twice in succession
- **THEN** the two stdout outputs MUST be byte-identical

<!-- @trace
source: status-result-cancel
updated: 2026-06-01
code:
  - README.md
  - CLAUDE.md
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/skills/codex-cancel/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - tests/status.sh
  - tests/cancel.sh
  - tests/run.sh
  - tests/result.sh
-->
