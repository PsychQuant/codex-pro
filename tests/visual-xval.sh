#!/usr/bin/env bash
# tests/visual-xval.sh — Layer 2: the deterministic scripts behind
# /codex-pro:codex-visual-xval (#23). Every script is exercised as a black-box
# CLI on fixtures; no network, no OAuth, no model downloads.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

# The bundle generator requires the skill directory to hold exactly the manifest's files.
export PYTHONDONTWRITEBYTECODE=1

XVAL_DIR="$REPO_ROOT/plugins/codex-pro/skills/codex-visual-xval"
SCRIPTS="$XVAL_DIR/scripts"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ── SKILL.md: the contract a reader (Claude or Codex) follows ────
SKILL="$XVAL_DIR/SKILL.md"
assert_file "$SKILL" "codex-visual-xval SKILL.md exists"
skill_check=$(python3 - "$SKILL" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
fm = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
fm = fm.group(1) if fm else ""
body = text[text.find("\n---\n", 4) + 5:]
def pos(s):
    return body.find(s) if s in body else 10 ** 9
step4 = re.search(r"### Step 4\.2: codex-call invocation\n(.*?)\n## Step 5", body, re.DOTALL)
step5 = re.search(r"## Step 5: Handle exit code\n(.*?)\n## Step 6", body, re.DOTALL)
checks = {
    "name": "name: codex-visual-xval" in fm,
    "tools": all(t in fm for t in ("- Bash", "- Read")),
    "privacy_before_send": pos("## Step 2: 送出前的隱私提醒") < pos("## Step 4: Invoke codex-call"),
    "seal_before_send": pos("xval.py\" seal --run") < pos("### Step 4.2: codex-call invocation"),
    "runtime_files": bool(step4) and 'CODEX_CALL="$(command -v codex-call)"' in step4.group(1)
        and "runtime_error.txt" in step4.group(1) and "runtime.txt" in step4.group(1),
    "one_runtime_line": body.count('CODEX_CALL="$(command -v codex-call)"') == 1,
    "no_bare_invocation": "codex-call \\\n" not in body,
    "no_codex_cli": re.search(r"(^|\s)codex exec", body) is None,
    "foreground": "前景同步執行" in body and "run_in_background" in body,
    "classes": bool(step5) and all(c in step5.group(1) for c in (
        "rate_limit", "oauth_invalid", "timeout", "target_invalid", "runtime_unsupported", "parse_failed")),
    "all_failures_anchor": "\n\n**所有 failure 仍寫 result file**" in body,
    "no_retry": "所有 failure 都不 retry" in body,
    "one_error_enum": len(re.findall(r"error: <[^>\n]+>", body)) == 1,
    "result_path": ".codex-pro/visual-xval-" in body,
    "sam_consent": "AskUserQuestion" in body and "install --yes" in body,
    "zoom_blind": "不要讀 `$RUN/codex.json`" in body,
    "limitations": "兩個模型一致不代表正確" in body,
}
print(" ".join(f"{k}={'ok' if v else 'MISSING'}" for k, v in checks.items()))
PY
)
case "$skill_check" in
  *MISSING*) fail "SKILL.md states the visual-xval contract: $skill_check" ;;
  *) pass "SKILL.md states the visual-xval contract ($skill_check)" ;;
esac
for ref in references/vocab-format.md references/claim-schema.md; do
  assert_file "$XVAL_DIR/$ref" "SKILL.md reference exists: $ref"
done

# run_py <script> <args...> — sets RUN_STATUS and RUN_OUT (stdout+stderr)
run_py() {
  RUN_STATUS=0
  RUN_OUT=$(python3 "$SCRIPTS/$1" "${@:2}" 2>&1) || RUN_STATUS=$?
}

json_get() {   # json_get <json-text> <python-expression over d>
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); print($2)" "$1" 2>/dev/null
}

# ── Fixtures ─────────────────────────────────────────────────────
cat > "$WORK/vocab.json" <<'JSON'
{
  "classes": {"INST": "laparoscopic instrument", "THREAD": "suture thread", "PAD": "practice pad"},
  "constraints": ["INST count is at most 2"],
  "max_count": {"INST": 2},
  "relations": {"tips_together": {"between": ["INST", "INST"], "definition": "distance_pct < 5"}},
  "position_threshold_pct": 5
}
JSON

# Twelve frames; every frame is identical on both sides except f08, which is the
# spec's worked example (counts and tips agree, tips_together disagrees).
python3 - "$WORK" <<'PY'
import json, sys
work = sys.argv[1]
def frame(name, together, tips):
    return {"frame": name, "objects": {"INST": 2, "THREAD": 1},
            "points": [{"class": "INST", "x_pct": x, "y_pct": y} for x, y in tips]
                      + [{"class": "THREAD", "x_pct": 20, "y_pct": 80}],
            "relations": {"tips_together": together}}
same = [(40, 50), (60, 50)]
claude = [frame(f"f{i:02d}.png", False, same) for i in range(1, 13)]
codex = [frame(f"f{i:02d}.png", False, same) for i in range(1, 13)]
claude[7] = frame("f08.png", True, [(31, 19), (33, 21)])
codex[7] = frame("f08.png", False, [(32, 20), (30, 22)])
json.dump({"claims": claude}, open(f"{work}/claude.json", "w"))
json.dump({"claims": codex}, open(f"{work}/codex.json", "w"))
PY

# ── compare_claims.py: vocabulary ────────────────────────────────
assert_file "$SCRIPTS/compare_claims.py" "compare_claims.py exists"

run_py compare_claims.py check-vocab "$WORK/vocab.json"
assert_eq "0" "$RUN_STATUS" "a vocabulary whose relations all have thresholds is accepted"

python3 - "$WORK" <<'PY'
import json, sys
v = json.load(open(f"{sys.argv[1]}/vocab.json"))
v["relations"]["tips_together"]["definition"] = "the tips are together"
json.dump(v, open(f"{sys.argv[1]}/vocab_nothreshold.json", "w"))
PY
run_py compare_claims.py check-vocab "$WORK/vocab_nothreshold.json"
assert_eq "2" "$RUN_STATUS" "a relation without a numeric threshold exits 2"
assert_contains "$RUN_OUT" '"error": "target_invalid"' "a relation without a threshold is target_invalid"
assert_contains "$RUN_OUT" "tips_together" "the target_invalid detail names the relation"

# A relation names its two classes and is "<quantity> <operator> <number>", nothing looser (#23 verify I5).
python3 - "$WORK" <<'PY'
import json, sys
w = sys.argv[1]
base = json.load(open(f"{w}/vocab.json"))
def variant(name, change):
    v = json.loads(json.dumps(base)); change(v); json.dump(v, open(f"{w}/vocab_{name}.json", "w"))
