#!/usr/bin/env python3
"""Settle disagreements with third evidence only (#23).

  adjudicate.py VOCAB COMPARISON [--zoom ZOOM_JSON] [--sam TRACK_JSON]

Every disagreement ends as exactly one of resolved_claude, resolved_codex, unverifiable.
There is no majority vote and no model is asked to reconsider. Three kinds of evidence:

  zoom        both models re-answered the cropped region (blind to each other) and agree;
              the side whose original answer matches that shared answer wins
  sam         a valid (non-collapsed) SAM frame measures the disputed quantity. A
              measurement within the SAM margin of the threshold is not evidence: measured
              SAM-vs-annotation distance error was 0.28% median, 0.91% max (2026-10-07).
              SAM only follows objects present at its anchor, so it can confirm that
              objects are there but cannot show that an extra one is absent.
  constraint  a count above the vocabulary's max_count for that class

If the evidence that exists points to different sides, the disagreement is unverifiable.
"""
import json
import math
import re
import sys
from typing import Any

DEFAULT_MARGIN_PCT = 1.0
DEFINITION = re.compile(r"^\s*([a-z_]+)\s*(<=|>=|<|>|==)\s*(-?\d+(?:\.\d+)?)\s*$")
OPS = {"<": lambda a, b: a < b, "<=": lambda a, b: a <= b, ">": lambda a, b: a > b,
       ">=": lambda a, b: a >= b, "==": lambda a, b: a == b}


def side_matching(value: Any, item: dict) -> str | None:
    if value == item["claude"] and value != item["codex"]:
        return "resolved_claude"
    if value == item["codex"] and value != item["claude"]:
        return "resolved_codex"
    return None


def from_zoom(item: dict, zoom: dict) -> dict | None:
    answer = zoom.get(item["id"])
    if not answer or answer.get("claude") != answer.get("codex"):
        return None
    verdict = side_matching(answer["claude"], item)
    return verdict and {"source": "zoom", "verdict": verdict, "detail": f"both models answered {answer['claude']!r} on the crop"}


def from_constraint(item: dict, vocab: dict) -> dict | None:
    if item["kind"] != "count":
        return None
    limit = vocab.get("max_count", {}).get(item["class"])
    if limit is None:
        return None
    over = {side: item[side] > limit for side in ("claude", "codex")}
    if over["claude"] and not over["codex"]:
        return {"source": "constraint", "verdict": "resolved_codex", "detail": f"Claude's count {item['claude']} exceeds max {limit}"}
    if over["codex"] and not over["claude"]:
        return {"source": "constraint", "verdict": "resolved_claude", "detail": f"Codex's count {item['codex']} exceeds max {limit}"}
    return None


def from_sam(item: dict, sam: dict, vocab: dict, margin: float) -> dict | None:
    frame = sam.get("frames", {}).get(item["frame"])
    if not frame or frame.get("invalid"):
        return None
    if item["kind"] == "relation":
        parsed = DEFINITION.match(item.get("definition", ""))
        measured = frame.get("distance_pct")
        if not parsed or parsed.group(1) != "distance_pct" or measured is None:
            return None
        op, threshold = parsed.group(2), float(parsed.group(3))
        if abs(measured - threshold) <= margin:
            return None
        verdict = side_matching(OPS[op](measured, threshold), item)
        return verdict and {"source": "sam", "verdict": verdict,
                            "detail": f"distance_pct={measured} (threshold {threshold}, margin {margin})"}
    if item["kind"] == "count":
        seen = sum(1 for obj in frame.get("objects", {}).values() if obj)
        higher = max(item["claude"], item["codex"])
        if seen == higher:
            verdict = side_matching(higher, item)
            return verdict and {"source": "sam", "verdict": verdict, "detail": f"SAM tracked {seen} objects"}
        return None
    if item["kind"] == "position":
        tips = [obj["tip_pct"] for obj in frame.get("objects", {}).values() if obj and obj.get("tip_pct")]
        threshold = float(item.get("threshold_pct", vocab.get("position_threshold_pct", 5)))
        if not tips:
            return None
        aspect = float(item.get("aspect", 1.0))   # same distance definition as compare_claims.py
        gap = lambda p, q: math.hypot(p[0] - q[0], (p[1] - q[1]) * aspect)
        tip = min(tips, key=lambda t: min(gap(t, item["claude"]), gap(t, item["codex"])))
        d_claude, d_codex = gap(tip, item["claude"]), gap(tip, item["codex"])
        if d_claude <= threshold and d_codex > threshold + margin:
            verdict = "resolved_claude"
        elif d_codex <= threshold and d_claude > threshold + margin:
            verdict = "resolved_codex"
        else:
            return None
        return {"source": "sam", "verdict": verdict, "detail": f"SAM tip {tip}: {d_claude:.1f} from Claude, {d_codex:.1f} from Codex"}
    return None


def adjudicate(vocab: dict, comparison: dict, zoom: dict, sam: dict | None) -> dict:
    margin = float(vocab.get("sam_margin_pct", DEFAULT_MARGIN_PCT))
    results = []
    for item in comparison.get("disagreements", []):
        evidence = [e for e in (from_zoom(item, zoom), from_constraint(item, vocab),
                                from_sam(item, sam, vocab, margin) if sam else None) if e]
        verdicts = {e["verdict"] for e in evidence}
        verdict = verdicts.pop() if len(verdicts) == 1 else "unverifiable"
        note = "conflicting evidence" if len({e["verdict"] for e in evidence}) > 1 else (
            "no third evidence" if not evidence else "")
        results.append({"id": item["id"], "frame": item["frame"], "kind": item["kind"],
                        "verdict": verdict, "evidence": evidence, "note": note})
    counts = {v: sum(1 for r in results if r["verdict"] == v) for v in ("resolved_claude", "resolved_codex", "unverifiable")}
    return {"sam_margin_pct": margin, "adjudications": results, "counts": counts}


def option(argv: list[str], name: str) -> str | None:
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None


def load(path: str | None, default: Any) -> Any:
    if not path:
        return default
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def main(argv: list[str]) -> None:
    if len(argv) < 2 or argv[0].startswith("--"):
        print(__doc__, file=sys.stderr)
        sys.exit(64)
    sam = load(option(argv, "--sam"), None)
    if sam is not None and sam.get("sam_status") != "ok":
        sam = None
    print(json.dumps(adjudicate(load(argv[0], {}), load(argv[1], {}), load(option(argv, "--zoom"), {}), sam),
                     ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
