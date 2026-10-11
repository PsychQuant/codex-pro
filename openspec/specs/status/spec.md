# status Specification

## Purpose

TBD - created by archiving change 'status-result-cancel'. Update Purpose after archive.

## Requirements

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


<!-- @trace
source: add-visual-xval
updated: 2026-10-12
code:
  - .codex/skills/codex-visual-xval/references/claim-schema.md
  - .codex/skills/codex-visual-xval/scripts/zoom_round.py
  - skills/codex-visual-xval/scripts/adjudicate.py
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
  - .codex/skills/codex-visual-xval/scripts/adjudicate.py
  - .codex/skills/codex-status/SKILL.md
  - tests/codex-skills-parity.sh
  - THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-ask/SKILL.md
  - bin/codex-pro-call
  - plugins/codex-pro/skills/codex-visual-xval/scripts/adjudicate.py
  - skills/codex-visual-xval/references/claim-schema.md
  - skills/codex-visual-xval/scripts/xval.py
  - skills/codex-visual-xval/scripts/sam_env.sh
  - .agents/skills/spectra-commit/SKILL.md
  - .codex/.codex-bundle-files
  - plugins/codex-pro/runtime/codex-call
  - .codex/skills/codex-visual-xval/scripts/codex_errors.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_track.py
  - skills/codex-setup/SKILL.md
  - scripts/codex-skills.manifest
  - plugins/codex-pro/skills/codex-visual-xval/scripts/zoom_round.py
  - .codex/bin/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/media.py
  - skills/codex-visual-xval/scripts/seal.py
  - skills/codex-visual-xval/references/vocab-format.md
  - bin/codex-call
  - .codex/skills/codex-visual-xval/scripts/sam_track.py
  - plugins/codex-pro/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/xval.py
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/seal.py
  - .codex/skills/codex-visual-xval/scripts/result_file.py
  - CHANGELOG.md
  - skills/codex-status/SKILL.md
  - tests/result.sh
  - tests/e2e-checklist.md
  - .codex-bundle-files
  - plugins/codex-pro/skills/codex-visual-xval/references/vocab-format.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-review/SKILL.md
  - tests/lib/assert.sh
  - AGENTS.md
  - skills/codex-visual-xval/scripts/codex_errors.py
  - skills/codex-visual-xval/scripts/sam_track.py
  - tests/run.sh
  - .codex/skills/codex-visual-xval/scripts/xval.py
  - .codex/skills/codex-visual-xval/scripts/sam_env.sh
  - skills/codex-visual-xval/SKILL.md
  - tests/codex-plugin.sh
  - .codex/skills/codex-visual-xval/scripts/seal.py
  - plugins/codex-pro/references/codex-call-provenance.json
  - .codex/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-drift/SKILL.md
  - .codex/bin/codex-call
  - skills/codex-visual-xval/scripts/media.py
  - .codex/skills/codex-visual-xval/scripts/run_files.py
  - scripts/codex-bundle-resources.manifest
  - skills/codex-visual-xval/scripts/zoom_round.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/media.py
  - .agents/skills/spectra-verify/SKILL.md
  - .codex-plugin/plugin.json
  - plugins/codex-pro/THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-archive/SKILL.md
  - .codex/skills/codex-visual-xval/references/vocab-format.md
  - .codex/skills/codex-result/SKILL.md
  - plugins/codex-pro/runtime/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/compare_claims.py
  - skills/codex-visual-xval/scripts/run_files.py
  - tests/visual-xval.sh
  - .codex/references/codex-call-provenance.json
  - CLAUDE.md
  - skills/codex-visual-xval/scripts/compare_claims.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/run_files.py
  - .agents/skills/spectra-debug/SKILL.md
  - references/codex-call-provenance.json
  - .agents/skills/spectra-audit/SKILL.md
  - scripts/generate-codex-skills.sh
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_env.sh
  - plugins/codex-pro/skills/codex-visual-xval/references/claim-schema.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/compare_claims.py
  - tests/status.sh
  - tests/codex-runtime.sh
  - skills/codex-result/SKILL.md
  - README.md
  - .claude-plugin/marketplace.json
  - .agents/skills/spectra-apply/SKILL.md
  - .codex/skills/codex-setup/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/codex_errors.py
-->

---
### Requirement: Status invocation is read-only with no Codex interaction

The skill SHALL NOT invoke `codex-call` and SHALL NOT spawn the `codex` CLI. The skill SHALL NOT write, modify, or delete any file in `.codex-pro/` or elsewhere. The skill body in `SKILL.md` MUST NOT contain the literal strings `codex-call` or `codex exec`. This places `status` in the codex-pro read-only category alongside `setup` (and the sibling `result` / `cancel` skills landed in the same change), in deliberate contrast to the producer skills (`review` / `rescue` / `adversarial-review`) which write to `.codex-pro/` and invoke `codex-call`, and the `batch` exception which invokes `codex exec`.

