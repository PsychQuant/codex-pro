# review Specification

## Purpose

The review capability provides read-only Codex code review via `/codex-pro:codex-review`, accepting three mutually-exclusive review targets: current uncommitted diff (no argument), a specific file path, or a branch comparison (`--base <ref>`). Review invokes the `codex-call` HTTPS-direct wrapper with a hard timeout — explicitly NOT spawning the `codex` CLI subprocess — and therefore stands as the canonical adherence example for codex-pro Design constraint #1, in deliberate contrast to the `batch` capability which is the only documented exception. Output is written to a structured Markdown file at `.codex-pro/review-<ISO8601-timestamp>.md` with a YAML frontmatter (six fields including `findings_count` with no upper bound and an optional `error` class) and a body containing `## Summary` plus `## Findings` sections, each finding marked with severity and source location. Failures in three classes — rate limit, OAuth invalid, hard timeout — trigger circuit-breaker fail-fast: the result file is still written but with an `error` field naming the class, `findings_count: 0`, and the skill does NOT retry, directly countering the runaway-retry token-burn pattern that affects upstream `openai/codex-plugin-cc`. This v0.1 is single-oracle; ensemble multi-reviewer pattern is reserved for v0.2.

## Requirements

### Requirement: Review skill registration and target resolution

The plugin SHALL expose a `/codex-pro:codex-review` skill registered at `plugins/codex-pro/skills/codex-review/SKILL.md` with a YAML frontmatter declaring `name: codex-review`, a descriptive `description` block (containing the literal substring `v0.2 — untracked-by-default` to make the v0.1 → v0.2 behavior change discoverable), and an `allowed-tools` list containing at least `Bash` (for `codex-call` invocation, `git diff HEAD`, `git ls-files --others --exclude-standard`, and `git check-attr binary`) and `Read` (for file content collection). The skill SHALL accept three mutually-exclusive review targets and resolve them in the following precedence: an explicit `--base <ref>` flag triggers branch comparison via `git diff <ref>...HEAD` (unchanged from v0.1); a positional file-path argument triggers single-file review via reading that file (unchanged from v0.1); no argument or `--diff` flag triggers review of all uncommitted changes via `git diff HEAD` PLUS untracked-file enumeration via `git ls-files --others --exclude-standard`. The `--diff` mode SHALL detect and isolate binary untracked files (via `git check-attr binary` plus NUL-byte sniff in first 8KB) and path-list them in a `### Untracked binaries omitted` section without content injection. The `--diff` mode SHALL apply a per-file 64KB content cap (truncating with the marker `… [truncated at 64KB of N bytes]`) and an aggregate 512KB cap (listing overflow files in `### Untracked files omitted (aggregate size cap)`). The `--diff` mode SHALL detect pre-first-commit repositories (`git diff HEAD` exit code 128 with stderr matching `unknown revision|ambiguous argument 'HEAD'`) and fall back to `git diff --cached` plus working-tree `git diff` plus untracked enumeration, recording `target: diff (pre-first-commit)` in result-file frontmatter. The skill MUST NOT add a `--legacy-tracked-only` opt-out flag (which would ossify the v0.1 silent-omission bug).

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-review/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-review`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`
- **AND** the frontmatter `description` MUST contain the literal substring `v0.2 — untracked-by-default`

#### Scenario: --diff mode includes both tracked changes and untracked files

- **WHEN** a user invokes `/codex-pro:codex-review` (or `/codex-pro:codex-review --diff`) in a repository containing tracked-modified files plus untracked files
- **THEN** the skill SHALL run `git diff HEAD` to obtain the tracked-changes portion of the target
- **AND** the skill SHALL run `git ls-files --others --exclude-standard` to enumerate untracked files (respecting `.gitignore`)
- **AND** the result-file target body SHALL include both portions

##### Example: mixed-state body composition

| Input state | Expected body section(s) |
| --- | --- |
| 1 modified tracked + 1 untracked normal text file | `git diff HEAD` output AND `### Untracked file: <path>` section with content |
| Only modified tracked | `git diff HEAD` output, no Untracked sections |
| Only untracked text | `### Untracked file: <path>` section, no `git diff HEAD` block |

#### Scenario: Binary untracked file is path-listed without content injection

- **WHEN** the `--diff` mode encounters an untracked file detected as binary (either `git check-attr binary` returns "binary", or the first 8KB contains a NUL byte)
- **THEN** the skill SHALL list its path under a `### Untracked binaries omitted` heading
- **AND** the skill MUST NOT inject the file's content into the target body

#### Scenario: Oversize untracked file is truncated with marker

- **WHEN** the `--diff` mode encounters an untracked content-eligible file larger than 64KB
- **THEN** the skill SHALL include the first 64KB of content followed by the literal marker `… [truncated at 64KB of N bytes]` (where N is the original size)

