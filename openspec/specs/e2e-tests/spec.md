# e2e-tests Specification

## Purpose

TBD - created by archiving change 'e2e-skill-invocation-tests'. Update Purpose after archive.

## Requirements

### Requirement: e2e test script registration and argument parsing

The `tests/e2e.sh` script SHALL exist as a standalone opt-in test runner that accepts exactly two required flags: `--skill <name>` (where `<name>` is one of `review` or `adversarial-review`) and `--scenario <name>` (where `<name>` is one of `mixed`, `binary`, `oversize`, `empty-repo`, `all-empty`). The script SHALL reject any other flag combination or invalid value with a usage hint that lists the accepted values, exiting with code 2. The script SHALL source two helper modules: `tests/lib/e2e-claude-print.sh` (Claude invocation + retry) and `tests/lib/e2e-fixtures.sh` (5 scenario fixture helpers). The script MUST NOT be added to `tests/run.sh` — Layer 3 is opt-in per-release, not opt-in per-commit.

#### Scenario: tests/e2e.sh exists and is executable

- **WHEN** the plugin repository is checked out
- **THEN** `tests/e2e.sh` MUST exist
- **AND** `bash -n tests/e2e.sh` MUST exit 0 (syntax valid)

#### Scenario: Valid --skill + --scenario combinations are accepted

- **WHEN** a user invokes `bash tests/e2e.sh --skill review --scenario mixed`
- **THEN** the script SHALL proceed to fixture setup
- **AND** the same SHALL hold for all 10 combinations (review|adversarial-review × mixed|binary|oversize|empty-repo|all-empty)

#### Scenario: Invalid --skill value is rejected

- **WHEN** a user invokes `bash tests/e2e.sh --skill bogus --scenario mixed`
- **THEN** the script SHALL emit a usage hint listing `review` and `adversarial-review`
- **AND** the script SHALL exit with code 2

#### Scenario: Invalid --scenario value is rejected

- **WHEN** a user invokes `bash tests/e2e.sh --skill review --scenario bogus`
- **THEN** the script SHALL emit a usage hint listing the 5 accepted scenarios
- **AND** the script SHALL exit with code 2

#### Scenario: Missing required flags are rejected

- **WHEN** a user invokes `bash tests/e2e.sh` with neither `--skill` nor `--scenario`
- **THEN** the script SHALL emit a usage hint
- **AND** the script SHALL exit with code 2


<!-- @trace
source: e2e-skill-invocation-tests
updated: 2026-06-01
code:
  - tests/e2e.sh
  - tests/lib/e2e-fixtures.sh
  - CLAUDE.md
  - tests/e2e-checklist.md
  - README.md
  - tests/lib/e2e-claude-print.sh
  - tests/run.sh
-->

---
### Requirement: e2e invokes real SKILL.md via claude --print --plugin-dir

The script SHALL invoke `timeout 600 claude --print --plugin-dir <codex-pro plugin path> "/codex-pro:<skill>"` from the fixture directory's cwd to trigger real Claude Code session that reads `plugins/codex-pro/skills/<skill>/SKILL.md` and resolves the skill via Claude's skill router. The `<codex-pro plugin path>` SHALL be derived dynamically from the repo root as `<repo>/plugins/codex-pro` rather than hardcoded. The script MUST NOT mock or substitute the SKILL.md invocation with test-script-internal Bash function (which is the Layer 2 behavioral pattern explicitly). The script MUST NOT bypass the Claude session — programmatic SDK invocation, stdin-piped prompt, or `expect`-driven interactive simulation are all out-of-scope.

#### Scenario: claude is invoked with --print and --plugin-dir

- **WHEN** the script reaches the invocation step
- **THEN** the script SHALL execute `timeout 600 claude --print --plugin-dir <derived path> "/codex-pro:<skill>"`
- **AND** the derived path MUST resolve to `<repo>/plugins/codex-pro` relative to the script location

#### Scenario: Fixture cwd is preserved for the Claude session

- **WHEN** the script invokes Claude from `cd "$FIXTURE_DIR" && claude --print ...`
- **THEN** the Claude session SHALL inherit `$FIXTURE_DIR` as its cwd
- **AND** the skill's `git diff HEAD` / `git ls-files` / `.codex-pro/` writes MUST land in `$FIXTURE_DIR`

