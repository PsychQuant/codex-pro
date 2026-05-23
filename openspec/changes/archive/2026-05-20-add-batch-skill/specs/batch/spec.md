## ADDED Requirements

### Requirement: Batch skill registration and parameter collection

The plugin SHALL expose a `/codex-pro:batch` skill triggered by Claude Code's skill invocation mechanism. The skill MUST be declared in `plugins/codex-pro/skills/batch/SKILL.md` with a YAML frontmatter containing `name: batch`, a `description` block describing its batch generation purpose, an `argument-hint`, and an `allowed-tools` list including `Bash` (required for spawning `codex exec`). Upon invocation the skill SHALL collect the following parameters from the user (skipping any already supplied through the slash argument): reference file path, chunk specification, prompt template, output directory, model identifier (default `gpt-5.5`), and reasoning effort (default `xhigh`).

#### Scenario: Skill is discoverable after plugin install

- **WHEN** a developer has installed the `codex-pro` plugin via the `codex-pro` marketplace (or loaded it via `--plugin-dir`)
- **AND** invokes `/codex-pro:batch` in Claude Code
- **THEN** Claude triggers the `batch` skill from `plugins/codex-pro/skills/batch/SKILL.md`
- **AND** the skill is listed under the plugin namespace in `/help` output

#### Scenario: Skill prompts for required parameters

- **WHEN** the user invokes `/codex-pro:batch` without supplying full parameters in the slash argument
- **THEN** the skill SHALL request each missing required parameter individually before proceeding (reference file, chunk specification, prompt template, output directory)
- **AND** the skill SHALL apply default values `gpt-5.5` for model and `xhigh` for reasoning effort when the user omits them

### Requirement: Batch script generation uses bundled template

The skill SHALL generate the executable shell script for parallel batch execution by deriving it from `plugins/codex-pro/skills/batch/references/script-template.sh`. That template file MUST be present alongside the skill and MUST remain byte-identical to the upstream `codex-batch` plugin template at the time of migration so that scripts previously generated under the upstream plugin produce identical output when regenerated.

#### Scenario: Template file accompanies skill

- **WHEN** the plugin is installed
- **THEN** `plugins/codex-pro/skills/batch/references/script-template.sh` MUST exist and be readable

#### Scenario: Generated script matches template structure

- **WHEN** the skill generates a batch script for a given parameter set
- **THEN** the script content MUST be derived from `references/script-template.sh` (with user-supplied parameters substituted into the template's placeholders)
- **AND** the script MUST contain `codex exec --full-auto` invocations consistent with the upstream codex-batch behaviour

### Requirement: Parallel job orchestration via subprocess

The skill SHALL orchestrate per-chunk parallel `codex exec --full-auto` invocations using shell-level subprocess control (background processes and synchronisation primitives such as `wait`). This subprocess-based orchestration is an explicit exception to the codex-pro design constraint that disallows subprocess spawning for Codex (the design constraint targets single-shot calls; batch fan-out is a different class of problem). Other skills in the `codex-pro` plugin MUST NOT take this exception as precedent.

#### Scenario: Per-chunk codex exec runs in parallel

- **WHEN** the generated script is executed with N chunks
- **THEN** up to N `codex exec --full-auto` subprocesses MAY run concurrently (subject to user-configurable concurrency limits in the template)
- **AND** the script MUST report progress (per-chunk start, completion, or failure) so the user sees ongoing status without waiting silently

#### Scenario: Per-chunk output isolation

- **WHEN** the generated script completes execution
- **THEN** each chunk's Codex output MUST be written to a separate file inside the user-specified output directory
- **AND** a chunk failure MUST NOT corrupt or partially write any other chunk's output file
