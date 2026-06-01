## ADDED Requirements

### Requirement: Review skill registration and target resolution

The plugin SHALL expose a `/codex-pro:review` skill registered at `plugins/codex-pro/skills/review/SKILL.md` with a YAML frontmatter declaring `name: review`, a descriptive `description` block, and an `allowed-tools` list containing at least `Bash` (for `codex-call` invocation and `git diff`) and `Read` (for file content collection). The skill SHALL accept three mutually-exclusive review targets and resolve them in the following precedence: an explicit `--base <ref>` flag triggers branch comparison via `git diff <ref>...HEAD`; a positional file-path argument triggers single-file review via reading that file; no argument or `--diff` flag triggers review of the current uncommitted working tree via `git diff`.

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/review/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `review`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`

#### Scenario: Empty argument defaults to uncommitted diff

- **WHEN** a user invokes `/codex-pro:review` with no arguments
- **THEN** the skill SHALL run `git diff` against the working tree to obtain the review target
- **AND** if `git diff` returns empty output (no uncommitted changes), the skill SHALL abort with a remediation message listing the three valid target forms (no-arg diff / file path / `--base <ref>`)

#### Scenario: File path argument targets a single file

- **WHEN** a user invokes `/codex-pro:review <file-path>` where `<file-path>` resolves to a readable file inside the project
- **THEN** the skill SHALL collect the entire file content as the review target

#### Scenario: --base flag targets a branch diff

- **WHEN** a user invokes `/codex-pro:review --base <ref>` where `<ref>` is a valid git reference
- **THEN** the skill SHALL run `git diff <ref>...HEAD` to obtain the review target
- **AND** when both a file-path argument and `--base` are provided, the skill SHALL use `--base` (branch comparison takes precedence)

### Requirement: Review invocation uses codex-call HTTPS direct without subprocess for Codex

The skill SHALL invoke the `codex-call` Swift wrapper (provided by the `parallel-ai-agents` runtime dependency) to execute the Codex review request. The skill MUST NOT spawn the `codex` CLI as a subprocess. This requirement is the canonical adherence pattern for codex-pro Design constraint #1 ("No subprocess spawn for Codex") and contrasts with the `batch` skill which is the documented explicit exception. The skill MUST pass a hard timeout flag to `codex-call` (`--max-time 600`) so that runaway inference is bounded.

#### Scenario: SKILL.md contains codex-call invocation

- **WHEN** the static layer inspects `plugins/codex-pro/skills/review/SKILL.md`
- **THEN** the body SHALL contain at least one occurrence of the literal string `codex-call`
- **AND** the body MUST NOT contain the literal string `codex exec` (the subprocess form is the batch exception, not allowed here)

#### Scenario: codex-call invocation includes hard timeout

- **WHEN** the skill body documents the codex-call invocation
- **THEN** the documented invocation MUST include the `--max-time 600` flag (10-minute hard timeout)

### Requirement: Review output is a structured Markdown result file

The skill SHALL write the Codex review output to a Markdown file at `.codex-pro/review-<ISO8601-timestamp>.md` inside the project root. The directory `.codex-pro/` MUST be created on first run if absent. The result file MUST contain a YAML frontmatter block with the required fields `target`, `model`, `effort`, `timestamp`, and `findings_count`. On success, the body MUST contain a `## Summary` section and a `## Findings` section with one `### Finding N: <severity> — <file>:<line>` heading per finding, each followed by the finding message and a `**Suggestion:**` line. The skill MUST NOT return findings inline to Claude as the primary delivery path; the result file is the contract — this discipline prevents the silent-stub failure mode that affects upstream `openai/codex-plugin-cc` (issue #324).

#### Scenario: Success case writes structured result file

- **WHEN** a review completes successfully
- **THEN** `.codex-pro/review-<timestamp>.md` MUST exist with YAML frontmatter containing the five required fields
- **AND** the body MUST contain `## Summary` and `## Findings` sections
- **AND** if any findings are reported, each finding MUST be a `### Finding N: <severity> — <file>:<line>` block

##### Example: minimal success frontmatter

| Field           | Example value                                  |
| --------------- | ---------------------------------------------- |
| target          | `diff`                                         |
| model           | `gpt-5.5`                                      |
| effort          | `xhigh`                                        |
| timestamp       | `2026-05-26T10:11:20+08:00`                    |
| findings_count  | `3`                                            |

#### Scenario: Findings count is uncapped

- **WHEN** Codex returns N findings in the review output
- **THEN** the result file MUST contain all N findings as separate `### Finding` blocks
- **AND** the `findings_count` frontmatter field MUST equal N
- **AND** there MUST NOT be a hardcoded upper bound (the upstream `openai/codex-plugin-cc` cap at 3 from issue #298 is explicitly removed)

#### Scenario: First run creates output directory

- **WHEN** the skill runs and `.codex-pro/` does not exist
- **THEN** the skill SHALL create the directory before writing the result file
- **AND** the directory creation failure (permissions, read-only filesystem) MUST abort the skill with a clear error and MUST NOT silently fall back to writing elsewhere

### Requirement: Review failures trigger circuit-breaker fail-fast

When the underlying `codex-call` invocation fails for one of three classes of error — rate-limit response, OAuth-invalid response, or hard-timeout exhaustion — the skill SHALL fail fast: it MUST NOT retry the request, MUST still write the result file with a YAML frontmatter `error` field naming the failure class (`rate_limit` / `oauth_invalid` / `timeout`), MUST set `findings_count: 0`, and MUST report a remediation message to the user identifying the failure class. This requirement encodes the circuit-breaker discipline that prevents the runaway-retry token-burn pattern affecting upstream `openai/codex-plugin-cc` (issue #306).

#### Scenario: Rate-limit response writes error frontmatter and stops

- **WHEN** `codex-call` exits non-zero with output containing "rate limit" or HTTP status 429
- **THEN** the result file MUST be written with YAML frontmatter `error: rate_limit` and `findings_count: 0`
- **AND** the body MAY be empty or contain only a single line describing the failure
- **AND** the skill MUST NOT retry the `codex-call` invocation

#### Scenario: OAuth-invalid response writes error frontmatter and stops

- **WHEN** `codex-call` exits non-zero with output containing "auth" or HTTP status 401
- **THEN** the result file MUST be written with YAML frontmatter `error: oauth_invalid` and `findings_count: 0`
- **AND** the skill MUST emit a remediation message directing the user to run `/codex-pro:setup`

#### Scenario: Timeout exhaustion writes error frontmatter and stops

- **WHEN** `codex-call` exceeds the `--max-time 600` hard timeout
- **THEN** the result file MUST be written with YAML frontmatter `error: timeout` and `findings_count: 0`
- **AND** the skill MUST emit a remediation message suggesting a narrower review target (e.g., a smaller file, a tighter `--base` range)