#### Scenario: Anthropic API rate limit triggers exponential-backoff retry

- **WHEN** `claude --print` output contains the substring `Server is temporarily limiting requests`
- **THEN** the script SHALL sleep `30 * 2^(attempt-1)` seconds (30s, 60s, 120s) and retry up to 3 attempts total
- **AND** the script SHALL exit code 4 if all 3 attempts hit rate limit
- **AND** the script MUST NOT retry on any other error (codex-call rate limit / OAuth invalid / timeout / target_invalid are SKILL-internal fail-fast and are valid e2e results)


<!-- @trace
source: e2e-skill-invocation-tests
updated: 2026-06-01
code:
  - tests/e2e.sh
  - tests/lib/e2e-fixtures.sh
  - CLAUDE.md
  - tests/e2e-checklist.md
  - README.md
  - tests/lib/e2e-claude-print.sh
  - tests/run.sh
-->

---
### Requirement: e2e verifies result file structure and frontmatter markers per scenario

After the Claude session completes (exit 0 or otherwise), the script SHALL verify the result file at `<fixture>/.codex-pro/<skill>-<ISO8601-timestamp>.md`. Verification SHALL include: (a) file exists, (b) YAML frontmatter contains the expected `target` marker per scenario (`diff` for mixed/binary/oversize, `diff (pre-first-commit)` for empty-repo, `target_invalid` error frontmatter for all-empty), (c) body contains expected H2 section headings driven by SKILL.md system instructions (review: `## Summary` + `## Findings`, per the review capability's literal-token Step 3 instructions; adversarial-review: 4 mandatory H2 sections each with > 200 substantive characters), (d) for all-empty scenario only: `error: target_invalid` frontmatter + `findings_count: 0` for review (this scenario is fully deterministic because Claude's pre-flight writes the result file without invoking codex-call).

**Heading assertion strength**: the H2 heading checks in clause (c) SHALL be hard assertions — a missing heading increments the fail counter and the run exits non-zero — implemented via the same fail-on-miss helper used for frontmatter markers. The warn-level (best-effort, non-failing) treatment of heading checks is the pre-promotion state only: it applied while the review capability's Step 3 instructions described the structure via prose nouns, and SHALL NOT persist once a full e2e matrix observation run against the literal-token instructions has shown zero heading-related warn lines. If a future full-matrix run shows heading drift recurring (a hard heading assertion failing for a non-regression reason), maintainers SHALL treat that as new evidence requiring instruction-level rework in the producing skill, not as grounds to silently demote the assertion back to warn.

**Verification scope boundary** (v0.1 limitation): the script MUST NOT verify codex-call PROMPT body content (e.g., whether the untracked file content was injected, whether the binary path-list section was constructed, whether the truncation marker was emitted) — these are prompt-construction details that Claude builds via the Bash tool and pipes to codex-call's `--prompt-file`, which the e2e harness does not intercept. The script MUST NOT verify Codex's OUTPUT body content beyond H2 section headings (e.g., whether Codex mentioned a specific file path / referenced the binary omission heading / quoted the truncation marker) because Codex output is non-deterministic LLM prose. Prompt-construction verification is the responsibility of Layer 2 behavioral tests (which can run the collection logic via mock) and pre-archive smoke (which can inspect the constructed prompt file directly).

#### Scenario: Result file path verified at fixture-local path

- **WHEN** the script completes Claude invocation
- **THEN** the script SHALL check for `<fixture>/.codex-pro/<skill>-*.md` (glob with skill name prefix)
- **AND** if the file does not exist, the script SHALL exit code 5

#### Scenario: Mixed scenario verifies required H2 headings

- **WHEN** the script runs `--skill review --scenario mixed`
- **THEN** the body MUST contain `## Summary` and `## Findings` H2 headings
- **WHEN** the script runs `--skill adversarial-review --scenario mixed`
- **THEN** the body MUST contain all 4 H2 headings (`## Assumptions Challenged` / `## Failure Modes` / `## Alternative Approaches` / `## Trade-off Counterarguments`)

#### Scenario: Missing required heading fails the run

