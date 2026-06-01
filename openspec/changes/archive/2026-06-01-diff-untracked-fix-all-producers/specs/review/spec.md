## MODIFIED Requirements

### Requirement: Review skill registration and target resolution

The plugin SHALL expose a `/codex-pro:review` skill registered at `plugins/codex-pro/skills/review/SKILL.md` with a YAML frontmatter declaring `name: review`, a descriptive `description` block (containing the literal substring `v0.2 — untracked-by-default` to make the v0.1 → v0.2 behavior change discoverable), and an `allowed-tools` list containing at least `Bash` (for `codex-call` invocation, `git diff HEAD`, `git ls-files --others --exclude-standard`, and `git check-attr binary`) and `Read` (for file content collection). The skill SHALL accept three mutually-exclusive review targets and resolve them in the following precedence: an explicit `--base <ref>` flag triggers branch comparison via `git diff <ref>...HEAD` (unchanged from v0.1); a positional file-path argument triggers single-file review via reading that file (unchanged from v0.1); no argument or `--diff` flag triggers review of all uncommitted changes via `git diff HEAD` PLUS untracked-file enumeration via `git ls-files --others --exclude-standard`. The `--diff` mode SHALL detect and isolate binary untracked files (via `git check-attr binary` plus NUL-byte sniff in first 8KB) and path-list them in a `### Untracked binaries omitted` section without content injection. The `--diff` mode SHALL apply a per-file 64KB content cap (truncating with the marker `… [truncated at 64KB of N bytes]`) and an aggregate 512KB cap (listing overflow files in `### Untracked files omitted (aggregate size cap)`). The `--diff` mode SHALL detect pre-first-commit repositories (`git diff HEAD` exit code 128 with stderr matching `unknown revision|ambiguous argument 'HEAD'`) and fall back to `git diff --cached` plus working-tree `git diff` plus untracked enumeration, recording `target: diff (pre-first-commit)` in result-file frontmatter. The skill MUST NOT add a `--legacy-tracked-only` opt-out flag (which would ossify the v0.1 silent-omission bug).

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/review/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `review`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`
- **AND** the frontmatter `description` MUST contain the literal substring `v0.2 — untracked-by-default`

#### Scenario: --diff mode includes both tracked changes and untracked files

- **WHEN** a user invokes `/codex-pro:review` (or `/codex-pro:review --diff`) in a repository containing tracked-modified files plus untracked files
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

- **WHEN** a user invokes `/codex-pro:review <file-path>` where `<file-path>` resolves to a readable file inside the project
- **THEN** the skill SHALL collect the entire file content as the review target

#### Scenario: --base flag targets a branch diff

- **WHEN** a user invokes `/codex-pro:review --base <ref>` where `<ref>` is a valid git reference
- **THEN** the skill SHALL run `git diff <ref>...HEAD` to obtain the review target
- **AND** when both a file-path argument and `--base` are provided, the skill SHALL use `--base` (branch comparison takes precedence)

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
- **AND** the skill MUST emit a remediation message directing the user to run `/codex-pro:setup`

#### Scenario: Timeout exhaustion writes error frontmatter and stops

- **WHEN** `codex-call` exceeds the `--max-time 600` hard timeout
- **THEN** the result file MUST be written with YAML frontmatter `error: timeout` and `findings_count: 0`
- **AND** the skill MUST emit a remediation message suggesting a narrower review target (e.g., a smaller file, a tighter `--base` range)

#### Scenario: Target-invalid pre-flight fires when post-filter body is empty

- **WHEN** the `--diff` mode resolves a target body that, after binary detection and size cap filtering, is whitespace-only (zero meaningful content for Codex)
- **THEN** the skill SHALL abort BEFORE invoking `codex-call` (pre-flight)
- **AND** the result file MUST be written with YAML frontmatter `error: target_invalid` and `findings_count: 0`
- **AND** the skill MUST emit a remediation message explaining that the target body was empty after binary and size filtering, suggesting the user verify there are real changes to review (e.g., uncommitted tracked changes, or untracked text files within 64KB each)
