# result Specification

## Purpose

TBD - created by archiving change 'status-result-cancel'. Update Purpose after archive.

## Requirements

### Requirement: Result skill registration and selection-mode argument parsing

The plugin SHALL expose a `/codex-pro:codex-result` skill registered at `plugins/codex-pro/skills/codex-result/SKILL.md` with a YAML frontmatter declaring `name: codex-result`, a descriptive `description` block whose trigger keywords are codex-qualified — `show codex result file` / `display codex review output` / `顯示 codex 結果` — and MUST NOT list the bare standalone term `顯示結果` as a trigger keyword. The `allowed-tools` list MUST contain at least `Bash` and `Read`. The skill SHALL accept three mutually-exclusive selection modes: (a) a positional `<filename>` argument naming a file in `.codex-pro/` (filename only, no path prefix); (b) `--latest <skill>` where `<skill>` is one of the producer result-file prefixes `review`, `rescue`, `adversarial-review` (bare producer identifiers — result-file naming is intentionally decoupled from the `codex-`-prefixed invocation name and is unchanged by this rename); (c) `--latest` with no argument (selects the most recent result file across all producer skills). Supplying both a positional filename and `--latest` SHALL be rejected as a usage error.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-result/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-result`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: Positional filename selects a specific file

- **WHEN** a user invokes `/codex-pro:codex-result review-20260601T120000Z.md` with that file present in `.codex-pro/`
- **THEN** the skill SHALL display the full content of `.codex-pro/review-20260601T120000Z.md` to stdout

#### Scenario: --latest with skill selects most recent of that producer

- **WHEN** a user invokes `/codex-pro:codex-result --latest rescue` with multiple `rescue-*.md` files in `.codex-pro/`
- **THEN** the skill SHALL select the rescue file with the highest filename lexical order
- **AND** the skill SHALL display its content to stdout

#### Scenario: --latest without argument selects most recent across all producers

- **WHEN** a user invokes `/codex-pro:codex-result --latest` with mixed-producer files in `.codex-pro/`
- **THEN** the skill SHALL select the file with the highest filename lexical order regardless of producer prefix
- **AND** the skill SHALL display its content to stdout

#### Scenario: Conflicting arguments are rejected

- **WHEN** a user invokes `/codex-pro:codex-result review-20260601T120000Z.md --latest`
- **THEN** the skill SHALL emit a usage hint explaining the modes are mutually exclusive
- **AND** the skill SHALL exit non-zero
- **AND** the skill SHALL NOT display any file content


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
  - plugins/codex-pro/skills/codex-batch/SKILL.md
  - plugins/codex-pro/skills/codex-rescue/SKILL.md
  - plugins/codex-pro/skills/codex-rescue/SKILL.md
  - tests/config.sh
  - tests/review.sh
  - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
  - plugins/codex-pro/skills/codex-cancel/SKILL.md
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - tests/setup.sh
  - plugins/codex-pro/skills/codex-config/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - plugins/codex-pro/skills/codex-config/SKILL.md
  - plugins/codex-pro/skills/codex-setup/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
  - plugins/codex-pro/skills/codex-review/SKILL.md
  - plugins/codex-pro/skills/codex-batch/references/script-template.sh
-->

---
### Requirement: Result invocation is read-only with no Codex interaction

The skill SHALL NOT invoke `codex-call` and SHALL NOT spawn the `codex` CLI. The skill SHALL NOT write, modify, or delete any file. The skill body in `SKILL.md` MUST NOT contain the literal strings `codex-call` or `codex exec`. This places `result` in the codex-pro read-only category alongside `setup` and the sibling `status` / `cancel` skills, in deliberate contrast to the producer skills (`review` / `rescue` / `adversarial-review`).

#### Scenario: SKILL.md does not invoke codex-call or codex exec

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-result/SKILL.md`
- **THEN** the body MUST NOT contain the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec`

#### Scenario: Skill does not mutate any file

- **WHEN** the skill runs end-to-end against any `.codex-pro/` state
- **THEN** no file SHALL be created, modified, or deleted in `.codex-pro/` or elsewhere


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
### Requirement: Result selection uses filename lexical order as the timestamp authority

The skill SHALL determine "most recent" exclusively by lexical comparison of filenames within the `.codex-pro/` directory. The skill MUST NOT consult filesystem `mtime` or frontmatter `timestamp` field for selection ordering. This relies on the producer-side filename pattern `<skill>-<ISO8601-timestamp>.md` enforced by review / rescue / adversarial-review SKILL.md; any future producer that diverges from this pattern is a spec change to that producer, not to result.

#### Scenario: Lexical order matches ISO8601 chronological order

- **WHEN** a user invokes `/codex-pro:codex-result --latest review` with `.codex-pro/` containing `review-20260601T120000Z.md` and `review-20260601T133000Z.md`
- **THEN** the skill SHALL select `review-20260601T133000Z.md` (later ISO8601 timestamp)

#### Scenario: Filesystem mtime is not consulted

- **WHEN** a user invokes `/codex-pro:codex-result --latest` with `.codex-pro/` containing `review-20260601T120000Z.md` and `rescue-20260601T130000Z.md`, and the rescue file's filesystem `mtime` has been touched to an earlier time than the review file
- **THEN** the skill SHALL select `rescue-20260601T130000Z.md` (later lexical filename) regardless of `mtime`


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
### Requirement: Result fails fast with remediation when target is unresolvable

The skill SHALL fail fast (non-zero exit) when the requested file cannot be resolved, with a remediation message identifying the recovery action. Four resolution failure cases: (a) `.codex-pro/` directory missing → message points to running any producer skill; (b) `.codex-pro/` empty → message points to running any producer skill; (c) positional filename not present in `.codex-pro/` → message suggests running `/codex-pro:codex-status` to list available files; (d) `--latest <skill>` requested but zero files match that prefix → message suggests running that producer skill. The skill MUST NOT silently fall back to a different selection or display a placeholder.

#### Scenario: Missing .codex-pro/ aborts with remediation

- **WHEN** a user invokes `/codex-pro:codex-result --latest` in a project where `.codex-pro/` does not exist
- **THEN** the skill SHALL emit an error message referencing producer-skill creation as the recovery
- **AND** the skill SHALL exit non-zero
- **AND** the skill MUST NOT create `.codex-pro/`

#### Scenario: Unknown filename aborts with status remediation

- **WHEN** a user invokes `/codex-pro:codex-result bogus-20260601T120000Z.md` with that file absent from `.codex-pro/`
- **THEN** the skill SHALL emit an error message referencing `/codex-pro:codex-status` as the recovery action
- **AND** the skill SHALL exit non-zero

#### Scenario: --latest <skill> with zero matches aborts with producer remediation

- **WHEN** a user invokes `/codex-pro:codex-result --latest adversarial-review` with `.codex-pro/` containing only `review-*.md` files
- **THEN** the skill SHALL emit an error message referencing `/codex-pro:codex-adversarial-review` as the recovery action
- **AND** the skill SHALL exit non-zero

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
