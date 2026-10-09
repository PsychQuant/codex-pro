#!/usr/bin/env python3
"""SAM 2.1 evidence for /codex-pro:codex-visual-xval (#23).

  check-collapse MASKS_JSON
      MASKS_JSON = {frame: {object_id: 2-D 0/1 mask}}. Prints the frames whose masks
      collapsed (any two objects with intersection-over-union > 0.5) and the largest
      IoU per frame. Collapsed frames are not evidence.
  anchors COMPARISON CLAUDE CODEX --class CLASS
      One anchor per run of consecutive agreeing frames (the first frame of the run),
      with the agreed positions of CLASS (midpoints of the paired points) as prompts.
  tip-check CASE_JSON
      CASE_JSON = {"image_gray": 2-D grey levels, "mask": 2-D 0/1}; prints the tip and entry.
  track --frames FRAMES_JSON --anchors ANCHORS_JSON --out TRACK_JSON
      Runs facebook/sam2.1-hiera-large. Needs the environment from sam_env.sh; without
      it, prints {"sam_status": "not_installed"} and exits 4 before reading anything.

Tracking re-anchors at every run of agreeing frames: a single anchor propagated over
a long clip was seen to collapse both objects onto one instrument (332 of 909 frames)
and to swap identities after both left the view.
"""
import json
import math
import os
import sys
from typing import Any

sys.dont_write_bytecode = True   # no __pycache__ next to the bundled scripts
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

COLLAPSE_IOU = 0.5
MODEL_ID = "facebook/sam2.1-hiera-large"
MODEL_REVISION = "665f8e2ad61cf5f53d65644ff27c8ee525124610"   # the revision tracking was verified with (2026-10-07)
MIN_AREA_PX = 50


def mask_iou(a: list[list[int]], b: list[list[int]]) -> float:
    inter = union = 0
    for row_a, row_b in zip(a, b):
        for x, y in zip(row_a, row_b):
            inter += 1 if (x and y) else 0
            union += 1 if (x or y) else 0
    return inter / union if union else 0.0


def max_pair_iou(masks: dict[str, Any]) -> float:
    ids = sorted(masks)
    best = 0.0
    for i, first in enumerate(ids):
        for second in ids[i + 1:]:
            best = max(best, mask_iou(masks[first], masks[second]))
    return best


def check_collapse(masks_by_frame: dict[str, dict[str, Any]]) -> dict:
    ious = {frame: round(max_pair_iou(masks), 3) for frame, masks in masks_by_frame.items()}
    return {"invalid_frames": sorted(f for f, iou in ious.items() if iou > COLLAPSE_IOU), "max_iou": ious}


def agreeing_runs(order: list[str], agree: dict[str, bool]) -> list[list[str]]:
    runs, current = [], []
    for frame in order:
        if agree.get(frame):
            current.append(frame)
        elif current:
            runs.append(current)
            current = []
    if current:
        runs.append(current)
    return runs


def anchors(comparison: dict, claude: dict, codex: dict, cls: str,
            order: list | None = None, aspects: dict | None = None) -> dict:
    """The time order is the order the images were given (`order`); the order of Claude's answer
    list is not evidence of time (#23 verify I7)."""
    from compare_claims import claims_list, pair_points
    mine = {c["frame"]: c for c in claims_list(claude)}
    theirs = {c["frame"]: c for c in claims_list(codex)}
    order = list(order) if order else sorted(mine)
    aspects = aspects or {}
    agree = {frame: info["agree"] for frame, info in comparison["frames"].items()}
    result = []
    for run in agreeing_runs(order, agree):
        frame = run[0]
        a = [p for p in mine[frame].get("points", []) if p["class"] == cls]
        b = [p for p in theirs[frame].get("points", []) if p["class"] == cls]
        points = [[round((p["x_pct"] + q["x_pct"]) / 2, 2), round((p["y_pct"] + q["y_pct"]) / 2, 2)]
                  for p, q in pair_points(a, b, aspects.get(frame, 1.0))]
        if points:
            result.append({"frame": frame, "run": run, "points": points})
    return {"class": cls, "order": order, "anchors": result}


# Measured on 960-px-wide laparoscopic frames (#23): an opening of radius 4 removes the
# suture threads SAM tends to include in an instrument mask (tip within 2% of the annotated
# tip on 23/24 masks, against 17/24 with radius 2) and keeps the 15-25 px shafts. Both
# lengths scale with the frame width.
THREAD_RADIUS_AT_960 = 4
EDGE_TIP_FRACTION = 0.005   # a "tip" this close to the edge of the view is not an inner end
DARK_LEVEL = 16             # grey level at or below which a pixel is outside the camera's view


def _shifted(mask, dy: int, dx: int):
    import numpy as np
    out = np.zeros_like(mask)
    h, w = mask.shape
    ys, yd = (slice(dy, h), slice(0, h - dy)) if dy >= 0 else (slice(0, h + dy), slice(-dy, h))
    xs, xd = (slice(dx, w), slice(0, w - dx)) if dx >= 0 else (slice(0, w + dx), slice(-dx, w))
    out[yd, xd] = mask[ys, xs]
    return out


