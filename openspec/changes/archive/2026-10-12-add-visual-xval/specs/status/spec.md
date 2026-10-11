## MODIFIED Requirements

### Requirement: Status skill registration and argument parsing

The plugin SHALL expose a `/codex-pro:codex-status` skill registered at `plugins/codex-pro/skills/codex-status/SKILL.md` with a YAML frontmatter declaring `name: codex-status`, a descriptive `description` block whose trigger keywords are codex-qualified — `list codex result files` / `codex review history` / `過去 codex 結果列表` — and MUST NOT list the bare standalone term `狀態` as a trigger keyword. The `allowed-tools` list MUST contain at least `Bash` (for filesystem scan) and `Read` (for frontmatter parse). The skill SHALL accept an optional `--skill <name>` flag where `<name>` is one of the producer result-file prefixes `review`, `rescue`, `adversarial-review`, `visual-xval` (bare producer identifiers — result-file naming is intentionally decoupled from the `codex-`-prefixed invocation name and is unchanged by this rename). Any other flag or positional argument SHALL be rejected with a usage hint.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-status/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-status`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: --skill filter parses a valid producer name

- **WHEN** a user invokes `/codex-pro:codex-status --skill review`
- **THEN** the skill SHALL filter the listing to only `review-*.md` filenames
- **AND** the skill SHALL accept `--skill rescue`, `--skill adversarial-review`, and `--skill visual-xval` identically

#### Scenario: Invalid --skill value is rejected

- **WHEN** a user invokes `/codex-pro:codex-status --skill bogus`
- **THEN** the skill SHALL emit a usage hint listing the four accepted values
- **AND** the skill SHALL exit non-zero

### Requirement: Status output is a markdown table of result file frontmatter summary

The skill SHALL scan `.codex-pro/*.md` (when the directory exists), parse YAML frontmatter from each file, and emit a markdown table to stdout with the columns (in order): `filename`, `skill type`, `target / task`, `outcome summary`, `timestamp`, `error`. Heterogeneous frontmatter SHALL be reconciled per the design D2 mapping: `skill type` derived from filename prefix; `target / task` from frontmatter `target` (review / adversarial-review / visual-xval) or `task_description` truncated to 50 characters (rescue); `outcome summary` from `findings_count` (review) or `outcome` enum value (rescue) or the literal `4/4 sections` (adversarial-review) or the frontmatter `agreement_rate` rendered as a percentage followed by ` agreement` (visual-xval); `timestamp` from the filename ISO8601 portion truncated to date + HH:MM; `error` from frontmatter `error` field if present, else empty. Missing fields SHALL render as `—` (em dash) rather than crash or omit the row.

#### Scenario: Populated .codex-pro/ produces a markdown table

- **WHEN** a user invokes `/codex-pro:codex-status` with a non-empty `.codex-pro/` containing one review, one rescue, and one adversarial-review result file
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

#### Scenario: Visual cross-validation row shows its agreement rate

- **WHEN** `.codex-pro/` contains `visual-xval-20261007T120000Z.md` whose frontmatter has `agreement_rate: 0.917`
- **THEN** that row's `skill type` column MUST be `visual-xval`
- **AND** its `outcome summary` column MUST be `91.7% agreement`
