#!/usr/bin/env bash
# tests/lib/e2e-fixtures.sh — Layer 3 e2e fixture builders.
# Five scenarios (mixed / binary / oversize / empty-repo / all-empty) — one
# helper per scenario, each invoked with the target directory.
#
# Fixture content matches the Layer 2 behavioral fixtures (tests/review.sh,
# tests/adversarial-review.sh) so Layer 3 + Layer 2 are 1-to-1 comparable —
# divergence in pass/fail across layers signals SKILL.md → runtime drift.
#
# Source via:
#   source "$SCRIPT_DIR/lib/assert.sh"        # for assert_git_fixture
#   source "$SCRIPT_DIR/lib/e2e-fixtures.sh"

# Guard against double-source
if [ -n "${E2E_FIXTURES_LOADED:-}" ]; then
  return 0
fi
E2E_FIXTURES_LOADED=1

# ── mixed: tracked modified + untracked normal text ──────────────
e2e_fixture_mixed() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "fn baseline() {}" > tracked.swift && git add tracked.swift && git -c gc.auto=0 commit -q -m initial )
  ( cd "$dir" && echo "fn modified() { panic!(\"changed\") }" >> tracked.swift )
  ( cd "$dir" && echo "fn new_feature() { unimplemented!() }" > untracked_normal.swift )
}

# ── binary: untracked text + untracked binary (PNG with NUL bytes) ──
e2e_fixture_binary() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "text content for review" > untracked_text.txt )
  ( cd "$dir" && printf '\x89PNG\r\n\x1a\n\x00\x00binary data inside' > untracked_image.png )
}

# ── oversize: untracked 100KB file → 64KB cap + truncation marker ──
# Use realistic Swift-like code content so Claude actually invokes the skill
# (a 100KB blob of literal 'a' characters is correctly identified as junk
# and Claude refuses to invoke codex-call against it).
e2e_fixture_oversize() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && python3 -c "
content = '\n'.join([
    f'func processItem{i}(input: String) -> Int {{ return input.count + {i} }}'
    for i in range(2000)
])
open('many_funcs.swift', 'w').write(content)
" )
}

# ── empty-repo: pre-first-commit (no HEAD) + 1 untracked text ──
e2e_fixture_empty_repo() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && echo "fresh untracked in pre-first-commit repo" > only_file.txt )
  # NO git commit — leaves repo in pre-first-commit state for fallback test
}

# ── all-empty: empty repo + binary-only → target_invalid post-filter ──
e2e_fixture_all_empty() {
  local dir="$1"
  assert_git_fixture "$dir"
  ( cd "$dir" && printf '\x00\x00\x00\x00binary content only' > only_binary.bin )
  # No tracked changes, no content-eligible untracked → target_invalid fires
}