def erode(mask, r: int):
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out &= _shifted(mask, dy, dx)
    return out


def dilate(mask, r: int):
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= _shifted(mask, dy, dx)
    return out


def outside_distance(inside):
    """Approximate (Chebyshev) distance of every pixel to the nearest pixel outside the view."""
    import numpy as np
    step = 4 if inside.size > 200_000 else 1
    small = inside[::step, ::step].copy()
    dist = np.zeros(small.shape, dtype=np.int32)
    for _ in range(max(small.shape)):
        if not small.any():
            break
        dist += small
        small = erode(small, 1)
    return np.repeat(np.repeat(dist, step, 0), step, 1)[: inside.shape[0], : inside.shape[1]] * step


def view_region(gray):
    """The camera's view as a filled region: per row and per column, everything between the
    outermost bright pixels. A dark object inside the view (a black instrument shaft) stays
    inside; only what lies beyond the edge of the view is outside."""
    import numpy as np
    bright = gray > DARK_LEVEL
    rows = np.zeros_like(bright)
    cols = np.zeros_like(bright)
    for y in np.nonzero(bright.any(axis=1))[0]:
        xs = np.nonzero(bright[y])[0]
        rows[y, xs[0]: xs[-1] + 1] = True
    for x in np.nonzero(bright.any(axis=0))[0]:
        ys = np.nonzero(bright[:, x])[0]
        cols[ys[0]: ys[-1] + 1, x] = True
    return rows & cols


def tip_and_entry(mask, gray):
    """Entry = mask pixel closest to the edge of the view; tip = mask pixel farthest from it.

    Thin structures stuck to the mask (a thread held by the instrument) are removed first
    by an opening, so the tip is not carried along the thread.
    """
    import numpy as np
    width = mask.shape[1]
    radius = max(2, round(THREAD_RADIUS_AT_960 * width / 960))
    opened = dilate(erode(mask, radius), radius) & mask
    body = opened if opened.sum() >= MIN_AREA_PX // 2 else mask
    ys, xs = np.nonzero(body)
    if xs.size == 0:
        return None, None
    depth = outside_distance(view_region(gray))[ys, xs]
    pts = np.stack([xs, ys], 1).astype(float)
    nearest_edge = depth <= depth.min() + 1          # average the ties instead of taking the first in raster order
    entry = pts[nearest_edge].mean(0)
    k = int(np.argmax(np.linalg.norm(pts - entry, axis=1)))
    if depth[k] <= max(4, EDGE_TIP_FRACTION * width):
        return None, entry                           # no inner end: the object only touches the edge
    return pts[k], entry


def mask_geometry(mask, gray) -> dict | None:
    import numpy as np
    ys, xs = np.nonzero(mask)
    if xs.size < MIN_AREA_PX:
        return None
    height, width = mask.shape
    tip, entry = tip_and_entry(mask, gray)
    pct = lambda p: None if p is None else [round(float(p[0]) / width * 100, 2), round(float(p[1]) / height * 100, 2)]
    centre = np.stack([xs, ys], 1).mean(0)
    return {"area": int(xs.size), "centroid_pct": pct(centre), "tip_pct": pct(tip), "entry_pct": pct(entry)}