#### Scenario: Aggregate size cap omits overflow files

- **WHEN** the cumulative content of untracked content-eligible files would exceed 512KB
- **THEN** the skill SHALL stop content inclusion at the cap and list remaining file paths under `### Untracked files omitted (aggregate size cap)` without content injection

#### Scenario: Pre-first-commit repository falls back to --cached + working-tree diff

- **WHEN** the `--diff` mode runs in a repository where `git diff HEAD` exits 128 with stderr matching `unknown revision|ambiguous argument 'HEAD'`
- **THEN** the skill SHALL fall back to `git diff --cached` plus working-tree `git diff` plus untracked enumeration
- **AND** the result-file frontmatter `target` field SHALL be set to `diff (pre-first-commit)` instead of `diff`

#### Scenario: File path argument targets a single file

- **WHEN** a user invokes `/codex-pro:codex-review <file-path>` where `<file-path>` resolves to a readable file inside the project
- **THEN** the skill SHALL collect the entire file content as the review target

#### Scenario: --base flag targets a branch diff

- **WHEN** a user invokes `/codex-pro:codex-review --base <ref>` where `<ref>` is a valid git reference
- **THEN** the skill SHALL run `git diff <ref>...HEAD` to obtain the review target
- **AND** when both a file-path argument and `--base` are provided, the skill SHALL use `--base` (branch comparison takes precedence)


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
### Requirement: Review invocation uses codex-call HTTPS direct without subprocess for Codex

The skill SHALL invoke the `codex-call` Swift wrapper (provided by the `parallel-ai-agents` runtime dependency) to execute the Codex review request. The skill MUST NOT spawn the `codex` CLI as a subprocess. This requirement is the canonical adherence pattern for codex-pro Design constraint #1 ("No subprocess spawn for Codex") and contrasts with the `batch` skill which is the documented explicit exception. The skill MUST pass `--model`, `--effort`, and `--max-time` flags to `codex-call` whose values come from the resolved profile (per the `config` capability). When no profile is set or the field is absent, hardcoded defaults SHALL apply: `--model gpt-5.6-sol` / `--effort xhigh` / `--max-time 600` (the 2026-07 default bump per issue #3: `gpt-5.6-sol` is the only 5.6-generation model the codex-call ChatGPT-account backend-api path accepts — verified empirically 2026-07-10; users with a profile override are unaffected, 100% backward compatible). The frontmatter description block in SKILL.md SHALL contain the literal substring `v0.3 — profile-aware` to make the v0.2 → v0.3 version bump discoverable.

#### Scenario: SKILL.md contains codex-call invocation

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-review/SKILL.md`
- **THEN** the body SHALL contain at least one occurrence of the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec` (the subprocess form is the batch exception, not allowed here)

#### Scenario: codex-call invocation includes hard timeout flag (default 600)

- **WHEN** the skill body documents the codex-call invocation
- **THEN** the documented invocation MUST include the `--max-time` flag with the literal substring `600` (the default fallback when the resolved profile has no `max_time` override)

#### Scenario: SKILL.md frontmatter announces v0.3 — profile-aware

- **WHEN** the static layer inspects `plugins/codex-pro/skills/codex-review/SKILL.md`
- **THEN** the frontmatter `description` MUST contain the literal substring `v0.3 — profile-aware`

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
### Requirement: Review output is a structured Markdown result file

The skill SHALL write the Codex review output to a Markdown file at `.codex-pro/review-<ISO8601-timestamp>.md` inside the project root. The directory `.codex-pro/` MUST be created on first run if absent. The result file MUST contain a YAML frontmatter block with the required fields `target`, `model`, `effort`, `timestamp`, `findings_count` (with no upper bound), and an optional `error` field when a fail-fast condition fires. An optional v0.3 `profile_source` field MAY appear with one of four enum values: `default` (all 3 producer-relevant fields hardcoded), `global` (at least one field from global, none from project), `project` (at least one field from project, no global-only fields), or `mixed` (at least one global field AND at least one project field). v0.2 result files without `profile_source` remain valid (`/codex-pro:codex-status` and `/codex-pro:codex-result` MUST tolerate missing `profile_source`). The body MUST contain a `## Summary` section (one-paragraph overall assessment) followed by a `## Findings` section. Each finding heading MUST use the format `### Finding N: <severity> — <file>:<line>` and each finding body MUST contain a concise message followed by a single line beginning with `**Suggestion:**` providing concrete remediation. The skill MUST NOT return findings inline to Claude as the primary delivery path; the result file is the contract.

#### Scenario: Success case writes structured result file

