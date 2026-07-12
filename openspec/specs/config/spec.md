# config Specification

## Purpose

TBD - created by archiving change 'config-profile-mechanism'. Update Purpose after archive.

## Requirements

### Requirement: Config skill registration with zero-argument display

The plugin SHALL expose a `/codex-pro:codex-config` skill registered at `plugins/codex-pro/skills/codex-config/SKILL.md` with a YAML frontmatter declaring `name: codex-config`, a descriptive `description` block whose trigger keywords are codex-qualified — `codex profile` / `codex config` / `show resolved profile` / `which model` — and MUST NOT list the bare standalone terms `設定`, `配置`, `settings`, or `config` as trigger keywords (these generic terms caused the collision with the system `/config` command that this change resolves). The `allowed-tools` list MUST contain at least `Bash` (for filesystem scan + python3 parse) and `Read` (for profile YAML inspection). The skill SHALL accept zero arguments. Any argument SHALL be silently ignored (the script still proceeds to display the profile — argument has no effect on output).

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-config/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-config`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`
- **AND** the frontmatter `description` MUST contain the substring `profile`
- **AND** the frontmatter `description` MUST NOT contain the bare standalone trigger terms `設定` or `配置`

#### Scenario: Zero-argument invocation displays resolved profile

- **WHEN** a user invokes `/codex-pro:codex-config` with no arguments
- **THEN** the skill SHALL emit a 4-row markdown table to stdout with columns `field`, `resolved value`, `source`
- **AND** the skill SHALL emit two informational lines: `Global profile: ~/.codex-pro/profile.yaml (exists / does not exist)` and `Project profile: .codex-pro/profile.yaml (exists / does not exist)`
- **AND** the skill SHALL exit 0

#### Scenario: Argument is silently ignored

- **WHEN** a user invokes `/codex-pro:codex-config something extra` or `/codex-pro:codex-config --flag`
- **THEN** the skill SHALL proceed to display the resolved profile as if invoked with no argument
- **AND** the skill SHALL exit 0


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
### Requirement: Config invocation is read-only consumer with no Codex interaction

The skill SHALL NOT invoke `codex-call` and SHALL NOT spawn the `codex` CLI. The skill SHALL NOT write, modify, or delete any file. The skill SHALL NOT create `~/.codex-pro/` or `<project>/.codex-pro/` directories. The skill body in `SKILL.md` MUST NOT contain the literal strings `codex-call` or `codex exec`. This places `config` in the codex-pro read-only consumer category alongside `setup` / `status` / `result` / `cancel`, in deliberate contrast to mutating producer skills (`review` / `rescue` / `adversarial-review`) and the `batch` exception.

#### Scenario: SKILL.md does not invoke codex-call or codex exec

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-config/SKILL.md`
- **THEN** the body MUST NOT contain the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec`

#### Scenario: Skill does not mutate any file or directory

- **WHEN** the skill runs end-to-end against any profile state (both missing / only global / only project / mixed)
- **THEN** no file SHALL be created, modified, or deleted
- **AND** no directory SHALL be created (specifically NOT `~/.codex-pro/` or `<project>/.codex-pro/`)


<!-- @trace
source: config-profile-mechanism
updated: 2026-06-07
code:
  - plugins/codex-pro/.claude-plugin/plugin.json
  - tests/config.sh
  - plugins/codex-pro/skills/codex-review/SKILL.md
  - tests/e2e-checklist.md
  - tests/review.sh
  - CLAUDE.md
  - plugins/codex-pro/skills/codex-rescue/SKILL.md
  - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
  - README.md
  - tests/e2e.sh
  - tests/run.sh
  - tests/adversarial-review.sh
  - plugins/codex-pro/skills/codex-config/SKILL.md
  - tests/lib/e2e-fixtures.sh
  - tests/rescue.sh
-->

---
### Requirement: Config profile resolution algorithm — two-layer with project priority

The skill SHALL resolve the effective profile by loading two YAML files in order: (1) `~/.codex-pro/profile.yaml` as the global layer; (2) `<cwd>/.codex-pro/profile.yaml` as the project layer (where `<cwd>` is the invocation working directory). Field-level merging applies: a field present in the project layer SHALL override the same field in the global layer; a field present only in the global layer SHALL apply; a field absent from both layers SHALL fall back to hardcoded defaults (`model: gpt-5.6-sol`, `effort: xhigh`, `max_time: 600`, `focus_default: ""` (empty string)). Resolution SHALL be lazy per invocation — no caching between runs. Missing files (either layer) SHALL be treated as an empty layer and SHALL NOT raise an error. Malformed YAML (parse failure) SHALL be treated as an empty layer (silent fallback for that layer). Unknown fields in profile YAML SHALL be silently ignored (forward-compat with future schema additions). Field type mismatches (e.g. `max_time: "abc"` instead of int) SHALL cause that single field to fall back to its hardcoded default (other fields unaffected).