def track(frames_path: str, anchors_path: str, out_path: str) -> None:
    try:
        import numpy as np
        import torch
        from PIL import Image
        from transformers import Sam2VideoModel, Sam2VideoProcessor
    except ImportError as exc:
        print(json.dumps({"sam_status": "not_installed", "detail": str(exc)}))
        sys.exit(4)
    with open(frames_path, encoding="utf-8") as fh:
        frame_paths = json.load(fh)
    with open(anchors_path, encoding="utf-8") as fh:
        plan = json.load(fh)
    by_name = {os.path.basename(p): p for p in frame_paths}
    order = [name for name in plan["order"] if name in by_name]
    images = {name: np.array(Image.open(by_name[name]).convert("RGB")) for name in order}
    height, width = next(iter(images.values())).shape[:2]
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    # Only files already on disk: installing is a separate step the user consented to.
    model = Sam2VideoModel.from_pretrained(MODEL_ID, revision=MODEL_REVISION, local_files_only=True).to(device)
    processor = Sam2VideoProcessor.from_pretrained(MODEL_ID, revision=MODEL_REVISION, local_files_only=True)

    starts = [order.index(a["frame"]) for a in plan["anchors"]]
    results: dict[str, dict] = {}
    for n, anchor in enumerate(plan["anchors"]):
        lo = 0 if n == 0 else starts[n]
        hi = starts[n + 1] if n + 1 < len(starts) else len(order)
        segment = order[lo:hi]
        local = order.index(anchor["frame"]) - lo
        session = processor.init_video_session(video=[images[f] for f in segment], inference_device=device,
                                               video_storage_device="cpu")
        ids = list(range(1, len(anchor["points"]) + 1))
        points = [[[[x / 100 * width, y / 100 * height]] for x, y in anchor["points"]]]
        # Pass a copy: the processor consumes the obj_ids list it is given (seen emptied in
        # transformers 5.19), which silently left every frame with no objects.
        processor.add_inputs_to_inference_session(inference_session=session, frame_idx=local, obj_ids=list(ids),
                                                  input_points=points, input_labels=[[[1] for _ in ids]])
        model(inference_session=session, frame_idx=local)
        masks: dict[int, Any] = {}
        scores: dict[int, list] = {}
        for reverse in (False, True):
            for out in model.propagate_in_video_iterator(session, start_frame_idx=local, reverse=reverse):
                m = processor.post_process_masks([out.pred_masks], original_sizes=[[height, width]], binarize=True)[0]
                masks[out.frame_idx] = m[:, 0].cpu().numpy().astype(bool)
                # The model's own judgement of whether each object is in the frame. A mask alone
                # can drift onto a thread or the pad after the instrument has left (#23 verify I6).
                scores[out.frame_idx] = [float(v) for v in out.object_score_logits.flatten().cpu().tolist()]
        for idx, per_object in masks.items():
            name = segment[idx]
            iou = 0.0
            for i in range(len(ids)):
                for j in range(i + 1, len(ids)):
                    inter = np.logical_and(per_object[i], per_object[j]).sum()
                    union = np.logical_or(per_object[i], per_object[j]).sum()
                    iou = max(iou, float(inter / union) if union else 0.0)
            gray = images[name].mean(axis=2)
            objects = {}
            for k in ids:
                geometry = mask_geometry(per_object[k - 1], gray)
                score = scores[idx][k - 1] if k - 1 < len(scores.get(idx, [])) else None
                if geometry is not None:
                    geometry.update(present=score is not None and score > 0, object_score=score)
                objects[str(k)] = geometry
            tips = [o["tip_pct"] for o in objects.values() if o and o["present"] and o["tip_pct"]]
            # distance_pct: the smallest distance between two different tracked objects' tips
            pairs = [(a, b) for i, a in enumerate(tips) for b in tips[i + 1:]]
            distance = round(min(math.hypot(a[0] - b[0], (a[1] - b[1]) * height / width) for a, b in pairs), 2) if pairs else None
            results[name] = {"anchor": anchor["frame"], "invalid": iou > COLLAPSE_IOU, "max_iou": round(iou, 3),
                             "objects": objects, "distance_pct": distance}
    # Written to a new temporary file and moved over the name, as xval writes its records, so a link at the
    # name is replaced and never written through (#23 verify round 12, H1). This runs in SAM's own Python,
    # which does not load xval's modules.
    import tempfile
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(out_path)), prefix=".xval-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"sam_status": "ok", "model": MODEL_ID, "revision": MODEL_REVISION, "class": plan["class"],
                       "device": device, "frames": results,
                       "invalid_frames": sorted(f for f, r in results.items() if r["invalid"])}, fh, indent=1)
        os.chmod(tmp, 0o644)   # as xval writes its records; the umask is not touched in a threaded process (round 14)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.lexists(tmp):
            os.remove(tmp)
        raise
    print(json.dumps({"sam_status": "ok", "frames": len(results)}))


def option(argv: list[str], name: str) -> str | None:
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None


def main(argv: list[str]) -> None:
    if len(argv) == 2 and argv[0] == "check-collapse":
        with open(argv[1], encoding="utf-8") as fh:
            print(json.dumps(check_collapse(json.load(fh))))
        return
    if len(argv) >= 6 and argv[0] == "anchors" and option(argv, "--class"):
        loaded = []
        for path in argv[1:4]:
            with open(path, encoding="utf-8") as fh:
                loaded.append(json.load(fh))
        order = None
        if option(argv, "--order"):
            with open(option(argv, "--order"), encoding="utf-8") as fh:
                order = json.load(fh)
        print(json.dumps(anchors(*loaded, option(argv, "--class"), order=order), ensure_ascii=False))
        return
    if len(argv) == 2 and argv[0] == "tip-check":
        import numpy as np
        with open(argv[1], encoding="utf-8") as fh:
            case = json.load(fh)
        tip, entry = tip_and_entry(np.array(case["mask"], dtype=bool), np.array(case["image_gray"], dtype=float))
        print(json.dumps({"tip_px": None if tip is None else [float(v) for v in tip],
                          "entry_px": None if entry is None else [float(v) for v in entry]}))
        return
    if argv[:1] == ["track"] and all(option(argv, k) for k in ("--frames", "--anchors", "--out")):
        track(option(argv, "--frames"), option(argv, "--anchors"), option(argv, "--out"))
        return
    print(__doc__, file=sys.stderr)
    sys.exit(64)


if __name__ == "__main__":
    main(sys.argv[1:])
