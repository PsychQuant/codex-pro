## MODIFIED Requirements

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
