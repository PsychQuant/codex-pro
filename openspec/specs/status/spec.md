# status Specification

## Purpose

TBD - created by archiving change 'status-result-cancel'. Update Purpose after archive.

## Requirements

### Requirement: Status skill registration and argument parsing

The plugin SHALL expose a `/codex-pro:status` skill registered at `plugins/codex-pro/skills/status/SKILL.md` with a YAML frontmatter declaring `name: status`, a descriptive `description` block whose trigger keywords include "list result files" / "review history" / 過去結果列表 / 狀態 / observability verbiage, and an `allowed-tools` list containing at least `Bash` (for filesystem scan) and `Read` (for frontmatter parse). The skill SHALL accept an optional `--skill <name>` flag where `<name>` is one of `review`, `rescue`, `adversarial-review`. Any other flag or positional argument SHALL be rejected with a usage hint.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/status/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `status`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: --skill filter parses a valid producer name

- **WHEN** a user invokes `/codex-pro:status --skill review`
- **THEN** the skill SHALL filter the listing to only `review-*.md` filenames
- **AND** the skill SHALL accept `--skill rescue` and `--skill adversarial-review` identically

#### Scenario: Invalid --skill value is rejected

- **WHEN** a user invokes `/codex-pro:status --skill bogus`
- **THEN** the skill SHALL emit a usage hint listing the three accepted values
- **AND** the skill SHALL exit non-zero


<!-- @trace
source: status-result-cancel
updated: 2026-06-01
code:
  - README.md
  - CLAUDE.md
  - plugins/codex-pro/skills/result/SKILL.md
  - plugins/codex-pro/skills/cancel/SKILL.md
  - plugins/codex-pro/skills/status/SKILL.md
  - tests/status.sh
  - tests/cancel.sh
  - tests/run.sh
  - tests/result.sh
-->

---
### Requirement: Status invocation is read-only with no Codex interaction

The skill SHALL NOT invoke `codex-call` and SHALL NOT spawn the `codex` CLI. The skill SHALL NOT write, modify, or delete any file in `.codex-pro/` or elsewhere. The skill body in `SKILL.md` MUST NOT contain the literal strings `codex-call` or `codex exec`. This places `status` in the codex-pro read-only category alongside `setup` (and the sibling `result` / `cancel` skills landed in the same change), in deliberate contrast to the producer skills (`review` / `rescue` / `adversarial-review`) which write to `.codex-pro/` and invoke `codex-call`, and the `batch` exception which invokes `codex exec`.

#### Scenario: SKILL.md does not invoke codex-call or codex exec

- **WHEN** the static layer inspects `plugins/codex-pro/skills/status/SKILL.md`
- **THEN** the body MUST NOT contain the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec`

#### Scenario: Skill does not mutate any file

- **WHEN** the skill runs end-to-end against any `.codex-pro/` state (missing / empty / populated)
- **THEN** no file SHALL be created, modified, or deleted in `.codex-pro/` or elsewhere
- **AND** no file SHALL be created outside the project root (no `~/`-rooted writes)


<!-- @trace
source: status-result-cancel
updated: 2026-06-01
code:
  - README.md
  - CLAUDE.md
  - plugins/codex-pro/skills/result/SKILL.md
  - plugins/codex-pro/skills/cancel/SKILL.md
  - plugins/codex-pro/skills/status/SKILL.md
  - tests/status.sh
  - tests/cancel.sh
  - tests/run.sh
  - tests/result.sh
-->

---
### Requirement: Status output is a markdown table of result file frontmatter summary

The skill SHALL scan `.codex-pro/*.md` (when the directory exists), parse YAML frontmatter from each file, and emit a markdown table to stdout with the columns (in order): `filename`, `skill type`, `target / task`, `outcome summary`, `timestamp`, `error`. Heterogeneous frontmatter SHALL be reconciled per the design D2 mapping: `skill type` derived from filename prefix; `target / task` from frontmatter `target` (review / adversarial-review) or `task_description` truncated to 50 characters (rescue); `outcome summary` from `findings_count` (review) or `outcome` enum value (rescue) or the literal `4/4 sections` (adversarial-review); `timestamp` from the filename ISO8601 portion truncated to date + HH:MM; `error` from frontmatter `error` field if present, else empty. Missing fields SHALL render as `—` (em dash) rather than crash or omit the row.

#### Scenario: Populated .codex-pro/ produces a markdown table

- **WHEN** a user invokes `/codex-pro:status` with a non-empty `.codex-pro/` containing one review, one rescue, and one adversarial-review result file
- **THEN** stdout MUST contain a markdown table with the six column headers in order
- **AND** the table MUST contain exactly three rows
- **AND** each row's `skill type` column MUST match the filename prefix

##### Example: heterogeneous frontmatter rendering

| filename | skill type | target / task | outcome summary | timestamp | error |
| --- | --- | --- | --- | --- | --- |
| review-20260601T120000Z.md | review | diff | 5 findings | 2026-06-01 12:00 | — |
| rescue-20260601T123000Z.md | rescue | 修復 .codex/auth.json TCC 問題 | completed | 2026-06-01 12:30 | — |
| adversarial-review-20260601T130000Z.md | adversarial-review | diff | 4/4 sections | 2026-06-01 13:00 | — |

#### Scenario: Malformed frontmatter in single file does not abort

- **WHEN** one `.codex-pro/*.md` file has invalid YAML frontmatter while other files are valid
- **THEN** the row for the malformed file SHALL display the literal string `(unparseable frontmatter)` in the `outcome summary` column
- **AND** the skill SHALL continue processing remaining files
- **AND** the skill SHALL exit 0


<!-- @trace
source: status-result-cancel
updated: 2026-06-01
code:
  - README.md
  - CLAUDE.md
  - plugins/codex-pro/skills/result/SKILL.md
  - plugins/codex-pro/skills/cancel/SKILL.md
  - plugins/codex-pro/skills/status/SKILL.md
  - tests/status.sh
  - tests/cancel.sh
  - tests/run.sh
  - tests/result.sh
-->

---
### Requirement: Status handles missing or empty .codex-pro/ as informational

The skill SHALL distinguish between three states of `.codex-pro/` and emit informational stdout (not error) for the empty and missing cases, with exit 0. State (a) `.codex-pro/` directory does not exist: the skill SHALL print a one-line note explaining that the directory is created on first producer-skill run, and exit 0. State (b) `.codex-pro/` exists but contains zero `*.md` files: the skill SHALL print `No result files found` and exit 0. State (c) populated: render the markdown table per the prior requirement. The skill MUST NOT create `.codex-pro/` as a side effect of running status.

#### Scenario: Missing .codex-pro/ directory is informational

- **WHEN** a user invokes `/codex-pro:status` in a project whose `.codex-pro/` directory does not exist
- **THEN** stdout MUST contain a one-line note referencing first producer-skill creation
- **AND** the skill MUST NOT create `.codex-pro/`
- **AND** the skill SHALL exit 0

#### Scenario: Empty .codex-pro/ directory is informational

- **WHEN** a user invokes `/codex-pro:status` with an empty `.codex-pro/` directory (zero `*.md` files)
- **THEN** stdout MUST contain the literal string `No result files found`
- **AND** the skill SHALL exit 0

<!-- @trace
source: status-result-cancel
updated: 2026-06-01
code:
  - README.md
  - CLAUDE.md
  - plugins/codex-pro/skills/result/SKILL.md
  - plugins/codex-pro/skills/cancel/SKILL.md
  - plugins/codex-pro/skills/status/SKILL.md
  - tests/status.sh
  - tests/cancel.sh
  - tests/run.sh
  - tests/result.sh
-->