variant("string_relation", lambda v: v["relations"].update(tips_together="distance_pct < 5"))
variant("loose_definition", lambda v: v["relations"]["tips_together"].update(definition="很近（< 5）"))
variant("unknown_between", lambda v: v["relations"]["tips_together"].update(between=["INST", "SCALPEL"]))
variant("one_between", lambda v: v["relations"]["tips_together"].update(between=["INST"]))
variant("bad_max_count", lambda v: v.update(max_count={"INST": "two"}))
variant("unknown_max_count", lambda v: v.update(max_count={"SCALPEL": 1}))
variant("bad_track_class", lambda v: v.update(track_class="SCALPEL"))
variant("bad_margin", lambda v: v.update(sam_margin_pct=-1))
variant("bad_constraints", lambda v: v.update(constraints="INST count is at most 2"))
PY
for bad in string_relation loose_definition unknown_between one_between bad_max_count unknown_max_count \
           bad_track_class bad_margin bad_constraints; do
  run_py compare_claims.py check-vocab "$WORK/vocab_$bad.json"
  assert_eq "2" "$RUN_STATUS" "an invalid vocabulary is target_invalid ($bad)"
done
run_py compare_claims.py check-vocab "$WORK/vocab_loose_definition.json"
assert_contains "$RUN_OUT" "tips_together" "a definition that names no quantity is rejected, naming the relation"

# ── compare_claims.py: the spec example ──────────────────────────
run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/claude.json" "$WORK/codex.json"
assert_eq "0" "$RUN_STATUS" "comparing two valid claim sets exits 0"
assert_eq "12" "$(json_get "$RUN_OUT" 'd["n_frames"]')" "twelve frames are compared"
assert_eq "0.917" "$(json_get "$RUN_OUT" 'd["agreement_rate"]')" "f08 example: agreement rate is 11/12"
assert_eq "1" "$(json_get "$RUN_OUT" 'len(d["disagreements"])')" "f08 example: exactly one disagreement"
assert_eq "f08.png relation tips_together" \
  "$(json_get "$RUN_OUT" '" ".join([d["disagreements"][0][k] for k in ("frame", "kind", "relation")])')" \
  "f08 example: the disagreement is a relation mismatch on tips_together"
assert_eq "True False" \
  "$(json_get "$RUN_OUT" '"%s %s" % (d["disagreements"][0]["claude"], d["disagreements"][0]["codex"])')" \
  "f08 example: Claude says true and Codex says false"

# ── compare_claims.py: count and position mismatches ─────────────
python3 - "$WORK" <<'PY'
import json, sys
w = sys.argv[1]
codex = json.load(open(f"{w}/codex.json"))
c = codex["claims"]
c[1]["objects"]["INST"] = 1                      # f02: count mismatch
c[1]["points"] = c[1]["points"][:1] + [p for p in c[1]["points"] if p["class"] != "INST"]
c[2]["points"][0] = {"class": "INST", "x_pct": 52, "y_pct": 50}  # f03: 12% off
c[3]["points"].reverse()                          # f04: same points, other order
json.dump(codex, open(f"{w}/codex_mixed.json", "w"))
PY
run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/claude.json" "$WORK/codex_mixed.json"
kinds=$(json_get "$RUN_OUT" '" ".join(sorted("%s:%s" % (x["frame"], x["kind"]) for x in d["disagreements"]))')
assert_contains "$kinds" "f02.png:count" "a different instrument count is a count mismatch"
assert_contains "$kinds" "f03.png:position" "a tip moved beyond the threshold is a position mismatch"
assert_eq "1.0" "$(json_get "$RUN_OUT" '[x["aspect"] for x in d["disagreements"] if x["kind"] == "position"][0]')" \
  "a position disagreement carries the aspect ratio used for its distance"
case "$kinds" in
  *f04.png*) fail "points listed in another order are paired by distance (got: $kinds)" ;;
  *) pass "points listed in another order are paired by distance" ;;
esac
case "$kinds" in
  *f02.png:position*) fail "a frame with a count mismatch does not also report positions for that class" ;;
  *) pass "a frame with a count mismatch does not also report positions for that class" ;;
esac

# ── compare_claims.py: Codex replies that do not fit the schema ──
python3 - "$WORK" <<'PY'
import json, sys
w = sys.argv[1]
c = json.load(open(f"{w}/codex.json"))
c["claims"] = c["claims"][:11]
json.dump(c, open(f"{w}/codex_missing_frame.json", "w"))
c = json.load(open(f"{w}/codex.json"))
c["claims"][0]["objects"]["SCALPEL"] = 1
json.dump(c, open(f"{w}/codex_unknown_class.json", "w"))
c = json.load(open(f"{w}/codex.json"))
c["claims"][0]["objects"]["other"] = 1
json.dump(c, open(f"{w}/codex_other_without_description.json", "w"))
PY
for bad in codex_missing_frame codex_unknown_class codex_other_without_description; do
  run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/claude.json" "$WORK/$bad.json"
  assert_eq "3" "$RUN_STATUS" "Codex claims that break the schema exit 3 ($bad)"
  assert_contains "$RUN_OUT" '"error": "parse_failed"' "Codex claims that break the schema are parse_failed ($bad)"
done
printf 'not json at all' > "$WORK/codex_garbage.json"
run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/claude.json" "$WORK/codex_garbage.json"
assert_eq "3" "$RUN_STATUS" "a Codex reply that is not JSON exits 3"

# Every counted object has exactly one key point (#23 verify B7): a reply that leaves the
# points out is not agreement, it is an incomplete answer.
python3 - "$WORK" <<'PY'
import json, sys
w = sys.argv[1]
c = json.load(open(f"{w}/codex.json"))
c["claims"][0]["points"] = [p for p in c["claims"][0]["points"] if p["class"] != "INST"]
json.dump(c, open(f"{w}/codex_no_points.json", "w"))
c = json.load(open(f"{w}/codex.json"))
c["claims"][0]["points"].append({"class": "PAD", "x_pct": 10, "y_pct": 10})
json.dump(c, open(f"{w}/codex_point_without_object.json", "w"))
PY
for bad in codex_no_points codex_point_without_object; do
  run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/claude.json" "$WORK/$bad.json"
  assert_eq "3" "$RUN_STATUS" "key points that do not match the counts are parse_failed from Codex ($bad)"
done
run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/codex_no_points.json" "$WORK/codex.json"
assert_eq "2" "$RUN_STATUS" "key points that do not match the counts are target_invalid from Claude"

run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/codex_unknown_class.json" "$WORK/codex.json"
assert_eq "2" "$RUN_STATUS" "Claude claims that break the schema are the caller's input error (exit 2)"
assert_contains "$RUN_OUT" '"error": "target_invalid"' "invalid Claude claims are target_invalid"

# ── seal.py: Claude's answers are sealed before Codex is called ──
assert_file "$SCRIPTS/seal.py" "seal.py exists"
cp "$WORK/claude.json" "$WORK/sealed_answers.json"
run_py seal.py seal "$WORK/sealed_answers.json" "$WORK/seal.json"
assert_eq "0" "$RUN_STATUS" "sealing the answers exits 0"
sealed_digest=$(json_get "$(cat "$WORK/seal.json" 2>/dev/null)" 'd["sha256"]')
assert_eq "$(shasum -a 256 "$WORK/sealed_answers.json" | cut -d' ' -f1)" "$sealed_digest" \
  "the seal records the SHA-256 of the answer file"
sealed_at=$(json_get "$(cat "$WORK/seal.json" 2>/dev/null)" 'd["sealed_at"]')
case "$sealed_at" in
  ????-??-??T??:??:??[+-]??:??) pass "sealed_at carries an explicit UTC offset" ;;
  *) fail "sealed_at carries an explicit UTC offset (got '$sealed_at')" ;;
