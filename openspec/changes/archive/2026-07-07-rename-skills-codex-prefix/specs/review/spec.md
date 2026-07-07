## MODIFIED Requirements

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
