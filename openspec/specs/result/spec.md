# result Specification

## Purpose

TBD - created by archiving change 'status-result-cancel'. Update Purpose after archive.

## Requirements

### Requirement: Result skill registration and selection-mode argument parsing

The plugin SHALL expose a `/codex-pro:codex-result` skill registered at `plugins/codex-pro/skills/codex-result/SKILL.md` with a YAML frontmatter declaring `name: codex-result`, a descriptive `description` block whose trigger keywords are codex-qualified — `show codex result file` / `display codex review output` / `顯示 codex 結果` — and MUST NOT list the bare standalone term `顯示結果` as a trigger keyword. The `allowed-tools` list MUST contain at least `Bash` and `Read`. The skill SHALL accept three mutually-exclusive selection modes: (a) a positional `<filename>` argument naming a file in `.codex-pro/` (filename only, no path prefix); (b) `--latest <skill>` where `<skill>` is one of the producer result-file prefixes `review`, `rescue`, `adversarial-review`, `visual-xval` (bare producer identifiers — result-file naming is intentionally decoupled from the `codex-`-prefixed invocation name and is unchanged by this rename); (c) `--latest` with no argument (selects the most recent result file across all producer skills). Supplying both a positional filename and `--latest` SHALL be rejected as a usage error.

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

#### Scenario: --latest selects the most recent visual cross-validation result

- **WHEN** a user invokes `/codex-pro:codex-result --latest visual-xval` with multiple `visual-xval-*.md` files in `.codex-pro/`
- **THEN** the skill SHALL select the visual-xval file with the highest filename lexical order
- **AND** the skill SHALL display its content to stdout


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