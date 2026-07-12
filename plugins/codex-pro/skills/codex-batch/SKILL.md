---
name: codex-batch
description: |
  Generate and run batch Codex CLI jobs — split a large reference document into chunks,
  parallel-execute codex exec (GPT-5.5 xhigh) with structured prompts, monitor progress.
  Use when: "batch generate", "codex batch", "parallel codex", "generate solutions/summaries/translations for each chapter"
argument-hint: "[task description]"
allowed-tools: Bash, Read, Write, Glob, Grep, Agent(general-purpose)
---

# /codex-pro:codex-batch — Parallel Content Generation with Codex CLI

Generate a shell script that runs `codex exec` in parallel across multiple chunks of a large document, then execute and monitor it.

## codex-pro Design Constraint Exception

This skill is an **explicit exception** to codex-pro Design constraint #1 ("No subprocess spawn for Codex"). That constraint was written to prevent the IPC pipe deadlock pattern that plagues `openai/codex-plugin-cc` (upstream issue #330) on single-shot calls. Batch's fan-out parallel orchestration is a different class of problem: each `codex exec` runs detached as a background job, never attempting interactive pipe coordination with the parent shell. Parallel job control via shell `&` and `wait` is the idiomatic solution for this workload.

Future skills MUST NOT cite this exception as precedent. The default for all codex-pro skills remains HTTPS-direct via the `codex-call` wrapper; subprocess `codex exec` is permitted in this skill only because batch's semantics demand shell-level job control.

## Prerequisites

- `/opt/homebrew/bin/codex` installed and authenticated
- `~/.codex/config.toml` configured (model, reasoning effort)

## Step 1: Collect Parameters

Ask the user for these parameters (skip any they've already provided in the argument):

### Required
1. **Reference file** — the large document to use as context (e.g., a textbook .tex file)
2. **Chunks** — how to split the work (chapter numbers, file list, section IDs)
3. **Prompt template** — what to generate for each chunk
4. **Output directory** — where to save results

### Optional (with defaults)
5. **Model** — default: `gpt-5.6-sol`
6. **Reasoning effort** — default: `xhigh`
7. **Output filename pattern** — default: `ch${ch}_output.tex`
8. **Parallel execution** — default: `true` (all chunks at once)
9. **Chunk names** — human-readable names for each chunk (for prompts and logging)

## Step 2: Generate Shell Script

Create a `generate.sh` script in the output directory using the template from `references/script-template.sh`.

### Key script features:
- **Skip existing**: won't overwrite unless `FORCE=1`
- **Logging**: timestamps, elapsed time, file sizes to `progress.log`
- **Retry**: `FORCE=1 ./generate.sh <chunk>` to redo a specific chunk
- **Stdin context**: sends the entire reference file via stdin to codex
- **Non-interactive**: uses `codex exec` with `--full-auto --skip-git-repo-check`

### Prompt template guidelines:
- Tell the model it has the FULL document — "Do NOT search the web"
- Specify output format explicitly (LaTeX only, Markdown only, etc.)
- Include structural requirements (sections, subsections, formatting)
- Use heredoc with variable interpolation for `${ch}`, `${chunk_name}`

## Step 3: Execute

Run the script in background using Bash with `run_in_background`:

```bash
# Parallel: launch all chunks at once
cd <output_dir> && bash generate.sh
```

If parallel execution requested, modify the script to use `&` and `wait`:
```bash
for ch in "${CHAPTERS[@]}"; do
    generate_chunk "$ch" &
done
wait
```

## Step 4: Monitor Progress

Set up a background monitoring task:

```bash
while true; do
    completed=$(ls <output_dir>/<pattern> 2>/dev/null | wc -l)
    running=$(pgrep -f "codex exec" | wc -l)
    echo "[$(date '+%H:%M:%S')] Files: $completed/<total>, Processes: $running/<total>"
    [[ $completed -ge <total> || $running -eq 0 ]] && break
    sleep 120
done
```

Report to user when done with file sizes and any failures.

## Step 5: Post-Processing Checklist

After all chunks complete, remind the user to:
1. **Check for empty/failed outputs**: `find <dir> -name "<pattern>" -empty`
2. **Strip standalone preambles** if outputs have `\documentclass` (common with LaTeX)
3. **Create a main assembly file** if outputs need to be combined
4. **Compile/validate** the combined output
5. **Retry failures**: `FORCE=1 ./generate.sh <failed_chunk>`

## Example Configurations

### Textbook Exercise Solutions (Concise)
```
reference: accumulated.tex (19,657 lines)
chunks: 2 3 4 5 6 7 8 9 10 13
prompt: "Write complete solutions for ALL exercises in Chapter ${ch}"
output: ch${ch}_solutions.tex
format: LaTeX only, \subsection*{Exercise N.M}, align*/equation*
```

### Textbook Exercise Solutions (Detailed 4-Section)
```
reference: accumulated.tex
chunks: 2 3 4 5 6 7 8 9 10 13
prompt: "Write DETAILED STUDY GUIDE with Concept Review / Strategy / Solution / Intuition"
output: detailed/ch${ch}_solutions.tex
format: LaTeX, \paragraph{Concept Review}, \paragraph{Strategy}, etc.
```

### Document Translation
```
reference: book.tex
chunks: 1 2 3 4 5 ...
prompt: "Translate Chapter ${ch} to Traditional Chinese, preserving all LaTeX formatting"
output: ch${ch}_translated.tex
```

### Chapter Summaries
```
reference: textbook.tex
chunks: 1 2 3 ... N
prompt: "Write a 2-page summary of Chapter ${ch} covering key concepts, theorems, and examples"
output: ch${ch}_summary.tex
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Network stream disconnection | Delete empty output, `FORCE=1 ./generate.sh <ch>` |
| Output has `\documentclass` preamble | `sed -i '' '/^\\documentclass/,/^\\begin{document}/d; /^\\end{document}/d'` |
| Undefined commands from stripped preamble | Find `\newcommand` in deleted preamble, replace usages |
| codex hangs | Check `~/.codex/config.toml`, try with explicit `-m gpt-5.6-sol` |
| 400 `requires a newer version of Codex` | `gpt-5.6-sol` 需 codex CLI ≥ 0.144（實測 0.142.3 → 400、0.144.1 OK）；`npm install -g @openai/codex@latest` 後重跑 |
| Rate limiting | Reduce parallel count or add delay between launches |
