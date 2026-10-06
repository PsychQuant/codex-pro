#!/usr/bin/env bash
# tests/visual-xval.sh — Layer 2: the deterministic scripts behind
# /codex-pro:codex-visual-xval (#23). Every script is exercised as a black-box
# CLI on fixtures; no network, no OAuth, no model downloads.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assert.sh"

XVAL_DIR="$REPO_ROOT/plugins/codex-pro/skills/codex-visual-xval"
SCRIPTS="$XVAL_DIR/scripts"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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
  "relations": {"tips_together": "distance_pct < 5"},
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
            "points": [{"class": "INST", "x_pct": x, "y_pct": y, "touching": None} for x, y in tips],
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
v["relations"]["tips_together"] = "the tips are together"
json.dump(v, open(f"{sys.argv[1]}/vocab_nothreshold.json", "w"))
PY
run_py compare_claims.py check-vocab "$WORK/vocab_nothreshold.json"
assert_eq "2" "$RUN_STATUS" "a relation without a numeric threshold exits 2"
assert_contains "$RUN_OUT" '"error": "target_invalid"' "a relation without a threshold is target_invalid"
assert_contains "$RUN_OUT" "tips_together" "the target_invalid detail names the relation"

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
c[1]["points"] = c[1]["points"][:1]
c[2]["points"][0] = {"class": "INST", "x_pct": 52, "y_pct": 50, "touching": None}  # f03: 12% off
c[3]["points"].reverse()                          # f04: same points, other order
json.dump(codex, open(f"{w}/codex_mixed.json", "w"))
PY
run_py compare_claims.py compare "$WORK/vocab.json" "$WORK/claude.json" "$WORK/codex_mixed.json"
kinds=$(json_get "$RUN_OUT" '" ".join(sorted("%s:%s" % (x["frame"], x["kind"]) for x in d["disagreements"]))')
assert_contains "$kinds" "f02.png:count" "a different instrument count is a count mismatch"
assert_contains "$kinds" "f03.png:position" "a tip moved beyond the threshold is a position mismatch"
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

report_summary "visual-xval"