#### Scenario: SKILL.md does not invoke codex-call or codex exec

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-status/SKILL.md`
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
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/skills/codex-cancel/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - tests/status.sh
  - tests/cancel.sh
  - tests/run.sh
  - tests/result.sh
-->

---
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


<!-- @trace
source: add-visual-xval
updated: 2026-10-12
code:
  - .codex/skills/codex-visual-xval/references/claim-schema.md
  - .codex/skills/codex-visual-xval/scripts/zoom_round.py
  - skills/codex-visual-xval/scripts/adjudicate.py
  - plugins/codex-pro/skills/codex-result/SKILL.md
  - plugins/codex-pro/.claude-plugin/plugin.json
  - .codex/skills/codex-visual-xval/scripts/adjudicate.py
  - .codex/skills/codex-status/SKILL.md
  - tests/codex-skills-parity.sh
  - THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-ask/SKILL.md
  - bin/codex-pro-call
  - plugins/codex-pro/skills/codex-visual-xval/scripts/adjudicate.py
  - skills/codex-visual-xval/references/claim-schema.md
  - skills/codex-visual-xval/scripts/xval.py
  - skills/codex-visual-xval/scripts/sam_env.sh
  - .agents/skills/spectra-commit/SKILL.md
  - .codex/.codex-bundle-files
  - plugins/codex-pro/runtime/codex-call
  - .codex/skills/codex-visual-xval/scripts/codex_errors.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_track.py
  - skills/codex-setup/SKILL.md
  - scripts/codex-skills.manifest
  - plugins/codex-pro/skills/codex-visual-xval/scripts/zoom_round.py
  - .codex/bin/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/media.py
  - skills/codex-visual-xval/scripts/seal.py
  - skills/codex-visual-xval/references/vocab-format.md
  - bin/codex-call
  - .codex/skills/codex-visual-xval/scripts/sam_track.py
  - plugins/codex-pro/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/xval.py
  - .agents/skills/spectra-analyze/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/seal.py
  - .codex/skills/codex-visual-xval/scripts/result_file.py
  - CHANGELOG.md
  - skills/codex-status/SKILL.md
  - tests/result.sh
  - tests/e2e-checklist.md
  - .codex-bundle-files
  - plugins/codex-pro/skills/codex-visual-xval/references/vocab-format.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-review/SKILL.md
  - tests/lib/assert.sh
  - AGENTS.md
  - skills/codex-visual-xval/scripts/codex_errors.py
  - skills/codex-visual-xval/scripts/sam_track.py
  - tests/run.sh
  - .codex/skills/codex-visual-xval/scripts/xval.py
  - .codex/skills/codex-visual-xval/scripts/sam_env.sh
  - skills/codex-visual-xval/SKILL.md
  - tests/codex-plugin.sh
  - .codex/skills/codex-visual-xval/scripts/seal.py
  - plugins/codex-pro/references/codex-call-provenance.json
  - .codex/skills/codex-visual-xval/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-drift/SKILL.md
  - .codex/bin/codex-call
  - skills/codex-visual-xval/scripts/media.py
  - .codex/skills/codex-visual-xval/scripts/run_files.py
  - scripts/codex-bundle-resources.manifest
  - skills/codex-visual-xval/scripts/zoom_round.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/media.py
  - .agents/skills/spectra-verify/SKILL.md
  - .codex-plugin/plugin.json
  - plugins/codex-pro/THIRD_PARTY_NOTICES.md
  - .agents/skills/spectra-archive/SKILL.md
  - .codex/skills/codex-visual-xval/references/vocab-format.md
  - .codex/skills/codex-result/SKILL.md
  - plugins/codex-pro/runtime/codex-pro-call
  - .codex/skills/codex-visual-xval/scripts/compare_claims.py
  - skills/codex-visual-xval/scripts/run_files.py
  - tests/visual-xval.sh
  - .codex/references/codex-call-provenance.json
  - CLAUDE.md
  - skills/codex-visual-xval/scripts/compare_claims.py
  - plugins/codex-pro/skills/codex-visual-xval/scripts/run_files.py
  - .agents/skills/spectra-debug/SKILL.md
  - references/codex-call-provenance.json
  - .agents/skills/spectra-audit/SKILL.md
  - scripts/generate-codex-skills.sh
  - plugins/codex-pro/skills/codex-visual-xval/scripts/sam_env.sh
  - plugins/codex-pro/skills/codex-visual-xval/references/claim-schema.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/compare_claims.py
  - tests/status.sh
  - tests/codex-runtime.sh
  - skills/codex-result/SKILL.md
  - README.md
  - .claude-plugin/marketplace.json
  - .agents/skills/spectra-apply/SKILL.md
  - .codex/skills/codex-setup/SKILL.md
  - plugins/codex-pro/skills/codex-status/SKILL.md
  - skills/codex-visual-xval/scripts/result_file.py
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/codex-pro/skills/codex-visual-xval/scripts/codex_errors.py
-->

---
### Requirement: Status handles missing or empty .codex-pro/ as informational

The skill SHALL distinguish between three states of `.codex-pro/` and emit informational stdout (not error) for the empty and missing cases, with exit 0. State (a) `.codex-pro/` directory does not exist: the skill SHALL print a one-line note explaining that the directory is created on first producer-skill run, and exit 0. State (b) `.codex-pro/` exists but contains zero `*.md` files: the skill SHALL print `No result files found` and exit 0. State (c) populated: render the markdown table per the prior requirement. The skill MUST NOT create `.codex-pro/` as a side effect of running status.

#### Scenario: Missing .codex-pro/ directory is informational

- **WHEN** a user invokes `/codex-pro:codex-status` in a project whose `.codex-pro/` directory does not exist
- **THEN** stdout MUST contain a one-line note referencing first producer-skill creation
- **AND** the skill MUST NOT create `.codex-pro/`
- **AND** the skill SHALL exit 0

#### Scenario: Empty .codex-pro/ directory is informational

- **WHEN** a user invokes `/codex-pro:codex-status` with an empty `.codex-pro/` directory (zero `*.md` files)
- **THEN** stdout MUST contain the literal string `No result files found`
- **AND** the skill SHALL exit 0

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