esac

run_py seal.py verify "$WORK/sealed_answers.json" "$WORK/seal.json"
assert_eq "0" "$RUN_STATUS" "verifying an untouched answer file exits 0"
assert_eq "False" "$(json_get "$RUN_OUT" 'd["seal_broken"]')" "untouched answers keep the seal"
assert_eq "$sealed_digest" "$(json_get "$RUN_OUT" 'd["sha256_now"]')" "the digest is recomputed and matches"

printf ' ' >> "$WORK/sealed_answers.json"
run_py seal.py verify "$WORK/sealed_answers.json" "$WORK/seal.json"
assert_eq "0" "$RUN_STATUS" "verifying an edited answer file still exits 0 (the run goes on)"
assert_eq "True" "$(json_get "$RUN_OUT" 'd["seal_broken"]')" "an edited answer file breaks the seal"

run_py seal.py verify "$WORK/sealed_answers.json" "$WORK/no-such-seal.json"
assert_eq "True" "$(json_get "$RUN_OUT" 'd["seal_broken"]')" "a missing seal record counts as a broken seal"

# ── sam_track.py: collapse detection, anchors, missing environment ──
assert_file "$SCRIPTS/sam_track.py" "sam_track.py exists"
# One-row synthetic masks with hand-computed IoU: [0,17) vs [3,20) -> 14/20 = 0.7;
# [0,10) vs [8,20) -> 2/20 = 0.1. No model is downloaded.
python3 - "$WORK" <<'PY'
import json, sys
row = lambda lo, hi: [[1 if lo <= i < hi else 0 for i in range(20)]]
json.dump({"f05.png": {"1": row(0, 17), "2": row(3, 20)},
           "f06.png": {"1": row(0, 10), "2": row(8, 20)}},
          open(f"{sys.argv[1]}/masks.json", "w"))
PY
run_py sam_track.py check-collapse "$WORK/masks.json"
assert_eq "0" "$RUN_STATUS" "check-collapse exits 0"
assert_eq "['f05.png']" "$(json_get "$RUN_OUT" 'd["invalid_frames"]')" "masks with IoU 0.7 mark the frame invalid; IoU 0.1 does not"
assert_eq "0.7 0.1" "$(json_get "$RUN_OUT" '"%s %s" % (d["max_iou"]["f05.png"], d["max_iou"]["f06.png"])')" "the reported IoU values are the hand-computed ones"

run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/claude.json" "$WORK/codex.json"
printf '%s' "$RUN_OUT" > "$WORK/comparison.json"
run_py sam_track.py anchors "$WORK/comparison.json" "$WORK/claude.json" "$WORK/codex.json" --class INST
assert_eq "0" "$RUN_STATUS" "anchors exits 0"
assert_eq "f01.png f09.png" "$(json_get "$RUN_OUT" '" ".join(a["frame"] for a in d["anchors"])')" \
  "every run of agreeing frames gets its own anchor (f08 splits the run)"
assert_eq "[[40.0, 50.0], [60.0, 50.0]]" "$(json_get "$RUN_OUT" 'sorted(d["anchors"][0]["points"])')" \
  "anchor points are the agreed positions"

mkdir -p "$WORK/fakemods/torch"
printf 'raise ImportError("simulated: torch is not installed")\n' > "$WORK/fakemods/torch/__init__.py"
RUN_STATUS=0
RUN_OUT=$(PYTHONPATH="$WORK/fakemods" python3 "$SCRIPTS/sam_track.py" track --frames "$WORK/claude.json" \
  --anchors /dev/null --out "$WORK/track.json" 2>&1) || RUN_STATUS=$?
assert_eq "4" "$RUN_STATUS" "track without the SAM environment exits 4"
assert_contains "$RUN_OUT" '"sam_status": "not_installed"' "track without the SAM environment reports not_installed"
assert_no_file "$WORK/track.json" "track without the SAM environment writes no tracking output"

# ── sam_track.py: tip geometry ignores a thread stuck to the instrument ──
# Synthetic 200x120 frame: bright circular view on black; a 12-px-thick shaft enters
# from the left edge of the circle and ends at x=110; a 1-px thread continues from the
# shaft end to x=170. SAM often includes such a thread in the instrument mask (seen on
# real frames), which made "farthest point" tip rules run along the thread.
if python3 -c 'import numpy' 2>/dev/null; then
  python3 - "$WORK" <<'PY'
import json, sys
W, H = 200, 120
image = [[0 if (x - 100) ** 2 + (y - 60) ** 2 > 58 ** 2 else 200 for x in range(W)] for y in range(H)]
mask = [[0] * W for _ in range(H)]
for y in range(54, 66):
    for x in range(42, 111):
        if image[y][x]:
            mask[y][x] = 1
for x in range(111, 171):
    mask[60][x] = 1
json.dump({"image_gray": image, "mask": mask}, open(f"{sys.argv[1]}/tipcase.json", "w"))
PY
  run_py sam_track.py tip-check "$WORK/tipcase.json"
  assert_eq "0" "$RUN_STATUS" "tip-check exits 0"
  tip_x=$(json_get "$RUN_OUT" 'round(d["tip_px"][0])')
  entry_x=$(json_get "$RUN_OUT" 'round(d["entry_px"][0])')
  case "$tip_x" in
    10[6-9]|110) pass "the tip is the end of the shaft, not the end of the thread (x=$tip_x)" ;;
    *) fail "the tip is the end of the shaft, not the end of the thread (expected x≈108, got '$tip_x')" ;;
  esac
  case "$entry_x" in
    4[2-6]) pass "the entry is where the shaft meets the edge of the view (x=$entry_x)" ;;
    *) fail "the entry is where the shaft meets the edge of the view (expected x≈43, got '$entry_x')" ;;
  esac
  # A dark metal shaft (grey 0, as on the real frames) entering diagonally from the lower
  # left: scanning pixels in raster order meets the inner end first, so a dark object
  # mistaken for "outside the view" put the entry at the inner end and the tip at the edge.
  python3 - "$WORK" <<'PY'
import json, math, sys
W, H = 200, 120
image = [[0 if (x - 100) ** 2 + (y - 60) ** 2 > 58 ** 2 else 200 for x in range(W)] for y in range(H)]
mask = [[0] * W for _ in range(H)]
(x0, y0), (x1, y1) = (40, 100), (110, 40)          # from beyond the lower-left edge to the inner end
length = math.hypot(x1 - x0, y1 - y0)
for y in range(H):
    for x in range(W):
        t = ((x - x0) * (x1 - x0) + (y - y0) * (y1 - y0)) / length ** 2
        if 0 <= t <= 1 and abs((x - x0) * (y1 - y0) - (y - y0) * (x1 - x0)) / length <= 6 and image[y][x]:
            mask[y][x] = 1
