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
import os
import re
import sys
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_claims import pair_points  # noqa: E402

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


def as_points(points: list) -> list[dict]:
    return [{"x_pct": float(p[0]), "y_pct": float(p[1])} for p in points]


def instance_verdict(evidence: list, item: dict, limit: float, margin: float) -> tuple[str, list] | None:
    """Which side's disputed point is the object the evidence found there?

    The evidence points are paired with ALL of each side's key points of the class, and the
    disagreement is settled only when both disputed points pair with the same evidence point.
    Taking "the evidence point nearest either side" instead let a side that marked one object
    twice be confirmed by the other object (#23 verify B6, B9).
    """
    aspect = float(item.get("aspect", 1.0))
    gap = lambda p, q: math.hypot(p[0] - q[0], (p[1] - q[1]) * aspect)
    found = as_points(evidence)
    def partner(points: list, disputed: list) -> int | None:
        for e, p in pair_points(found, as_points(points), aspect):
            if [p["x_pct"], p["y_pct"]] == [float(v) for v in disputed]:
                return found.index(e)
        return None
    mine = partner(item.get("claude_points") or [item["claude"]], item["claude"])
    theirs = partner(item.get("codex_points") or [item["codex"]], item["codex"])
    if mine is None or mine != theirs:
        return None
    point = [found[mine]["x_pct"], found[mine]["y_pct"]]
    d_claude, d_codex = gap(point, item["claude"]), gap(point, item["codex"])
    if d_claude <= limit and d_codex > limit + margin:
        return "resolved_claude", point
    if d_codex <= limit and d_claude > limit + margin:
        return "resolved_codex", point
    return None


def from_zoom(item: dict, zoom: dict, vocab: dict | None = None) -> dict | None:
    answer = zoom.get(item["id"])
    if not answer:
        return None
    if item["kind"] == "position":   # both sides list every key point of the class in the crop
        aspect = float(item.get("aspect", 1.0))
        limit = float(item.get("threshold_pct", (vocab or {}).get("position_threshold_pct", 5)))
        a, b = as_points(answer["claude"]), as_points(answer["codex"])
        pairs = pair_points(a, b, aspect)
        if len(a) != len(b) or any(math.hypot(p["x_pct"] - q["x_pct"], (p["y_pct"] - q["y_pct"]) * aspect) > limit
                                   for p, q in pairs):
            return None   # the two zoom answers do not agree with each other
        found = [[(p["x_pct"] + q["x_pct"]) / 2, (p["y_pct"] + q["y_pct"]) / 2] for p, q in pairs]
        settled = instance_verdict(found, item, limit, 0.0)
        return settled and {"source": "zoom", "verdict": settled[0],
                            "detail": f"both models placed that object at {[round(v, 2) for v in settled[1]]} on the crop"}
    if answer.get("claude") != answer.get("codex"):
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
        return {"source": "constraint", "verdict": "resolved_codex",
                "detail": f"Claude's count {item['claude']} exceeds max {limit}: this excludes Claude's count; "
                          f"it does not confirm Codex's {item['codex']}"}
    if over["codex"] and not over["claude"]:
        return {"source": "constraint", "verdict": "resolved_claude",
                "detail": f"Codex's count {item['codex']} exceeds max {limit}: this excludes Codex's count; "
                          f"it does not confirm Claude's {item['claude']}"}
    return None


def from_sam(item: dict, sam: dict, vocab: dict, margin: float) -> dict | None:
    """SAM follows one class. Its measurements are evidence only about that class, and only
    objects the model itself scores as present count (#23 verify B5, I6)."""
    frame = sam.get("frames", {}).get(item["frame"])
    if not frame or frame.get("invalid"):
        return None
    tracked = sam.get("class")
    present = [obj for obj in frame.get("objects", {}).values() if obj and obj.get("present", False)]
    if item["kind"] == "relation":
        parsed = DEFINITION.match(item.get("definition", ""))
        measured = frame.get("distance_pct")
        if (not parsed or parsed.group(1) != "distance_pct" or measured is None or len(present) != 2
                or item.get("between") != [tracked, tracked]):
            return None
        op, threshold = parsed.group(2), float(parsed.group(3))
        if abs(measured - threshold) <= margin:
            return None
        verdict = side_matching(OPS[op](measured, threshold), item)
        return verdict and {"source": "sam", "verdict": verdict,
                            "detail": f"distance_pct={measured} (threshold {threshold}, margin {margin})"}
    if item.get("class") != tracked:
        return None
    if item["kind"] == "count":
        seen = len(present)
        higher = max(item["claude"], item["codex"])
        if seen == higher:
            verdict = side_matching(higher, item)
            return verdict and {"source": "sam", "verdict": verdict, "detail": f"SAM tracked {seen} objects"}
        return None
    if item["kind"] == "position":
        tips = [obj["tip_pct"] for obj in present if obj.get("tip_pct")]
        threshold = float(item.get("threshold_pct", vocab.get("position_threshold_pct", 5)))
        settled = instance_verdict(tips, item, threshold, margin) if tips else None
        return settled and {"source": "sam", "verdict": settled[0],
                            "detail": f"the SAM tip of that object is at {settled[1]}"}
    return None


def refuted_both(item: dict, zoom: dict) -> str:
    """Both models gave the same zoom answer, and it is neither side's original answer."""
    answer = zoom.get(item["id"])
    if not answer or item["kind"] == "position" or answer.get("claude") != answer.get("codex"):
        return ""
    if answer["claude"] in (item["claude"], item["codex"]):
        return ""
    return f"the zoom round refuted both: both models answered {answer['claude']!r} on the crop"


def adjudicate(vocab: dict, comparison: dict, zoom: dict, sam: dict | None) -> dict:
    margin = float(vocab.get("sam_margin_pct", DEFAULT_MARGIN_PCT))
    results = []
    for item in comparison.get("disagreements", []):
        evidence = [e for e in (from_zoom(item, zoom, vocab), from_constraint(item, vocab),
                                from_sam(item, sam, vocab, margin) if sam else None) if e]
        verdicts = {e["verdict"] for e in evidence}
        verdict = verdicts.pop() if len(verdicts) == 1 else "unverifiable"
        note = "conflicting evidence" if len({e["verdict"] for e in evidence}) > 1 else (
            refuted_both(item, zoom) or ("no third evidence" if not evidence else ""))
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