#### Scenario: Both layers missing — all defaults

- **WHEN** the skill runs in an environment where neither `~/.codex-pro/profile.yaml` nor `<cwd>/.codex-pro/profile.yaml` exists
- **THEN** the resolved profile SHALL contain all hardcoded defaults
- **AND** all 4 rows in the output table SHALL show source `(default)`

#### Scenario: Only global layer — global wins for set fields

- **WHEN** the skill runs with `~/.codex-pro/profile.yaml` containing `{model: gpt-5.0}` and no project file
- **THEN** the resolved profile SHALL set `model` to `gpt-5.0` with source `global`
- **AND** the other 3 fields SHALL show source `(default)`

#### Scenario: Project layer overrides global for set fields

- **WHEN** the skill runs with `~/.codex-pro/profile.yaml` containing `{model: gpt-5.0, max_time: 900}` and `<cwd>/.codex-pro/profile.yaml` containing `{max_time: 1200}`
- **THEN** the resolved profile SHALL set `model` to `gpt-5.0` with source `global`
- **AND** SHALL set `max_time` to `1200` with source `project`
- **AND** the other 2 fields SHALL show source `(default)`

#### Scenario: Malformed YAML silently falls back

- **WHEN** the skill runs with `<cwd>/.codex-pro/profile.yaml` containing invalid YAML (e.g. a missing colon)
- **THEN** the project layer SHALL be treated as empty
- **AND** the skill SHALL NOT raise an error
- **AND** the skill SHALL exit 0 with the global layer (or defaults) applied

#### Scenario: Unknown profile field is silently ignored

- **WHEN** the skill runs with `<cwd>/.codex-pro/profile.yaml` containing `{model: gpt-5.0, future_field: foo}`
- **THEN** the resolved profile SHALL set `model` to `gpt-5.0`
- **AND** the output table SHALL NOT include a row for `future_field` (only the 4 known fields)


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
### Requirement: Config v0.1 schema is exactly 4 fields

The v0.1 profile schema SHALL contain exactly 4 fields with the types and defaults specified below. The `/codex-pro:codex-config` output table SHALL contain exactly 4 rows, one per schema field, in the listed order.

| Field | YAML type | Hardcoded default | Producer skills that use it |
| --- | --- | --- | --- |
| `model` | string | `gpt-5.6-sol` | review / rescue / adversarial-review |
| `effort` | string | `xhigh` | review / rescue / adversarial-review |
| `max_time` | int (seconds) | `600` | review / rescue / adversarial-review |
| `focus_default` | string | `""` (empty) | adversarial-review only |

`max_findings`, `sandbox`, retry/backoff, timeout-per-skill, multi-profile, named profiles, env-var overrides, model-escalation fields, and schema versioning are explicitly OUT of v0.1 scope (the model-escalation field was evaluated and rejected during issue #3: `gpt-5.6-sol` is already the top available model on the codex-call path, so an escalation target does not exist).

#### Scenario: Output table has exactly 4 rows in canonical order

- **WHEN** a user invokes `/codex-pro:codex-config`
- **THEN** the output table body SHALL contain exactly 4 rows
- **AND** the rows SHALL appear in this order: `model`, `effort`, `max_time`, `focus_default`

##### Example: full default state

| field          | resolved value | source    |
| -------------- | -------------- | --------- |
| model          | gpt-5.6-sol    | (default) |
| effort         | xhigh          | (default) |
| max_time       | 600            | (default) |
| focus_default  |                | (default) |

#### Scenario: focus_default is read by adversarial-review only

- **WHEN** the resolved profile sets `focus_default: security` and `/codex-pro:codex-adversarial-review` is invoked WITHOUT a `--focus` argument
- **THEN** the adversarial-review skill SHALL use `security` as the focus value
- **WHEN** `/codex-pro:codex-review` or `/codex-pro:codex-rescue` is invoked under the same profile
- **THEN** the `focus_default` field SHALL NOT affect their behavior (silently unused)

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
