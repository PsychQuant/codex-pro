## ADDED Requirements

### Requirement: Review system instructions name literal heading tokens

The Step 3 system instructions that the skill passes to `codex-call` via the `--instructions` flag SHALL name the required output structure with literal Markdown tokens rather than prose nouns. Specifically, the documented instructions block in `plugins/codex-pro/skills/review/SKILL.md` Step 3 MUST contain: (a) the literal line `## Summary` and the literal line `## Findings` presented as the exact required H2 headings, (b) a normative ordering clause stating the output consists of exactly two H2 sections in that order, (c) a CRITICAL clause stating the output MUST begin with the literal line `## Summary`, and (d) the literal H3 finding heading format `### Finding N: <severity> — <file>:<line>` (the heading level `###` is explicit, matching the Step 5 `findings_count` parser and the result-file contract). The instructions MUST NOT describe the Summary or Findings sections only as prose nouns (e.g., "a one-paragraph Summary", "a Findings list") without also naming the literal heading tokens. The instructions MUST NOT include a one-shot or few-shot example output block (rejected for per-call prompt-token cost; the literal-token naming pattern is the proven sufficient mechanism, per the adversarial-review four-section precedent).

#### Scenario: Step 3 instructions contain literal H2 heading tokens

- **WHEN** the static or behavioral layer inspects the Step 3 instructions block of `plugins/codex-pro/skills/review/SKILL.md`
- **THEN** the block MUST contain the literal string `## Summary`
- **AND** the block MUST contain the literal string `## Findings`
- **AND** the block MUST contain an ordering clause with the literal substring `exactly two H2 sections`

#### Scenario: Step 3 instructions specify literal H3 finding heading level

- **WHEN** the static or behavioral layer inspects the Step 3 instructions block
- **THEN** the block MUST contain the literal string `### Finding N:` (the explicit H3 level, not a level-unspecified "heading format" phrase)

#### Scenario: Heading reliability observed across full e2e matrix before assertion promotion

- **WHEN** a full Layer 3 e2e matrix run executes the review scenarios (mixed / binary / oversize / empty-repo / with-profile) against the hardened instructions
- **THEN** each review result-file body MUST contain the `## Summary` and `## Findings` H2 headings
- **AND** zero heading-related warn lines is the precondition for promoting the e2e heading checks to hard assertions (per the e2e-tests capability)

## MODIFIED Requirements

### Requirement: Review invocation uses codex-call HTTPS direct without subprocess for Codex

The skill SHALL invoke the `codex-call` Swift wrapper (provided by the `parallel-ai-agents` runtime dependency) to execute the Codex review request. The skill MUST NOT spawn the `codex` CLI as a subprocess. This requirement is the canonical adherence pattern for codex-pro Design constraint #1 ("No subprocess spawn for Codex") and contrasts with the `batch` skill which is the documented explicit exception. The skill MUST pass `--model`, `--effort`, and `--max-time` flags to `codex-call` whose values come from the resolved profile (per the `config` capability). When no profile is set or the field is absent, hardcoded defaults SHALL apply: `--model gpt-5.6-sol` / `--effort xhigh` / `--max-time 600` (the v0.2 hardcoded values become v0.3 default fallbacks — 100% backward compatible for users without a profile). The frontmatter description block in SKILL.md SHALL contain the literal substring `v0.3 — profile-aware` to make the v0.2 → v0.3 version bump discoverable, and the literal substring `v0.4 — heading-hardened` to make the v0.3 → v0.4 version bump (literal-token Step 3 instructions) discoverable.

#### Scenario: SKILL.md contains codex-call invocation

- **WHEN** the static layer inspects `plugins/codex-pro/skills/review/SKILL.md`
- **THEN** the body SHALL contain at least one occurrence of the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec` (the subprocess form is the batch exception, not allowed here)

#### Scenario: codex-call invocation includes hard timeout flag (default 600)

- **WHEN** the skill body documents the codex-call invocation
- **THEN** the documented invocation MUST include the `--max-time` flag with the literal substring `600` (the v0.3 default fallback when the resolved profile has no `max_time` override)

#### Scenario: SKILL.md frontmatter announces v0.3 — profile-aware

- **WHEN** the static layer inspects `plugins/codex-pro/skills/review/SKILL.md`
- **THEN** the frontmatter `description` MUST contain the literal substring `v0.3 — profile-aware`

#### Scenario: SKILL.md frontmatter announces v0.4 — heading-hardened

- **WHEN** the static layer inspects `plugins/codex-pro/skills/review/SKILL.md`
- **THEN** the frontmatter `description` MUST contain the literal substring `v0.4 — heading-hardened`

#### Scenario: Producer reads profile via inline python3 before codex-call

- **WHEN** the SKILL.md Step 4 body documents the codex-call invocation
- **THEN** the body MUST contain an inline `python3` block that reads `~/.codex-pro/profile.yaml` and `.codex-pro/profile.yaml`
- **AND** the documented invocation MUST pass `--model "$MODEL"` / `--effort "$EFFORT"` / `--max-time "$MAX_TIME"` (or equivalent shell-variable expansion from the python3 output)
- **AND** the body MUST mention the hardcoded defaults `gpt-5.6-sol` / `xhigh` / `600` as fallbacks
