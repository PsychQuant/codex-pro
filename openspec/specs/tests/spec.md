# tests Specification

## Purpose

The tests capability provides automated verification of codex-pro's structural correctness and skill behaviour. It defines three layers: Layer 1 (static) checks manifest schemas, SKILL.md frontmatter, shell syntax, the batch template's byte-identical sha256, and namespace consistency; Layer 2 (behavioral) reproduces skill scenarios in isolated environments using fake `HOME`, stripped `PATH`, and mktemp fake plugin roots; Layer 3 (manual) is a markdown checklist for UI verification that the automated layers cannot reach. The runner is pure Bash with two shared libraries (`lib/assert.sh`, `lib/isolate.sh`) and no external framework dependency. Hardcoded invariants — most notably the batch template sha256 reference value — encode design discipline as enforceable assertions so future drift is detected on the next `bash tests/run.sh`.

## Requirements

### Requirement: Test runner entry point

The plugin SHALL provide an executable Bash test runner at `tests/run.sh` that, when executed from the codex-pro repository root, runs all automated layers (static and behavioral) sequentially and reports an aggregate pass/fail summary. The runner MUST exit with code 0 when every assertion passes and a non-zero code when any assertion fails. The runner MUST NOT require external dependencies beyond `bash`, `python3`, and standard POSIX utilities.

#### Scenario: Runner reports pass on a clean repository

- **WHEN** a developer executes `bash tests/run.sh` from the codex-pro repository root in a clean state (no test-induced modifications)
- **THEN** the runner runs `tests/static.sh`, `tests/setup.sh`, and `tests/batch.sh` in sequence
- **AND** the runner prints a final summary including the count of passed and failed assertions
- **AND** the runner exits with code 0

#### Scenario: Runner reports fail when an assertion breaks

- **WHEN** a developer executes `bash tests/run.sh` and at least one assertion in any layer fails (for example, the batch template sha256 has drifted)
- **THEN** the runner prints the failing assertion message identifying the layer and the broken invariant
- **AND** the runner exits with a non-zero code

#### Scenario: Single layer can be executed independently

- **WHEN** a developer executes `bash tests/static.sh` or `bash tests/setup.sh` or `bash tests/batch.sh` directly
- **THEN** the script runs only its own assertions
- **AND** the script reports its own pass/fail summary and exit code

---
### Requirement: Static layer enforces structural invariants

The static layer at `tests/static.sh` SHALL verify the structural correctness of codex-pro artifacts without executing any skill behaviour. It MUST parse `.claude-plugin/marketplace.json` and `plugins/codex-pro/.claude-plugin/plugin.json` with `python3 -c "import json; json.load(open(...))"`, MUST parse the YAML frontmatter of every `SKILL.md` under `plugins/codex-pro/skills/`, MUST run `bash -n` on every `*.sh` file under `tests/` and under `plugins/codex-pro/skills/batch/references/`, MUST verify byte-identical preservation of `script-template.sh` against a hardcoded sha256, and MUST verify namespace consistency across CLAUDE.md, README.md, and main spec files.

#### Scenario: Manifest JSON parses and name alignment holds

- **WHEN** the static layer runs
- **THEN** both `.claude-plugin/marketplace.json` and `plugins/codex-pro/.claude-plugin/plugin.json` parse as valid JSON
- **AND** `marketplace.json` declares `name == "codex-pro"`
- **AND** `marketplace.json` `plugins[0].name == "codex-pro"`
- **AND** `plugin.json` declares `name == "codex-pro"`

#### Scenario: SKILL.md frontmatter parses

- **WHEN** the static layer runs
- **THEN** each `SKILL.md` under `plugins/codex-pro/skills/` has a valid YAML frontmatter
- **AND** the `name` field equals the immediate parent directory basename (e.g., `skills/setup/SKILL.md` has `name: setup`)
- **AND** the `allowed-tools` field contains `Bash`