- **WHEN** any heading check in a non-all-empty scenario does not find its required H2 heading in the result-file body
- **THEN** the script SHALL record a failed assertion (fail counter incremented)
- **AND** the run SHALL exit non-zero
- **AND** the failure message SHALL name the missing heading and the skill/scenario combination

#### Scenario: Binary scenario verifies required H2 headings only

- **WHEN** the script runs `--skill <name> --scenario binary` for either skill
- **THEN** the body MUST contain the skill's required H2 headings (same set as mixed scenario)
- **AND** verification of binary path-only behavior is delegated to Layer 2 behavioral tests + pre-archive smoke (prompt construction is not e2e-observable)

#### Scenario: Oversize scenario verifies required H2 headings only

- **WHEN** the script runs `--scenario oversize` for either skill
- **THEN** the body MUST contain the skill's required H2 headings
- **AND** verification of truncation marker construction is delegated to Layer 2 behavioral tests + pre-archive smoke

#### Scenario: Empty-repo scenario verifies pre-first-commit marker

- **WHEN** the script runs `--scenario empty-repo`
- **THEN** the result file frontmatter `target` field MUST contain `diff (pre-first-commit)`
- **AND** the body MUST contain the skill's required H2 headings

#### Scenario: All-empty scenario verifies target_invalid pre-flight

- **WHEN** the script runs `--scenario all-empty`
- **THEN** the result file frontmatter MUST contain `error: target_invalid`
- **AND** for `--skill review`, frontmatter MUST contain `findings_count: 0`
- **AND** the body MAY be empty or contain only a single line describing the failure

#### Scenario: Adversarial-review section non-empty enforcement

- **WHEN** the script runs `--skill adversarial-review --scenario <non-empty-scenario>`
- **THEN** each of the 4 mandatory H2 sections (`## Assumptions Challenged`, `## Failure Modes`, `## Alternative Approaches`, `## Trade-off Counterarguments`) MUST be present
- **AND** each section body MUST contain at least 200 substantive characters (whitespace-stripped)

---
### Requirement: e2e is opt-in and excluded from default tests/run.sh

The `tests/run.sh` aggregate test runner MUST NOT dispatch `tests/e2e.sh` automatically. The `tests/run.sh` header comment SHALL note Layer 3 e2e is opt-in via `bash tests/e2e.sh --skill <name> --scenario <name>`. The `tests/e2e-checklist.md` Layer 3 manual checklist SHALL include the explicit script invocation, quota budget estimate (~10 codex-call + ~500k Claude API tokens for the full 10-combination matrix), expected time budget (10-30 minutes), and rate-limit recovery procedure. The `CLAUDE.md` Tests section SHALL include Layer 3 row noting opt-in nature; the `README.md` Tests section SHALL also note Layer 3 as a release gate (not commit gate).

#### Scenario: tests/run.sh does not invoke e2e.sh

- **WHEN** the static layer inspects `tests/run.sh`
- **THEN** the file MUST NOT contain `run_layer e2e` or any `bash tests/e2e.sh` invocation
- **AND** the file header comment MUST mention `Layer 3` and `opt-in`

#### Scenario: tests/e2e-checklist.md documents quota + time budget

- **WHEN** a user reads `tests/e2e-checklist.md`
- **THEN** the file MUST contain the substring `~10 codex-call` (quota budget)
- **AND** MUST contain the substring `Server is temporarily limiting requests` or `rate limit` (recovery procedure reference)
- **AND** MUST list the 10 combinations (5 scenario × 2 skill) as explicit commands

#### Scenario: CLAUDE.md Tests section includes Layer 3 row

- **WHEN** the static layer inspects `CLAUDE.md`
- **THEN** the Tests section table MUST contain a row referencing `Layer 3` and `tests/e2e.sh`
- **AND** the row MUST note `opt-in` and the quota / cost cadence

<!-- @trace
source: e2e-skill-invocation-tests
updated: 2026-06-01
code:
  - tests/e2e.sh
  - tests/lib/e2e-fixtures.sh
  - CLAUDE.md
  - tests/e2e-checklist.md
  - README.md
  - tests/lib/e2e-claude-print.sh
  - tests/run.sh
-->