for i in range(1, 40):                              # thin thread continuing up-right
    mask[40 - i // 2][110 + i] = 1
for y in range(H):
    for x in range(W):
        if mask[y][x]:
            image[y][x] = 0                         # the instrument is dark
json.dump({"image_gray": image, "mask": mask}, open(f"{sys.argv[1]}/tipcase_dark.json", "w"))
PY
  run_py sam_track.py tip-check "$WORK/tipcase_dark.json"
  dark_tip=$(json_get "$RUN_OUT" '"%d,%d" % (round(d["tip_px"][0]), round(d["tip_px"][1]))')
  dark_ok=$(json_get "$RUN_OUT" 'abs(d["tip_px"][0] - 110) <= 6 and abs(d["tip_px"][1] - 40) <= 6')
  if [ "$dark_ok" = "True" ]; then
    pass "a dark diagonal shaft has its tip at the inner end ($dark_tip)"
  else
    fail "a dark diagonal shaft has its tip at the inner end (expected ≈110,40, got '$dark_tip')"
  fi
  # An object that only touches the edge of the view has no inner end: its "tip" would sit
  # on the edge (seen on a real frame, 21% away from the instrument's actual tip). No tip
  # is better evidence than a wrong one.
  python3 - "$WORK" <<'PY'
import json, sys
W, H = 200, 120
image = [[0 if (x - 100) ** 2 + (y - 60) ** 2 > 58 ** 2 else 200 for x in range(W)] for y in range(H)]
mask = [[1 if 50 <= y <= 70 and 42 <= x <= 44 and image[y][x] else 0 for x in range(W)] for y in range(H)]
json.dump({"image_gray": image, "mask": mask}, open(f"{sys.argv[1]}/tipcase_edge.json", "w"))
PY
  run_py sam_track.py tip-check "$WORK/tipcase_edge.json"
  assert_eq "None" "$(json_get "$RUN_OUT" 'd["tip_px"]')" "an object that only touches the edge of the view has no tip"
else
  fail "numpy is available for the SAM geometry tests"
fi

# ── sam_env.sh: consent before a ~1 GB download, pinned versions, no half-installed env ──
assert_file "$SCRIPTS/sam_env.sh" "sam_env.sh exists"
mkdir -p "$WORK/stubbin" "$WORK/home"
cat > "$WORK/stubbin/uv" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UV_LOG"
case "$1" in
  venv)
    dir="${@: -1}"; mkdir -p "$dir/bin"
    printf '#!/bin/sh\nexit 0\n' > "$dir/bin/python"; chmod +x "$dir/bin/python" ;;
  pip) exit "${UV_PIP_STATUS:-0}" ;;
esac
STUB
chmod +x "$WORK/stubbin/uv"
run_env() {   # run_env <args...> — isolated HOME, stub uv first on PATH
  RUN_STATUS=0
  RUN_OUT=$(HOME="$WORK/home" UV_LOG="$WORK/uv.log" PATH="$WORK/stubbin:$PATH" \
    bash "$SCRIPTS/sam_env.sh" "$@" 2>&1) || RUN_STATUS=$?
}
SAM_ENV="$WORK/home/.codex-pro/sam-env"

run_env --check
assert_eq "1" "$RUN_STATUS" "--check without an environment exits 1"
assert_contains "$RUN_OUT" "not_installed" "--check without an environment reports not_installed"

run_env install
assert_eq "3" "$RUN_STATUS" "install without --yes exits 3 (consent required)"
assert_contains "$RUN_OUT" "856 MB" "install without --yes states the measured model size"
assert_contains "$RUN_OUT" "--yes" "install without --yes says how to consent"
assert_no_file "$SAM_ENV" "install without --yes creates nothing"
assert_no_file "$WORK/uv.log" "install without --yes never calls uv"

run_env install --yes
assert_eq "0" "$RUN_STATUS" "install --yes with a working uv exits 0"
uv_calls=$(cat "$WORK/uv.log" 2>/dev/null)
assert_contains "$uv_calls" "venv --python 3.13 $SAM_ENV" "the environment is created under ~/.codex-pro/sam-env"
for pin in torch==2.14.1 torchvision==0.29.1 transformers==5.19.0 numpy==2.5.3 pillow==10.4.0; do
  assert_contains "$uv_calls" "$pin" "install pins $pin"
done
run_env --check
assert_eq "0" "$RUN_STATUS" "--check after install exits 0"
assert_contains "$RUN_OUT" "installed" "--check after install reports installed"

rm -rf "$WORK/home/.codex-pro" "$WORK/uv.log"
RUN_STATUS=0
RUN_OUT=$(HOME="$WORK/home" UV_LOG="$WORK/uv.log" UV_PIP_STATUS=1 PATH="$WORK/stubbin:$PATH" \
  bash "$SCRIPTS/sam_env.sh" install --yes 2>&1) || RUN_STATUS=$?
assert_eq "1" "$RUN_STATUS" "a failed package install exits 1"
assert_contains "$RUN_OUT" "error=install_failed" "a failed package install is reported"
assert_no_file "$SAM_ENV" "a failed install leaves no half-installed environment"

mkdir -p "$SAM_ENV" && printf 'user data\n' > "$SAM_ENV/keep.txt"
run_env install --yes
assert_eq "2" "$RUN_STATUS" "install refuses to touch an existing directory it did not create"
assert_file "$SAM_ENV/keep.txt" "the unknown directory is left alone"

# ── adjudicate.py: third evidence only, no majority vote ─────────
assert_file "$SCRIPTS/adjudicate.py" "adjudicate.py exists"
python3 - "$WORK" <<'PY'
import json, sys
w = sys.argv[1]
vocab = json.load(open(f"{w}/vocab.json")); vocab["max_count"] = {"INST": 2}
json.dump(vocab, open(f"{w}/vocab_limits.json", "w"))
rel = {"id": "d1", "frame": "f08.png", "kind": "relation", "relation": "tips_together",
       "definition": "distance_pct < 5", "claude": True, "codex": False}
cnt = {"id": "d2", "frame": "f02.png", "kind": "count", "class": "INST", "claude": 3, "codex": 2}
cnt_low = {"id": "d3", "frame": "f03.png", "kind": "count", "class": "INST", "claude": 2, "codex": 1}
json.dump({"n_frames": 12, "agreement_rate": 0.75, "frames": {}, "disagreements": [rel, cnt, cnt_low]},
          open(f"{w}/disputes.json", "w"))
def track(dist, invalid=False, objects=2):
    obj = {"area": 900, "centroid_pct": [50, 50], "tip_pct": [50, 50], "entry_pct": [10, 90]}
    return {"sam_status": "ok", "frames": {
        "f08.png": {"invalid": invalid, "max_iou": 0.7 if invalid else 0.0, "distance_pct": dist,
                    "objects": {"1": obj, "2": obj}},
        "f03.png": {"invalid": False, "max_iou": 0.0, "distance_pct": 20.0,
                    "objects": {str(k): obj for k in range(1, objects + 1)}}}}
json.dump(track(3.5), open(f"{w}/track_35.json", "w"))
json.dump(track(5.18), open(f"{w}/track_518.json", "w"))
json.dump(track(3.5, invalid=True), open(f"{w}/track_collapsed.json", "w"))
json.dump(track(8.0, objects=1), open(f"{w}/track_8_one_object.json", "w"))
json.dump({"d1": {"claude": True, "codex": True}}, open(f"{w}/zoom_claude.json", "w"))
json.dump({"d1": {"claude": False, "codex": False}}, open(f"{w}/zoom_codex.json", "w"))
PY
verdict() {   # verdict <id> — from RUN_OUT
  json_get "$RUN_OUT" "[a['verdict'] for a in d['adjudications'] if a['id'] == '$1'][0]"
}