- **WHEN** a review completes successfully
- **THEN** `.codex-pro/review-<timestamp>.md` MUST exist with YAML frontmatter containing `target`, `model`, `effort`, `timestamp`, `findings_count`
- **AND** the body MUST contain `## Summary` and `## Findings` sections
- **AND** each `### Finding N:` body MUST contain a `**Suggestion:**` line

#### Scenario: profile_source frontmatter field reflects resolution source

- **WHEN** a review runs with no profile set
- **THEN** the result file frontmatter MAY include `profile_source: default` (v0.3 producer SHOULD emit it; v0.2 compat layer for missing-field reads is intact)
- **WHEN** a review runs with a project profile that only sets `max_time`
- **THEN** the result file frontmatter `profile_source` MAY be `project`
- **WHEN** a review runs with a global profile setting `model` and a project profile setting `max_time`
- **THEN** the result file frontmatter `profile_source` MAY be `mixed`

#### Scenario: First run creates output directory

- **WHEN** the skill runs and `.codex-pro/` does not exist
- **THEN** the skill SHALL create the directory before writing the result file
- **AND** a failure to create the directory (permissions, read-only filesystem) MUST abort the skill with a clear error and MUST NOT silently fall back to writing elsewhere


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
### Requirement: Review failures trigger circuit-breaker fail-fast

When the underlying `codex-call` invocation fails for one of three runtime classes of error — rate-limit response, OAuth-invalid response, or hard-timeout exhaustion — OR when a fourth pre-flight class fires — target-invalid (post-filter empty target body) — the skill SHALL fail fast: it MUST NOT retry the request, MUST still write the result file with a YAML frontmatter `error` field naming the failure class (`rate_limit` / `oauth_invalid` / `timeout` / `target_invalid`), MUST set `findings_count: 0`, and MUST report a remediation message to the user identifying the failure class. The `target_invalid` class is the pre-flight class introduced in v0.2 to align with the adversarial-review template — it fires when `git diff HEAD` (or fallback path) returns empty AND untracked enumeration (after binary and size filtering) is empty AND the merged target body is whitespace-only. This pre-flight class prevents the skill from invoking `codex-call` with an empty prompt that would burn Codex quota for no work. The runtime three classes (`rate_limit` / `oauth_invalid` / `timeout`) and the no-retry circuit-breaker discipline are unchanged from v0.1. This requirement continues to encode the circuit-breaker discipline that prevents the runaway-retry token-burn pattern affecting upstream `openai/codex-plugin-cc` (issue #306).

#### Scenario: Rate-limit response writes error frontmatter and stops

- **WHEN** `codex-call` exits non-zero with output containing "rate limit" or HTTP status 429
- **THEN** the result file MUST be written with YAML frontmatter `error: rate_limit` and `findings_count: 0`
- **AND** the body MAY be empty or contain only a single line describing the failure
- **AND** the skill MUST NOT retry the `codex-call` invocation

#### Scenario: OAuth-invalid response writes error frontmatter and stops

- **WHEN** `codex-call` exits non-zero with output containing "auth" or HTTP status 401
- **THEN** the result file MUST be written with YAML frontmatter `error: oauth_invalid` and `findings_count: 0`
- **AND** the skill MUST emit a remediation message directing the user to run `/codex-pro:codex-setup`

#### Scenario: Timeout exhaustion writes error frontmatter and stops

- **WHEN** `codex-call` exceeds the `--max-time 600` hard timeout
- **THEN** the result file MUST be written with YAML frontmatter `error: timeout` and `findings_count: 0`
- **AND** the skill MUST emit a remediation message suggesting a narrower review target (e.g., a smaller file, a tighter `--base` range)

#### Scenario: Target-invalid pre-flight fires when post-filter body is empty

- **WHEN** the `--diff` mode resolves a target body that, after binary detection and size cap filtering, is whitespace-only (zero meaningful content for Codex)
- **THEN** the skill SHALL abort BEFORE invoking `codex-call` (pre-flight)
- **AND** the result file MUST be written with YAML frontmatter `error: target_invalid` and `findings_count: 0`
- **AND** the skill MUST emit a remediation message explaining that the target body was empty after binary and size filtering, suggesting the user verify there are real changes to review (e.g., uncommitted tracked changes, or untracked text files within 64KB each)

<!-- @trace
source: diff-untracked-fix-all-producers
updated: 2026-06-01
code:
  - README.md
  - plugins/codex-pro/skills/codex-adversarial-review/SKILL.md
  - tests/adversarial-review.sh
  - tests/review.sh
  - tests/lib/assert.sh
  - plugins/codex-pro/skills/codex-review/SKILL.md
  - CLAUDE.md
  - plugins/codex-pro/.claude-plugin/plugin.json
-->
