## MODIFIED Requirements

### Requirement: Adversarial-review skill registration and argument parsing

The plugin SHALL expose a `/codex-pro:codex-adversarial-review` skill registered at `plugins/codex-pro/skills/codex-adversarial-review/SKILL.md` with a YAML frontmatter declaring `name: codex-adversarial-review`, a descriptive `description` block whose trigger keywords include hostile-reviewer / challenge / stress-test / 壓力測試 verbiage (distinct from review's assessment verbiage to mitigate user-side mental-model overlap) AND the literal substring `v0.2 — untracked-by-default` to make the v0.1 → v0.2 behavior change discoverable, and an `allowed-tools` list containing at least `Bash` (for `codex-call` invocation, `git diff HEAD`, `git ls-files --others --exclude-standard`, and `git check-attr binary`) and `Read` (for target collection). The skill SHALL accept an optional positional target argument with the same three resolution modes as `/codex-pro:codex-review` (no argument or `--diff` → `git diff HEAD` plus untracked enumeration with binary/size filtering [v0.2 behavior change]; file path → Read the file [unchanged]; `--base <ref>` → `git diff <ref>...HEAD` [unchanged]). The `--diff` mode SHALL detect and isolate binary untracked files (via `git check-attr binary` plus NUL-byte sniff in first 8KB) and path-list them in a `### Untracked binaries omitted` section without content injection. The `--diff` mode SHALL apply a per-file 64KB content cap (truncating with the marker `… [truncated at 64KB of N bytes]`) and an aggregate 512KB cap (listing overflow files in `### Untracked files omitted (aggregate size cap)`). The `--diff` mode SHALL detect pre-first-commit repositories (`git diff HEAD` exit code 128 with stderr matching `unknown revision|ambiguous argument 'HEAD'`) and fall back to `git diff --cached` plus working-tree `git diff` plus untracked enumeration, recording `target: diff (pre-first-commit)` in result-file frontmatter. The skill SHALL accept an optional `--focus <area>` flag and an optional `--depth <shallow|deep>` flag (default `deep`). When `--focus` text length exceeds 200 characters after whitespace strip, the skill SHALL truncate the focus to the first 200 characters and record the truncation in the result file frontmatter `focus` field. The skill MUST NOT add a `--legacy-tracked-only` opt-out flag (which would ossify the v0.1 silent-omission bug).

#### Scenario: Skill is registered and discoverable

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/codex-adversarial-review/SKILL.md` MUST exist with valid YAML frontmatter
- **AND** the frontmatter `name` field MUST equal `codex-adversarial-review`
- **AND** the frontmatter `allowed-tools` MUST contain both `Bash` and `Read`
- **AND** the frontmatter `description` MUST contain at least one of the trigger keywords `hostile` / `challenge` / `stress-test` / `壓力測試` (distinct from review's assessment verbiage)
- **AND** the frontmatter `description` MUST contain the literal substring `v0.2 — untracked-by-default`

#### Scenario: --diff mode includes both tracked changes and untracked files

- **WHEN** a user invokes `/codex-pro:codex-adversarial-review` with no positional argument and no `--base`
- **THEN** the skill SHALL run `git diff HEAD` to obtain the tracked-changes portion of the target
- **AND** the skill SHALL run `git ls-files --others --exclude-standard` to enumerate untracked files (respecting `.gitignore`)
- **AND** the result-file target body SHALL include both portions

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

#### Scenario: Target resolution for file and --base modes mirrors review

- **WHEN** a user invokes `/codex-pro:codex-adversarial-review path/to/file.swift`
- **THEN** the skill SHALL Read the file content as the target
- **WHEN** a user invokes `/codex-pro:codex-adversarial-review --base origin/main`
- **THEN** the skill SHALL run `git diff origin/main...HEAD` and use the output as the target

#### Scenario: --depth and --focus are parsed

- **WHEN** a user invokes `/codex-pro:codex-adversarial-review --depth shallow --focus security`
- **THEN** the skill SHALL set `depth=shallow` and `focus=security` for the codex-call invocation
- **AND** when `--depth` is omitted, the skill SHALL default `depth` to `deep`

#### Scenario: --focus over 200 characters is truncated

- **WHEN** a user invokes `/codex-pro:codex-adversarial-review --focus "<350-character string>"`
- **THEN** the skill SHALL truncate the focus to the first 200 characters after whitespace strip
- **AND** the result file frontmatter `focus` field MUST record the truncation (original length and truncated marker)

##### Example: truncation marker

| Input focus length | Stored focus field | Truncation marker |
| --- | --- | --- |
| 50 chars | first 50 chars verbatim | (none) |
| 350 chars | first 200 chars | `; user supplied 350 chars, truncated to 200` |
