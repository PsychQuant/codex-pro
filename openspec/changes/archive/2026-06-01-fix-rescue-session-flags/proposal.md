## Problem

`rescue` v0.1 shipped (commit 79cedf0 on PsychQuant/codex-pro main) with a documented `--resume <session-id>` / `--fresh` flag pair in SKILL.md, spec, tests, and docs. The SKILL.md Step 4 explicitly instructs Claude to pass `--session <id>` to codex-call when `--resume` is given.

**The flags are a broken promise**: when a user actually invokes `/codex-pro:rescue <task> --resume sess_xyz`, Claude reads SKILL.md, builds the command `codex-call --session sess_xyz --output ... --model ... --effort ... --max-time 600 --instructions ... --prompt-file ...`, runs it, and codex-call exits non-zero with "unknown flag --session". The rescue skill silently breaks at runtime despite passing all 115 static + behavioral test assertions.

Discovered by an ultracode multi-agent workflow (4 design briefs + 8 adversarial skeptics + 1 synthesis) evaluating next-capability candidates: the technical skeptic attacking `review-v2-ensemble`'s `codex-call --session` assumption surfaced that the flag does not exist in the parallel-ai-agents `codex-call` Swift wrapper, indirectly implicating rescue v0.1's identical assumption.

## Root Cause

Two compounding causes:

1. **codex-call has no `--session` flag**. Confirmed by `codex-call --help` and source inspection of `bin/codex-call` (parallel-ai-agents/2.5.1): supported flags are exactly `--output / --model / --effort / --service-tier / --max-time / --instructions / --prompt-file`. No session-tagging mechanism exists; sessions are stateless per-invocation HTTPS calls to `chatgpt.com/backend-api/codex/responses`.

2. **codex-pro test discipline is string-level, not runtime-level**. `tests/rescue.sh` greps SKILL.md for `--resume`, `--fresh`, `session_id`, `resume_from`, and "mutually exclusive" markers — all of which exist in the prose. No assertion actually invokes codex-call with the documented flag set; doing so would burn Codex quota every test run. The blind spot is documented in the codex-pro Layer 2 test design philosophy (structural verification, not behavioral execution).

Rescue v0.1's design.md D1 ("codex-call invocation 沿用 review pattern + 加 session flag") incorrectly assumed codex-call had a `--session` flag without verifying it; the assumption propagated through proposal, spec scenarios, SKILL.md prose, and tests without any layer catching it.

## Proposed Solution

Strip the session-continuity surface from rescue v0.1, downgrading to v0.1.1:

1. **Remove `--resume <session-id>` and `--fresh` argument parsing from SKILL.md Step 1**. Rescue becomes effectively "always fresh" — every invocation creates a new stateless codex-call.

2. **Remove `--session <id>` passthrough from SKILL.md Step 4 invocation block**. The codex-call command line returns to the same shape as review's (no session flag).

3. **Remove `resume_from` from frontmatter required field list (Step 5 + Result file structure section)**. The field cannot be populated without `--resume` input.

4. **Keep `session_id` frontmatter field**. If codex-call's HTTP response surfaces a session/conversation identifier in headers or body (currently unverified), the skill MAY record it for future reference; if not, the field is recorded as `null` or omitted. Either way it does not promise continuity.

5. **Remove "mutually exclusive" prose** describing `--resume` vs `--fresh`. With both flags gone, the exclusivity language has no referent.

6. **Keep all 4 fail-fast classes**, including `task_unclear`. None of them depend on session flags; `task_unclear` is Codex self-reported and rescue-specific independent of session continuity.

Spec change: MODIFY the `Rescue skill registration and argument parsing` requirement to remove the `--resume` / `--fresh` scenarios. Other 3 rescue requirements unchanged.

Tests: drop 4 grep assertions in `tests/rescue.sh` (`--resume`, `--fresh`, `resume_from`, "mutually exclusive"). Aggregate falls from 115 to ~111.

Documentation: CLAUDE.md Commands surface remark and README.md Skills table entry both lose `--resume`/`--fresh` mentions; add a one-line known-limitation note pointing to a future restore change once codex-call gains session support upstream.

## Non-Goals

- Not implementing local session management in codex-pro (e.g., serializing previous prompt as context prefix on `--resume`). That is a v0.2 design discussion, not a bug fix.
- Not modifying the codex-call Swift wrapper. Upstream `parallel-ai-agents` owns codex-call; adding `--session` is their decision.
- Not modifying review v0.1 (review never claimed session continuity).
- Not modifying setup / batch / tests specs or behavior.
- Not changing the rescue capability identifier or the namespace `/codex-pro:rescue`.
- Not invoking real codex-call in any test (Layer 3 manual e2e checklist is the appropriate surface for runtime verification, not Layer 2 simulation).
- Not retroactively rewriting the archive of rescue-minimal (2026-06-01-rescue-minimal stays as historical record of the over-promise; this fix change is its own archive entry).

## Success Criteria

- `plugins/codex-pro/skills/rescue/SKILL.md` no longer contains the strings `--resume`, `--fresh`, `resume_from`, or any "mutually exclusive" prose tied to session flags. Verified by grep yielding 0.
- `plugins/codex-pro/skills/rescue/SKILL.md` retains all 4 fail-fast classes (`rate_limit` / `oauth_invalid` / `timeout` / `task_unclear`) — verified by grep yielding ≥1 each.
- `tests/rescue.sh` no longer asserts presence of `--resume` / `--fresh` / `resume_from` / "mutually exclusive". Verified by grep yielding 0 inside the assertion script.
- `bash tests/run.sh` completes with 0 failures and exit 0; assertion count drops to ~111 (within ±2) and 5 layers remain green.
- `openspec/specs/rescue/spec.md` MODIFIED Requirement `Rescue skill registration and argument parsing` no longer contains the "Resume flag records original session" or "--resume and --fresh are mutually exclusive" scenarios.
- `CLAUDE.md` Commands surface row for `/codex-pro:rescue` no longer mentions `--resume` / `--fresh`; adds a known-limitation note.
- `README.md` Skills table row for `rescue` no longer mentions `--resume` / `--fresh`; adds a known-limitation note.

## Impact

- Affected specs:
  - Modified: openspec/specs/rescue/spec.md (one requirement, two scenarios removed)
- Affected code:
  - Modified:
    - plugins/codex-pro/skills/rescue/SKILL.md (Step 1 + Step 4 + Step 5 + result file structure + comparison-with-review table)
    - tests/rescue.sh (remove 4 assertions for session flags + mutually exclusive marker; keep frontmatter session_id assertion)
    - CLAUDE.md (Commands surface row + Marketplace structure row text)
    - README.md (Skills table row + What it replaces table row)
  - New: (none)
  - Removed: (none)
- Expected test net delta: 115 → ~111 (-4 from rescue.sh) but possibly +1 if a "known limitation" doc-assertion is added to static.sh; final aggregate ≈ 111-112.
- No new files; no file moves; no spec deletions.
- Cross-repo impact: none. parallel-ai-agents not touched. codex-call binary not touched.
