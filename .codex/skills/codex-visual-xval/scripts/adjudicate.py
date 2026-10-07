#!/usr/bin/env python3
"""Settle disagreements with third evidence only (#23).

  adjudicate.py VOCAB COMPARISON [--zoom ZOOM_JSON] [--sam TRACK_JSON]

Every disagreement ends as exactly one of resolved_claude, resolved_codex, unverifiable.
There is no majority vote and no model is asked to reconsider. The evidence:

  zoom        both models re-answered the cropped region (blind to each other) and agree
  sam         a valid (non-collapsed) SAM frame of the tracked class. A measurement within the
              SAM margin of a threshold is not evidence: measured SAM-vs-annotation distance error
              was 0.28% median, 0.91% max (2026-10-07).
  constraint  the vocabulary's max_count for that class

Evidence is used only for what it can prove (#23 verify round 3). A crop shows part of the frame
and SAM follows only the objects it was anchored on, so neither can show that an object is
absent:
  count     what is seen is a lower bound on the frame's count and max_count an upper bound; a
            side below the lower bound or above the upper bound is excluded, and a side wins only
            when the other is excluded and its count equals what was seen (T3, T5, L5)
  position  the evidence settles the disagreement when both disputed points belong to the same
            object, and refutes both when that object is clearly away from both points, or when
            the zoom round finds no object near either point (T3)
  relation  a smallest distance measured on some of the objects is an upper bound on the frame's
            smallest distance, so it proves `distance_pct < N` but not its opposite (T4). A zoom
            answer is used only to show `<` true: a `false` can come from a crop in which no pair
            was seen (round 4, U2). A SAM distance settles both ways only when SAM measured the tip
            of every object the two sides agree the frame holds.
SAM measures the tip of each mask, so its position and relation evidence is used only when the
vocabulary declares `track_point: tip` (round 4, U4); it follows only the objects it was anchored
on, so it never refutes both answers (U3). Evidence that refutes both answers leaves the
disagreement unverifiable whatever else is found; evidence that points to different sides does too.
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
NAME = {"claude": "Claude", "codex": "Codex"}


def side_matching(value: Any, item: dict) -> str | None:
    if value is None:
        return None
    if value == item["claude"] and value != item["codex"]:
        return "resolved_claude"
    if value == item["codex"] and value != item["claude"]:
        return "resolved_codex"
    return None


def as_points(points: list) -> list[dict]:
    return [{"x_pct": float(p[0]), "y_pct": float(p[1])} for p in points]


def present(frame: dict) -> list[dict]:
    """Objects the model itself scores as present (#23 verify I6)."""
    return [obj for obj in frame.get("objects", {}).values() if obj and obj.get("present", False)]


def sam_frame(item: dict, sam: dict | None) -> dict | None:
    frame = (sam or {}).get("frames", {}).get(item["frame"])
    return frame if frame and not frame.get("invalid") else None


def unused_zoom(reason: str) -> dict:
    """A zoom answer that settles nothing is still listed, so the result file does not read as if the
    zoom round never ran (third end-to-end run, 2026-10-07)."""
    return {"source": "zoom", "detail": f"{reason}; not used"}


# ── counts ───────────────────────────────────────────────────────────

def count_evidence(item: dict, zoom: dict, sam: dict | None, vocab: dict) -> list[dict]:
    evidence = []
    answer = zoom.get(item["id"])
    if answer and answer.get("claude") == answer.get("codex") and isinstance(answer.get("claude"), int):
        n = answer["claude"]
        evidence.append({"source": "zoom", "at_least": n,
                         "detail": f"both models counted {n} on the crop, so the frame holds at least {n}"})
    elif answer:
        evidence.append(unused_zoom(f"the two zoom answers differ ({answer.get('claude')!r} and {answer.get('codex')!r})"))
    frame = sam_frame(item, sam)
    if frame and sam.get("class") == item.get("class"):
        n = len(present(frame))
        evidence.append({"source": "sam", "at_least": n,
                         "detail": f"SAM tracked {n} objects that are present, so the frame holds at least {n}"})
    limit = vocab.get("max_count", {}).get(item.get("class"))
    if limit is not None:
        evidence.append({"source": "constraint", "at_most": limit, "detail": f"the vocabulary allows at most {limit}"})
    return evidence


def settle_count(item: dict, evidence: list[dict]) -> tuple[str, str]:
    lows = [e["at_least"] for e in evidence if "at_least" in e]
    highs = [e["at_most"] for e in evidence if "at_most" in e]
    low, high = (max(lows) if lows else None), (min(highs) if highs else None)
    if not evidence:
        return "unverifiable", "no third evidence"
    if low is not None and high is not None and low > high:
        excluded = [NAME[s] for s in ("claude", "codex") if item[s] < low or item[s] > high]
        return "unverifiable", (f"conflicting evidence: at least {low} seen, at most {high} allowed"
                                + (f"; excluded: {', '.join(excluded)}" if excluded else ""))
    excluded = [s for s in ("claude", "codex")
                if (low is not None and item[s] < low) or (high is not None and item[s] > high)]
    names = ", ".join(NAME[s] for s in excluded)
    if len(excluded) == 2:
        return "unverifiable", f"refuted both: excluded: {names}"
    if excluded:
        other = "codex" if excluded[0] == "claude" else "claude"
        if item[other] == low:   # seen exactly that many, and the other count is ruled out
            return f"resolved_{other}", f"excluded: {names}; {low} were seen"
        return "unverifiable", f"excluded: {names}; nothing confirms the other count"
    return "unverifiable", "the evidence rules out neither count"


# ── positions ────────────────────────────────────────────────────────

def instance_verdict(evidence: list, item: dict, limit: float, margin: float) -> tuple[str, list] | None:
    """Which side's disputed point is the object the evidence found there?

    The evidence points are paired with ALL of each side's key points of the class, and the
    disagreement is settled only when both disputed points pair with the same evidence point.
    Taking "the evidence point nearest either side" instead let a side that marked one object
    twice be confirmed by the other object (#23 verify B6, B9). When that object is clearly away
    from both disputed points, both are refuted (round 3, T3).
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
    # The margin covers the measurement error on both sides: the winner must be clearly inside,
    # the loser clearly outside (#23 verify round 2, S11).
    if d_claude <= limit - margin and d_codex > limit + margin:
        return "resolved_claude", point
    if d_codex <= limit - margin and d_claude > limit + margin:
        return "resolved_codex", point
    if d_claude > limit + margin and d_codex > limit + margin:
        return "refuted_both", point
    return None


def position_evidence(item: dict, points: list, limit: float, margin: float, source: str, exhaustive: bool) -> dict | None:
    """`exhaustive`: the evidence lists every object of the class in the region, as a zoom answer does."""
    settled = instance_verdict(points, item, limit, margin) if points else None
    where = "on the crop" if source == "zoom" else "by SAM"
    if settled and settled[0] == "refuted_both" and not exhaustive:
        # SAM sees only the objects it was anchored on: the object at the disputed points may simply
        # not have been tracked (#23 verify round 4, U3)
        return {"source": source, "detail": f"the nearest tracked object is at {[round(v, 2) for v in settled[1]]}, "
                                            "away from both points, but SAM sees only anchored objects; not used"}
    if settled and settled[0] == "refuted_both":
        return {"source": source, "refutes_both": True,
                "detail": f"that object is at {[round(v, 2) for v in settled[1]]} {where}, away from both points"}
    if settled:
        return {"source": source, "verdict": settled[0],
                "detail": f"that object is at {[round(v, 2) for v in settled[1]]} {where}"}
    if exhaustive:
        aspect = float(item.get("aspect", 1.0))
        near = lambda q: any(math.hypot(p[0] - q[0], (p[1] - q[1]) * aspect) <= limit + margin for p in points)
        if not near(item["claude"]) and not near(item["codex"]):
            return {"source": source, "refutes_both": True,
                    "detail": f"no object of the class is near either point {where}"}
    return None


def zoom_position(item: dict, answer: dict, limit: float) -> dict | None:
    aspect = float(item.get("aspect", 1.0))
    a, b = as_points(answer["claude"]), as_points(answer["codex"])
    pairs = pair_points(a, b, aspect)
    if len(a) != len(b) or any(math.hypot(p["x_pct"] - q["x_pct"], (p["y_pct"] - q["y_pct"]) * aspect) > limit
                               for p, q in pairs):
        return unused_zoom("the two zoom answers place the objects differently")
    found = [[(p["x_pct"] + q["x_pct"]) / 2, (p["y_pct"] + q["y_pct"]) / 2] for p, q in pairs]
    return position_evidence(item, found, limit, 0.0, "zoom", exhaustive=True)


# ── relations ────────────────────────────────────────────────────────

def relation_value(op: str, threshold: float, low: float, high: float) -> bool | None:
    """The relation's value when the frame's smallest distance lies in [low, high]; None if undecided."""
    holds = lambda d: OPS[op](d, threshold)
    if op in ("<", "<="):
        return True if holds(high) else False if not holds(low) else None
    if op in (">", ">="):
        return True if holds(low) else False if not holds(high) else None
    return True if low == high == threshold else False if (high < threshold or low > threshold) else None


def counts_agree(item: dict) -> bool:
    """Both sides give the same count for every class of the relation, so the evidence can be
    checked for having seen every object they agree on (#23 verify round 3, T4)."""
    counts = item.get("counts") or {}
    classes = set(item.get("between", []))
    return bool(classes) and all(c in counts and counts[c][0] == counts[c][1] for c in classes)


def zoom_relation(item: dict, answer: dict) -> dict | None:
    """A zoom answer shows `distance_pct < N` (or `<=`) true, because that answer needs a pair of key
    points that are close; any other answer can come from a crop in which no pair was seen, and the
    answer does not say how many points the model saw (#23 verify round 4, U2)."""
    parsed = DEFINITION.match(item.get("definition", ""))
    value = answer.get("claude")
    if not parsed or not isinstance(value, bool):
        return None
    if value != answer.get("codex"):
        return unused_zoom(f"the two zoom answers differ ({value!r} and {answer.get('codex')!r})")
    if not (parsed.group(2) in ("<", "<=") and value):
        return unused_zoom(f"both models answered {value!r} on the crop; only a pair seen close together shows "
                           "anything for the frame, and this answer can come from a crop in which no pair was seen")
    verdict = side_matching(True, item)
    return verdict and {"source": "zoom", "verdict": verdict,
                        "detail": "both models answered True on the crop: a pair of key points is that close"}


def sam_relation(item: dict, frame: dict, tracked: str, margin: float) -> dict | None:
    parsed = DEFINITION.match(item.get("definition", ""))
    measured = frame.get("distance_pct")
    objects = present(frame)
    if (not parsed or parsed.group(1) != "distance_pct" or measured is None or len(objects) < 2
            or item.get("between") != [tracked, tracked]):
        return None
    op, threshold = parsed.group(2), float(parsed.group(3))
    if abs(measured - threshold) <= margin:   # strictly farther than the margin, both ways (round 4, M2)
        return {"source": "sam", "detail": f"distance_pct={measured} is within {margin} of the threshold {threshold}; not used"}
    # The distance is measured between tips; an object at the edge of the view has none (round 4, U2).
    tipped = [o for o in objects if o.get("tip_pct")]
    complete = counts_agree(item) and item["counts"][tracked][0] == len(tipped)
    low = measured - margin if complete else 0.0
    verdict = side_matching(relation_value(op, threshold, low, measured + margin), item)
    if not verdict:
        return {"source": "sam", "detail": f"distance_pct={measured} between the tips of {len(tipped)} of "
                                           f"{len(objects)} tracked objects; other objects could be closer, so it "
                                           "settles neither answer; not used"}
    note = "" if complete else "; other objects could only be closer"
    return {"source": "sam", "verdict": verdict,
            "detail": f"distance_pct={measured} between the tips of {len(tipped)} tracked objects "
                      f"(threshold {threshold}, margin {margin}{note})"}


# ── adjudication ─────────────────────────────────────────────────────

def other_evidence(item: dict, zoom: dict, sam: dict | None, vocab: dict, margin: float) -> list[dict]:
    """Position and relation evidence: each piece confirms a side or refutes both."""
    evidence, answer = [], zoom.get(item["id"])
    limit = float(item.get("threshold_pct", vocab.get("position_threshold_pct", 5)))
    if answer and item["kind"] == "position":
        evidence.append(zoom_position(item, answer, limit))
    elif answer and item["kind"] == "relation":
        evidence.append(zoom_relation(item, answer))
    frame, tracked = sam_frame(item, sam), (sam or {}).get("class")
    if frame and vocab.get("track_point") != "tip":   # SAM's point is the mask tip (round 4, U4)
        frame = None
    if frame and item["kind"] == "position" and item.get("class") == tracked:
        tips = [obj["tip_pct"] for obj in present(frame) if obj.get("tip_pct")]
        evidence.append(position_evidence(item, tips, limit, margin, "sam", exhaustive=False))
    elif frame and item["kind"] == "relation":
        evidence.append(sam_relation(item, frame, tracked, margin))
    return [e for e in evidence if e]


def settle(evidence: list[dict]) -> tuple[str, str]:
    refuting = [e for e in evidence if e.get("refutes_both")]
    confirming = {e["verdict"] for e in evidence if "verdict" in e}
    if refuting:   # evidence that refutes both answers: nothing else may award either (R3)
        source = "zoom round" if refuting[0]["source"] == "zoom" else "SAM"
        return "unverifiable", f"the {source} refuted both: {refuting[0]['detail']}"
    if len(confirming) > 1:
        return "unverifiable", "conflicting evidence"
    if confirming:
        return confirming.pop(), ""
    return "unverifiable", "the evidence settles neither answer" if evidence else "no third evidence"


def adjudicate(vocab: dict, comparison: dict, zoom: dict, sam: dict | None) -> dict:
    margin = float(vocab.get("sam_margin_pct", DEFAULT_MARGIN_PCT))
    results = []
    for item in comparison.get("disagreements", []):
        if item["kind"] == "count":
            evidence = count_evidence(item, zoom, sam, vocab)
            verdict, note = settle_count(item, evidence)
        else:
            evidence = other_evidence(item, zoom, sam, vocab, margin)
            verdict, note = settle(evidence)
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