run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes.json" --sam "$WORK/track_35.json"
assert_eq "0" "$RUN_STATUS" "adjudicate exits 0"
assert_eq "resolved_claude" "$(verdict d1)" "spec example: SAM measures 3.5% (threshold 5, margin 1) -> resolved_claude"
assert_contains "$(json_get "$RUN_OUT" "[a['evidence'] for a in d['adjudications'] if a['id'] == 'd1'][0]")" "3.5" \
  "the SAM measurement is recorded as evidence"
assert_eq "resolved_codex" "$(verdict d2)" "a count above the vocabulary's maximum loses (3 instruments vs max 2)"

run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes.json" --sam "$WORK/track_518.json"
assert_eq "unverifiable" "$(verdict d1)" "a measurement within the SAM margin (5.18 vs 5) is not evidence"

run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes.json" --sam "$WORK/track_collapsed.json"
assert_eq "unverifiable" "$(verdict d1)" "a collapsed SAM frame is not evidence"

run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes.json"
assert_eq "unverifiable" "$(verdict d1)" "without any third evidence the disagreement is unverifiable"

run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes.json" --zoom "$WORK/zoom_codex.json"
assert_eq "resolved_codex" "$(verdict d1)" "matching zoom-round answers that agree with Codex resolve to Codex"

python3 - "$WORK" <<'PY'
import json, sys
w = sys.argv[1]
pos = {"id": "d9", "frame": "f03.png", "kind": "position", "class": "INST", "claude": [40, 50], "codex": [52, 50],
       "distance_pct": 12.0, "threshold_pct": 5, "aspect": 1.0}
json.dump({"disagreements": [pos]}, open(f"{w}/disputes_pos.json", "w"))
json.dump({"d9": {"claude": [41, 50], "codex": [40.5, 51]}}, open(f"{w}/zoom_pos.json", "w"))
json.dump({"d9": {"claude": [41, 50], "codex": [52, 50]}}, open(f"{w}/zoom_pos_split.json", "w"))
PY
run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes_pos.json" --zoom "$WORK/zoom_pos.json"
assert_eq "resolved_claude" "$(verdict d9)" "zoom points that agree near Claude's original point resolve to Claude"
run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes_pos.json" --zoom "$WORK/zoom_pos_split.json"
assert_eq "unverifiable" "$(verdict d9)" "zoom points that still disagree are not evidence"

run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes.json" --zoom "$WORK/zoom_codex.json" --sam "$WORK/track_35.json"
assert_eq "unverifiable" "$(verdict d1)" "zoom round and SAM pointing to different sides is unverifiable"

run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes.json" --sam "$WORK/track_35.json"
assert_eq "resolved_claude" "$(verdict d3)" "SAM tracking two objects confirms the higher count (2 vs 1)"
run_py adjudicate.py "$WORK/vocab_limits.json" "$WORK/disputes.json" --sam "$WORK/track_8_one_object.json"
assert_eq "unverifiable" "$(verdict d3)" "SAM seeing fewer objects cannot refute the higher count (it only tracks anchored objects)"
# d1: 8.0% is beyond 5 ± 1, so "not together" -> Codex; d2: 3 > max 2 -> Codex; d3: unverifiable
assert_eq "0 2 1" "$(json_get "$RUN_OUT" '"%d %d %d" % (d["counts"]["resolved_claude"], d["counts"]["resolved_codex"], d["counts"]["unverifiable"])')" \
  "the summary counts every verdict once"

# ── xval.py: the orchestrator, behind a mock codex-call ──────────
# The mock records every invocation. MOCK_HELP_IMAGE=0 drops --image from --help (an old
# runtime); MOCK_REPLY is copied to --output; MOCK_STDERR/MOCK_STATUS simulate failures.
assert_file "$SCRIPTS/xval.py" "xval.py exists"
cat > "$WORK/stubbin/codex-call" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then
  printf 'codex-call\n  --output FILE\n'
  [ "${MOCK_HELP_IMAGE:-1}" = "1" ] && printf '  --image FILE   attach an image\n'
  exit 0
fi
printf '%s\n' "$*" >> "$MOCK_LOG"
out=""; prompt=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output) out="$2"; shift 2 ;;
    --prompt-file) prompt="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$prompt" ] && cat "$prompt" >> "$MOCK_PROMPTS"
[ -n "${MOCK_STDERR:-}" ] && printf '%s\n' "$MOCK_STDERR" >&2
[ -n "${MOCK_REPLY:-}" ] && [ -n "$out" ] && cp "$MOCK_REPLY" "$out"
exit "${MOCK_STATUS:-0}"
STUB
chmod +x "$WORK/stubbin/codex-call"

# Twelve neutral test images (200x120 PNG) made with sips — macOS, like the producer itself.
mkdir -p "$WORK/imgs"
base64 -D <<<'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAAABJRU5ErkJggg==' > "$WORK/dot.png"
for i in $(seq -w 1 12); do sips -z 120 200 "$WORK/dot.png" --out "$WORK/imgs/shot_2026-09-11_10$i.png" >/dev/null; done

# Claude's claims use a value that appears nowhere else, so the prompt can be searched for it.
python3 - "$WORK" <<'PY'
import json, sys
w = sys.argv[1]
c = json.load(open(f"{w}/claude.json"))
for i, claim in enumerate(c["claims"], 1):
    claim["frame"] = f"f{i:02d}.png"
c["claims"][0]["points"][0]["x_pct"] = 41.37
json.dump(c, open(f"{w}/claude_marked.json", "w"))
x = json.load(open(f"{w}/codex.json"))
for i, claim in enumerate(x["claims"], 1):
    claim["frame"] = f"f{i:02d}.png"
open(f"{w}/codex_reply.md", "w").write("Here are my answers.\n```json\n" + json.dumps(x) + "\n```\n")
PY