#### Scenario: Batch template byte-identical preservation

- **WHEN** the static layer runs
- **THEN** `shasum -a 256` on `plugins/codex-pro/skills/batch/references/script-template.sh` produces the hardcoded reference hash

##### Example: reference hash

- **GIVEN** the hardcoded sha256 reference value `746157138caf13436711b92f82af6570843d31c964387aa0b0ccb80c9983c1b0` (recorded during add-batch-skill task 1.2)
- **WHEN** the static layer reads the bundled template at its current location
- **THEN** the computed hash equals the reference value byte-for-byte

#### Scenario: Namespace consistency holds across artifacts

- **WHEN** the static layer runs
- **THEN** the obsolete namespace prefix `/codex-pro-setup` does NOT appear in CLAUDE.md, README.md, or main specs
- **AND** the obsolete plugin name `codex-pro-setup` does NOT appear in `.claude-plugin/marketplace.json` or `plugins/codex-pro/.claude-plugin/plugin.json`
- **AND** the canonical namespace `/codex-pro:` appears in CLAUDE.md, README.md, and main specs

---
### Requirement: Behavioral layer reproduces skill scenarios in isolated environments

The behavioral layer (`tests/setup.sh` and `tests/batch.sh`) SHALL reproduce the spec scenarios defined for setup and batch skills using isolated environments via shared helpers in `tests/lib/isolate.sh`. The behavioral layer MUST NOT mutate the developer's real `~/.codex/`, MUST NOT modify any file under `plugins/codex-pro/`, and MUST clean up any temporary directories it creates.

#### Scenario: Setup behaviour in missing-OAuth environment

- **WHEN** `tests/setup.sh` runs the OAuth token check inside `with_empty_home` (which sets `HOME=/nonexistent`)
- **THEN** the assertion confirms the check reports `missing` status
- **AND** the developer's real `~/.codex/` directory listing remains unchanged before and after the test

#### Scenario: Setup behaviour with corrupted plugin manifest

- **WHEN** `tests/setup.sh` runs the manifest self-check inside `with_fake_plugin_root` and writes a syntactically invalid JSON into the fake manifest
- **THEN** the assertion confirms the check reports a parse error containing the line and column of the failure
- **AND** the temporary directory created by the helper is removed after the test

#### Scenario: Batch SKILL records Design constraint exception

- **WHEN** `tests/batch.sh` inspects `plugins/codex-pro/skills/batch/SKILL.md`
- **THEN** the body contains at least one occurrence of `exception` and at least one occurrence of `constraint`
- **AND** the body explicitly mentions Design constraint #1 by name

#### Scenario: Batch template preserves parallel orchestration markers

- **WHEN** `tests/batch.sh` greps the bundled `script-template.sh`
- **THEN** the template contains a `codex exec` invocation with a `--full-auto` flag (either as literal `codex exec --full-auto` or via `"$CODEX" exec ... --full-auto`)
- **AND** the template contains the shell parallel markers `&` (background process) and `wait` (synchronisation)

---
### Requirement: Manual e2e checklist provides UI verification steps

The plugin SHALL ship a manual e2e checklist at `tests/e2e-checklist.md` containing at least six checkbox items covering installation, setup all-green, setup missing-OAuth, batch trigger, batch parameter prompting, and post-skill read-only verification. The checklist MUST use markdown checkbox syntax (`- [ ]`) so a developer can tick items as they verify them. The checklist is NOT executed by the automated runner.

#### Scenario: Checklist documents both happy and unhappy paths

- **WHEN** a developer opens `tests/e2e-checklist.md`
- **THEN** the file contains at least six lines starting with `- [ ]`
- **AND** the checklist covers (in any order): plugin install via marketplace, setup skill triggers and reports ready when environment is clean, setup skill reports missing OAuth when token absent, batch skill triggers and prompts for required parameters, post-test `~/.codex/` is unchanged, and `tests/run.sh` was executed before any of the above
