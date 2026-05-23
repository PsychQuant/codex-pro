#!/usr/bin/env bash
# tests/static.sh — Layer 1: structural invariants for codex-pro artifacts.
# Verifies manifest schemas, SKILL.md frontmatter, shell syntax,
# template byte-identical preservation, and namespace consistency.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

# Known-good invariants (locked by add-test-scenarios D5)
BATCH_TEMPLATE_SHA256="746157138caf13436711b92f82af6570843d31c964387aa0b0ccb80c9983c1b0"
PLUGIN_NAME="codex-pro"
NAMESPACE_PREFIX="/codex-pro:"
OBSOLETE_NAMESPACE="/codex-pro-setup"
OBSOLETE_PLUGIN_NAME="codex-pro-setup"

# ── Prerequisites ────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  echo "FATAL: python3 not on PATH (install Xcode Command Line Tools)" >&2
  exit 2
fi

# ── 1. Manifest JSON parse + name alignment ─────────────────────
parse_json_field() {
  # parse_json_field <file> <python-expr-on-d>
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print($2)" "$1" 2>/dev/null
}

mp="$REPO_ROOT/.claude-plugin/marketplace.json"
sp="$REPO_ROOT/plugins/$PLUGIN_NAME/.claude-plugin/plugin.json"
assert_file "$mp" "marketplace.json exists"
assert_file "$sp" "plugin.json exists"

mp_name=$(parse_json_field "$mp" "d['name']" || true)
mp_plugin_name=$(parse_json_field "$mp" "d['plugins'][0]['name']" || true)
mp_plugin_source=$(parse_json_field "$mp" "d['plugins'][0]['source']" || true)
sp_name=$(parse_json_field "$sp" "d['name']" || true)
assert_eq "$PLUGIN_NAME" "$mp_name" "marketplace.name == codex-pro"
assert_eq "$PLUGIN_NAME" "$mp_plugin_name" "marketplace.plugins[0].name == codex-pro"
assert_eq "./plugins/$PLUGIN_NAME" "$mp_plugin_source" "marketplace.plugins[0].source aligned"
assert_eq "$PLUGIN_NAME" "$sp_name" "plugin.name == codex-pro"

# ── 2. SKILL.md frontmatter parse ───────────────────────────────
parse_skill_frontmatter() {
  # parse_skill_frontmatter <path> <field>
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import sys, re
path, field = sys.argv[1], sys.argv[2]
content = open(path).read()
m = re.match(r"^---\n(.*?)\n---\n", content, re.DOTALL)
if not m:
    sys.exit(1)
# Naive YAML field lookup (no nested structures)
for line in m.group(1).splitlines():
    if line.startswith(field + ":"):
        print(line[len(field)+1:].strip())
        break
PY
}

for skill_dir in "$REPO_ROOT/plugins/$PLUGIN_NAME/skills/"*/; do
  skill_name=$(basename "$skill_dir")
  skill_md="${skill_dir}SKILL.md"
  assert_file "$skill_md" "SKILL.md exists for skill '$skill_name'"
  fm_name=$(parse_skill_frontmatter "$skill_md" "name")
  assert_eq "$skill_name" "$fm_name" "SKILL.md frontmatter name matches dir '$skill_name'"
  # allowed-tools containment check (handles single-line list "Bash, Read, ..."
  # or YAML block list). Extract frontmatter (between the first two `---`
  # delimiters), then grep inside for "Bash".
  fm_block=$(awk '/^---$/{count++; next} count==1' "$skill_md")
  if printf '%s\n' "$fm_block" | grep -q "Bash"; then
    pass "SKILL.md '$skill_name' allowed-tools contains Bash"
  else
    fail "SKILL.md '$skill_name' allowed-tools missing Bash"
  fi
done

# ── 3. bash -n on test scripts and batch template ───────────────
for sh in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR/lib"/*.sh \
          "$REPO_ROOT/plugins/$PLUGIN_NAME/skills/batch/references/script-template.sh"; do
  [ -e "$sh" ] || continue
  if bash -n "$sh" 2>/dev/null; then
    pass "bash -n ok: ${sh#$REPO_ROOT/}"
  else
    fail "bash -n failed: ${sh#$REPO_ROOT/}"
  fi
done

# ── 4. Batch template byte-identical preservation ───────────────
template="$REPO_ROOT/plugins/$PLUGIN_NAME/skills/batch/references/script-template.sh"
assert_sha256 "$template" "$BATCH_TEMPLATE_SHA256" "batch template sha256 matches reference"

# ── 5. Namespace consistency ────────────────────────────────────
# Check no obsolete namespace appears in user-facing artifacts
count_matches() {
  # count_matches <pattern> <file> -- prints N (or 0 on no-match / error)
  local out
  out=$(grep -c "$1" "$2" 2>/dev/null || true)
  [ -z "$out" ] && out=0
  printf '%s\n' "$out"
}

for f in "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/README.md" \
         "$REPO_ROOT/openspec/specs/setup/spec.md" \
         "$REPO_ROOT/openspec/specs/batch/spec.md"; do
  [ -r "$f" ] || continue
  rel="${f#$REPO_ROOT/}"
  count=$(count_matches "$OBSOLETE_NAMESPACE" "$f")
  assert_eq "0" "$count" "no obsolete namespace '$OBSOLETE_NAMESPACE' in $rel"
done

# manifests must not carry the obsolete plugin name
for f in "$REPO_ROOT/.claude-plugin/marketplace.json" \
         "$REPO_ROOT/plugins/$PLUGIN_NAME/.claude-plugin/plugin.json"; do
  count=$(count_matches "$OBSOLETE_PLUGIN_NAME" "$f")
  assert_eq "0" "$count" "no obsolete plugin name in ${f#$REPO_ROOT/}"
done

# Canonical namespace must appear in user-facing docs
for f in "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/README.md"; do
  if grep -q "$NAMESPACE_PREFIX" "$f"; then
    pass "canonical namespace '$NAMESPACE_PREFIX' present in ${f#$REPO_ROOT/}"
  else
    fail "canonical namespace '$NAMESPACE_PREFIX' missing in ${f#$REPO_ROOT/}"
  fi
done

# ── Summary ─────────────────────────────────────────────────────
report_summary "static"
exit_code=$?
exit "$exit_code"