xval() {   # xval <args...> — mock runtime, isolated HOME
  RUN_STATUS=0
  RUN_OUT=$(HOME="$WORK/home" MOCK_LOG="$WORK/mock.log" MOCK_PROMPTS="$WORK/prompts.txt" \
    PATH="$WORK/stubbin:$PATH" python3 "$SCRIPTS/xval.py" "$@" 2>&1) || RUN_STATUS=$?
}
new_run() {   # new_run <dir> — init a run on the twelve images and seal Claude's marked claims
  rm -rf "$1" "$WORK/mock.log" "$WORK/prompts.txt"
  xval init --run "$1" --vocab "$WORK/vocab.json" "$WORK"/imgs/*.png
  cp "$WORK/claude_marked.json" "$1/claude.json"
  printf '%s\n' "$WORK/stubbin/codex-call" > "$1/runtime.txt"
  : > "$1/runtime_error.txt"
  xval seal --run "$1"
}

new_run "$WORK/run1"
assert_eq "0" "$RUN_STATUS" "init and seal exit 0"
assert_eq "f01.png f12.png" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); n=sorted(d); print(n[0], n[-1])' "$WORK/run1/frames.json")" \
  "images get neutral names f01…f12"
assert_eq "False" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(any("2026" in k for k in d))' "$WORK/run1/frames.json")" \
  "neutral names carry no timestamps from the original file names"

# Runtime image capability preflight: an old runtime is refused before anything is sent.
RUN_STATUS=0
RUN_OUT=$(HOME="$WORK/home" MOCK_HELP_IMAGE=0 MOCK_LOG="$WORK/mock.log" MOCK_PROMPTS="$WORK/prompts.txt" \
  PATH="$WORK/stubbin:$PATH" python3 "$SCRIPTS/xval.py" ask --run "$WORK/run1" --round 1 --model m --effort e --max-time 30 2>&1) || RUN_STATUS=$?
assert_eq "5" "$RUN_STATUS" "a runtime without --image stops the run (exit 5)"
assert_contains "$RUN_OUT" '"error": "runtime_unsupported"' "a runtime without --image is runtime_unsupported"
assert_no_file "$WORK/mock.log" "no request is sent to a runtime without --image"

# A runtime path that is missing is runtime_unavailable, not a crash.
: > "$WORK/run1/runtime.txt"
xval ask --run "$WORK/run1" --round 1 --model m --effort e --max-time 30
assert_contains "$RUN_OUT" '"error": "runtime_unavailable"' "no runtime on PATH is runtime_unavailable"
printf 'package_corruption\nerror=hash_mismatch expected=abc\n' > "$WORK/run1/runtime_error.txt"
xval ask --run "$WORK/run1" --round 1 --model m --effort e --max-time 30
assert_contains "$RUN_OUT" '"error": "package_corruption"' "a native preflight error is carried through unchanged"
assert_no_file "$WORK/mock.log" "a native preflight error sends nothing"

# Blind Codex judgment: images by --image, neutral names, no Claude claims in the prompt.
new_run "$WORK/run2"
RUN_STATUS=0
RUN_OUT=$(HOME="$WORK/home" MOCK_REPLY="$WORK/codex_reply.md" MOCK_LOG="$WORK/mock.log" MOCK_PROMPTS="$WORK/prompts.txt" \
  PATH="$WORK/stubbin:$PATH" python3 "$SCRIPTS/xval.py" ask --run "$WORK/run2" --round 1 --model m --effort e --max-time 30 2>&1) || RUN_STATUS=$?
assert_eq "0" "$RUN_STATUS" "round 1 with a valid JSON reply exits 0"
assert_eq "12" "$(grep -o -- '--image ' "$WORK/mock.log" | wc -l | tr -d ' ')" "round 1 sends all twelve images with --image"
assert_contains "$(cat "$WORK/mock.log")" "--max-time 30" "round 1 passes the profile's hard timeout"
prompt=$(cat "$WORK/prompts.txt" 2>/dev/null)
assert_contains "$prompt" "f01.png" "the prompt names the frames by their neutral names"
assert_contains "$prompt" "tips_together" "the prompt carries the vocabulary's relations"
assert_contains "$prompt" "at most 2 objects of class INST" "the prompt carries the vocabulary's maximum counts"
assert_contains "$prompt" "between the key points of INST and INST" "the prompt says which key points a relation measures"
assert_contains "$prompt" "one key point for every object you count" "the prompt asks for one key point per counted object"
case "$prompt" in
  *touching*) fail "the prompt no longer asks what each point touches" ;;
  *) pass "the prompt no longer asks what each point touches" ;;
esac
case "$prompt" in
  *41.37*|*shot_2026*) fail "the prompt carries no Claude claim values and no original file names" ;;
  *) pass "the prompt carries no Claude claim values and no original file names" ;;
esac
case "$RUN_OUT" in
  *x_pct*|*'"claims"'*) fail "ask prints a status, not Codex's answers (keeps Claude blind for the zoom round)" ;;
  *) pass "ask prints a status, not Codex's answers (keeps Claude blind for the zoom round)" ;;
esac
assert_file "$WORK/run2/codex.json" "Codex's answers are written to the run directory"

# A reply that is not JSON is parse_failed, and nothing is retried.
new_run "$WORK/run3"
printf 'I cannot see any images.\n' > "$WORK/garbage_reply.md"
RUN_STATUS=0
RUN_OUT=$(HOME="$WORK/home" MOCK_REPLY="$WORK/garbage_reply.md" MOCK_LOG="$WORK/mock.log" MOCK_PROMPTS="$WORK/prompts.txt" \
  PATH="$WORK/stubbin:$PATH" python3 "$SCRIPTS/xval.py" ask --run "$WORK/run3" --round 1 --model m --effort e --max-time 30 2>&1) || RUN_STATUS=$?
assert_contains "$RUN_OUT" '"error": "parse_failed"' "a reply without JSON claims is parse_failed"
assert_eq "1" "$(wc -l < "$WORK/mock.log" | tr -d ' ')" "a parse failure is not retried (one request)"

# Rate limit and timeout are classified from the runtime's stderr; still one request.
for case_ in "rate limit exceeded (429):rate_limit" "request timed out after 30s:timeout" "401 unauthorized:oauth_invalid"; do
  new_run "$WORK/run4"
  RUN_STATUS=0
  RUN_OUT=$(HOME="$WORK/home" MOCK_STDERR="${case_%%:*}" MOCK_STATUS=1 MOCK_LOG="$WORK/mock.log" MOCK_PROMPTS="$WORK/prompts.txt" \
    PATH="$WORK/stubbin:$PATH" python3 "$SCRIPTS/xval.py" ask --run "$WORK/run4" --round 1 --model m --effort e --max-time 30 2>&1) || RUN_STATUS=$?
  assert_contains "$RUN_OUT" "\"error\": \"${case_##*:}\"" "'${case_%%:*}' is classified as ${case_##*:}"
  assert_eq "1" "$(wc -l < "$WORK/mock.log" | tr -d ' ')" "${case_##*:} is not retried"
done

# ── xval.py: compare, crops, zoom round, SAM step, adjudication (task 4.2) ──
cat > "$WORK/zoom_reply.md" <<'JSON'
{"answers": {"z01.png": {"value": false}}}
JSON
ask_with() {   # ask_with <reply> <run> <round>
  RUN_STATUS=0
  RUN_OUT=$(HOME="$WORK/home" MOCK_REPLY="$1" MOCK_LOG="$WORK/mock.log" MOCK_PROMPTS="$WORK/prompts.txt" \
    PATH="$WORK/stubbin:$PATH" python3 "$SCRIPTS/xval.py" ask --run "$2" --round "$3" --model m --effort e --max-time 30 2>&1) || RUN_STATUS=$?
}
new_run "$WORK/run5"
ask_with "$WORK/codex_reply.md" "$WORK/run5" 1
xval compare --run "$WORK/run5"
assert_eq "0" "$RUN_STATUS" "compare exits 0"
assert_eq "1" "$(json_get "$RUN_OUT" 'd["n_disagreements"]')" "compare reports the one disagreement (f08)"
assert_eq "d1 f08.png relation tips_together" \
  "$(json_get "$RUN_OUT" '" ".join(str(d["disputes"][0][k]) for k in ("id", "frame", "kind", "relation"))')" \
  "compare names the disputed frame, kind and relation"
case "$RUN_OUT" in
  *'"claude"'*|*'"codex"'*|*x_pct*) fail "compare prints no answer values" ;;
  *) pass "compare prints no answer values" ;;
esac
assert_file "$WORK/run5/comparison.json" "the full comparison is kept in the run directory"

xval crops --run "$WORK/run5"
assert_eq "0" "$RUN_STATUS" "crops exits 0"
assert_eq "1" "$(ls "$WORK/run5/crops" 2>/dev/null | wc -l | tr -d ' ')" "only the disputed frame is cropped"
crop_w=$(sips -g pixelWidth "$WORK/run5/crops/z01.png" 2>/dev/null | awk '/pixelWidth/{print $2}')
box_w=$(python3 -c 'import json,sys; b=json.load(open(sys.argv[1]))["d1"]["box_px"]; print(b[2]-b[0])' "$WORK/run5/zoom_plan.json")
assert_eq "$((box_w * 2))" "$crop_w" "the crop is enlarged twice"

rm -f "$WORK/mock.log" "$WORK/prompts.txt"
cp "$WORK/run5/zoom_plan.json" "$WORK/zoom_plan_before.json"
printf '{"d1": false}\n' > "$WORK/run5/zoom_claude.json"
xval seal --run "$WORK/run5" --zoom
ask_with "$WORK/zoom_reply.md" "$WORK/run5" zoom
assert_eq "0" "$RUN_STATUS" "the zoom round exits 0"
assert_eq "1" "$(grep -o -- '--image ' "$WORK/mock.log" | wc -l | tr -d ' ')" "the zoom round sends only the one crop"
assert_contains "$(cat "$WORK/mock.log")" "crops/z01.png" "the zoom round sends the crop, not the full frame"
zoom_prompt=$(cat "$WORK/prompts.txt" 2>/dev/null)
assert_contains "$zoom_prompt" "INST: laparoscopic instrument" "the zoom prompt carries the class definitions"
case "$zoom_prompt" in
  *41.37*|*'"claims"'*|*'"tips_together":'*) fail "the zoom prompt carries neither side's earlier answers" ;;
  *) pass "the zoom prompt carries neither side's earlier answers" ;;
esac

xval sam --run "$WORK/run5"
assert_eq "0" "$RUN_STATUS" "the SAM step never stops the run"
assert_contains "$RUN_OUT" '"sam_status": "not_applicable"' "images that are not a sequence get sam_status not_applicable"
python3 - "$WORK/run5/meta.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); m["sequence"] = True; json.dump(m, open(sys.argv[1], "w"))
PY
rm -rf "$WORK/home/.codex-pro"
xval sam --run "$WORK/run5"
assert_eq "0" "$RUN_STATUS" "a missing SAM environment does not stop the run"
assert_contains "$RUN_OUT" '"sam_status": "not_installed"' "a missing SAM environment is recorded as not_installed"

xval adjudicate --run "$WORK/run5"
assert_eq "0" "$RUN_STATUS" "adjudicate exits 0"
assert_eq "resolved_codex" "$(json_get "$(cat "$WORK/run5/adjudication.json")" 'd["adjudications"][0]["verdict"]')" \
  "both zoom answers say false, as Codex did -> resolved_codex"

new_run "$WORK/run6"
ask_with "$WORK/codex_reply.md" "$WORK/run6" 1
xval compare --run "$WORK/run6"
xval sam --run "$WORK/run6"
xval adjudicate --run "$WORK/run6"
assert_eq "unverifiable" "$(json_get "$(cat "$WORK/run6/adjudication.json")" 'd["adjudications"][0]["verdict"]')" \
  "without a zoom round or SAM, the disagreement stays unverifiable"

# ── xval.py result: the structured result file (task 4.3) ────────
mkdir -p "$WORK/project"
result_in() {   # result_in <run> — write the result file from inside $WORK/project
  RUN_STATUS=0
  RUN_OUT=$(cd "$WORK/project" && python3 "$SCRIPTS/xval.py" result --run "$1" --model gpt-test --effort high \
    --profile-source default 2>&1) || RUN_STATUS=$?
}
fm() {   # fm <file> <key> — one frontmatter value
  python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
for line in (m.group(1).splitlines() if m else []):
    k, _, v = line.partition(":")
    if k.strip() == sys.argv[2]:
        print(v.strip())
PY
}
result_in "$WORK/run5"
assert_eq "0" "$RUN_STATUS" "result exits 0"
result_file=$(ls "$WORK"/project/.codex-pro/visual-xval-*.md 2>/dev/null | tail -1)
assert_file "$result_file" "the result file is written to .codex-pro/visual-xval-<timestamp>.md"
case "$(basename "$result_file")" in
  visual-xval-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z.md) pass "the file name uses the producers' timestamp format" ;;
  *) fail "the file name uses the producers' timestamp format (got $(basename "$result_file"))" ;;
esac
assert_eq "visual-xval" "$(fm "$result_file" skill)" "frontmatter: skill"
assert_eq "gpt-test high default" "$(fm "$result_file" model) $(fm "$result_file" effort) $(fm "$result_file" profile_source)" \
  "frontmatter: model, effort, profile_source"
assert_eq "12 12 0.917" "$(fm "$result_file" n_images) $(fm "$result_file" n_claims) $(fm "$result_file" agreement_rate)" \
  "frontmatter: n_images, n_claims, agreement_rate"
assert_eq "$(shasum -a 256 "$WORK/run5/claude.json" | cut -d' ' -f1)" "$(fm "$result_file" claude_answers_sha256)" \
  "frontmatter: claude_answers_sha256 is the digest of Claude's answers"
assert_eq "false" "$(fm "$result_file" seal_broken)" "frontmatter: seal_broken"
assert_eq "not_installed" "$(fm "$result_file" sam_status)" "frontmatter: sam_status"
case "$(fm "$result_file" sealed_at)" in
  ????-??-??T??:??:??[+-]??:??) pass "frontmatter: sealed_at with an explicit offset" ;;
  *) fail "frontmatter: sealed_at with an explicit offset" ;;
esac
headings=$(grep '^## ' "$result_file" | tr '\n' '|')
assert_eq "## Agreement|## Disagreements|## SAM evidence|## Seal|## Limitations|" "$headings" \
  "the body sections come in the required order"
assert_contains "$(cat "$result_file")" "resolved_codex" "each disagreement carries its verdict"
assert_contains "$(cat "$result_file")" "does not establish that either is correct" \
  "the limitations say agreement does not establish correctness"

# Every failure class still writes the file; nothing is retried.
result_in "$WORK/run4"
fail_file=$(ls -t "$WORK"/project/.codex-pro/visual-xval-*.md | head -1)
assert_eq "oauth_invalid" "$(fm "$fail_file" error)" "a stopped run writes the result file with its error"
assert_contains "$(cat "$fail_file")" "No retry" "a failed run says it was not retried"

new_run "$WORK/run7"
printf 'package_corruption\nerror=hash_mismatch\texpected=abc\rline\n' > "$WORK/run7/runtime_error.txt"
xval ask --run "$WORK/run7" --round 1 --model m --effort e --max-time 30
sleep 1
result_in "$WORK/run7"
native_file=$(ls -t "$WORK"/project/.codex-pro/visual-xval-*.md | head -1)
assert_eq "package_corruption" "$(fm "$native_file" error)" "a native preflight failure is recorded in frontmatter"
detail_line=$(grep '^Runtime preflight detail:' "$native_file")
assert_contains "$detail_line" "error=hash_mismatch expected=abc line" "the preflight detail is sanitized (no TAB or CR)"
case "$(fm "$native_file" error)$(sed -n '/^---$/,/^---$/p' "$native_file")" in
  *hash_mismatch*) fail "the preflight detail stays out of the frontmatter" ;;
  *) pass "the preflight detail stays out of the frontmatter" ;;
esac

# A broken seal is reported, and the comparison still happened.
new_run "$WORK/run8"
ask_with "$WORK/codex_reply.md" "$WORK/run8" 1
printf ' ' >> "$WORK/run8/claude.json"
xval compare --run "$WORK/run8"
xval sam --run "$WORK/run8"
xval adjudicate --run "$WORK/run8"
sleep 1
result_in "$WORK/run8"
seal_file=$(ls -t "$WORK"/project/.codex-pro/visual-xval-*.md | head -1)
assert_eq "true" "$(fm "$seal_file" seal_broken)" "an edited answer file is reported as seal_broken: true"
assert_contains "$(cat "$seal_file")" "seal failed" "the conclusion says the seal failed"

# ── Native Codex bundle: resolver writes the runtime files in its own shell (task 4.4) ──
for native in "$REPO_ROOT/.codex/skills/codex-visual-xval/SKILL.md" "$REPO_ROOT/skills/codex-visual-xval/SKILL.md"; do
  assert_file "$native" "native visual-xval skill exists: ${native#"$REPO_ROOT"/}"
done
NATIVE="$REPO_ROOT/.codex/skills/codex-visual-xval/SKILL.md"
python3 - "$NATIVE" "$WORK/native_resolver.sh" > "$WORK/native_check.txt" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
sec = re.search(r"### Step 4\.2: Resolve bundled Codex runtime\n(.*?)\n### Step 4\.3", text, re.DOTALL)
block = re.findall(r"```bash\n(.*?)\n```", sec.group(1), re.DOTALL)[0] if sec else ""
open(sys.argv[2], "w").write(block + "\n")
def guarded(b):
    m = re.search(r'if \[ -z "\$CODEX_RUNTIME_ERROR" \]; then\n  printf \'%s\\n\' "\$CODEX_CALL" > "\$RUN/runtime\.txt"\nfi\s*$', b)
    return m is not None and b.count('"$RUN/runtime.txt"') == 1
mutated = block.replace('if [ -z "$CODEX_RUNTIME_ERROR" ]; then\n  printf', 'if true; then\n  printf')
step5 = text[text.find("## Step 5: Handle exit code"):]
checks = {
    "resolver": "BUNDLE_ROOT" in block and "bin/codex-pro-call" in block and 'CODEX_RUNTIME_ERROR=""' in block,
    "error_file_in_resolver": '> "$RUN/runtime_error.txt"' in block,
    "runtime_file_guarded": guarded(block),
    "guard_mutation_rejected": not guarded(mutated),
    "no_source_path_lookup": 'CODEX_CALL="$(command -v codex-call)"' not in text,
    "failure_rows": "runtime_unavailable" in step5 and "package_corruption" in step5,
    "error_enum": bool(re.search(r"error: <[^>]*runtime_unavailable[^>]*package_corruption[^>]*>", text)),
    "detail_contract": "Runtime preflight detail:" in text,
}
print(" ".join(f"{k}={'ok' if v else 'MISSING'}" for k, v in checks.items()))
PY
native_check=$(cat "$WORK/native_check.txt")
case "$native_check" in
  *MISSING*) fail "native visual-xval resolver contract: $native_check" ;;
  *) pass "native visual-xval resolver contract ($native_check)" ;;
esac

# Run the generated resolver against a fixture bundle whose wrapper reports an
# unsupported platform: the error lands in the run directory, no runtime path is
# written, and xval.py then stops before invoking anything.
FIX="$WORK/native_bundle"
mkdir -p "$FIX/bin" "$FIX/skills/codex-visual-xval" "$FIX/.codex-plugin"
printf '{}\n' > "$FIX/.codex-plugin/plugin.json"
printf '#!/bin/sh\necho "error=unsupported_platform os=Linux"\nexit 1\n' > "$FIX/bin/codex-pro-call"
chmod +x "$FIX/bin/codex-pro-call"
new_run "$WORK/run9"
rm -f "$WORK/run9/runtime.txt" "$WORK/run9/runtime_error.txt" "$WORK/mock.log"
( SKILL_DIR="$FIX/skills/codex-visual-xval" RUN="$WORK/run9" PATH="$WORK/stubbin:$PATH" bash "$WORK/native_resolver.sh" ) 2>/dev/null
assert_eq "runtime_unavailable" "$(head -1 "$WORK/run9/runtime_error.txt" 2>/dev/null)" \
  "an unsupported platform is recorded as runtime_unavailable by the native resolver"
assert_no_file "$WORK/run9/runtime.txt" "no runtime path is written when the resolver fails"
xval ask --run "$WORK/run9" --round 1 --model m --effort e --max-time 30
assert_contains "$RUN_OUT" '"error": "runtime_unavailable"' "xval.py stops on the native preflight error"
assert_no_file "$WORK/mock.log" "nothing is sent after a native preflight failure (no PATH fallback in a native bundle)"

# A native bundle (it has a plugin manifest) whose wrapper is gone is package corruption;
# the codex-call on PATH must not be used instead.
mv "$FIX/bin/codex-pro-call" "$FIX/bin/codex-pro-call.moved"
rm -f "$WORK/run9/runtime.txt" "$WORK/run9/runtime_error.txt" "$WORK/mock.log"
( SKILL_DIR="$FIX/skills/codex-visual-xval" RUN="$WORK/run9" PATH="$WORK/stubbin:$PATH" bash "$WORK/native_resolver.sh" ) 2>/dev/null
assert_eq "package_corruption" "$(head -1 "$WORK/run9/runtime_error.txt" 2>/dev/null)" \
  "a native bundle without its wrapper is package_corruption"
assert_no_file "$WORK/run9/runtime.txt" "a corrupt native bundle does not fall back to the codex-call on PATH"
mv "$FIX/bin/codex-pro-call.moved" "$FIX/bin/codex-pro-call"

printf '#!/bin/sh\necho "ok runtime=x sha256=y swift=z"\n' > "$FIX/bin/codex-pro-call"
rm -f "$WORK/run9/runtime.txt" "$WORK/run9/runtime_error.txt"
( SKILL_DIR="$FIX/skills/codex-visual-xval" RUN="$WORK/run9" bash "$WORK/native_resolver.sh" ) 2>/dev/null
assert_eq "$(cd "$FIX/bin" && pwd -P)/codex-pro-call" "$(cat "$WORK/run9/runtime.txt" 2>/dev/null)" \
  "a healthy bundle records its own wrapper as the runtime"
assert_eq "" "$(head -1 "$WORK/run9/runtime_error.txt" 2>/dev/null)" "a healthy bundle records no runtime error"

report_summary "visual-xval"
