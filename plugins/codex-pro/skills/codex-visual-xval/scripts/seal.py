#!/usr/bin/env python3
"""Seal Claude's answers before Codex is asked, and verify the seal before comparing (#23).

  seal ANSWERS SEAL_JSON     record the SHA-256 of ANSWERS and the time, write SEAL_JSON
  verify ANSWERS SEAL_JSON   recompute the digest; print {"seal_broken": ...} and exit 0

A broken seal does not stop the run: the comparison still happens and the result file
says the seal failed. That is the point of the seal — a reader can check afterwards that
Claude's answers were fixed before Codex's answers existed.
"""
import datetime
import hashlib
import json
import os
import sys


def digest(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def seal(answers: str, seal_path: str) -> None:
    record = {
        "path": answers,
        "sha256": digest(answers),
        "sealed_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "sealed_epoch": datetime.datetime.now().timestamp(),   # orders the seal against the request
    }
    # through xval's one write entry: a link at the name is replaced, never written through (#23 verify round 12,
    # H1). Imported here, not at the top: run_files imports this module.
    from run_files import write_bytes
    write_bytes(seal_path, json.dumps(record, ensure_ascii=True, indent=1).encode("utf-8"))
    print(json.dumps(record, ensure_ascii=False))


def verify(answers: str, seal_path: str) -> None:
    try:
        with open(seal_path, encoding="utf-8") as fh:
            record = json.load(fh)
        sealed = record.get("sha256")
    except (OSError, ValueError):
        record, sealed = {}, None
    try:
        now = digest(answers)
    except OSError:
        now = None
    print(json.dumps({
        "sha256_sealed": sealed,
        "sha256_now": now,
        "sealed_at": record.get("sealed_at"),
        "seal_broken": sealed is None or now is None or sealed != now,
    }))


def main(argv: list[str]) -> None:
    if len(argv) == 3 and argv[0] == "seal":
        seal(argv[1], argv[2])
    elif len(argv) == 3 and argv[0] == "verify":
        verify(argv[1], argv[2])
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(64)


if __name__ == "__main__":
    main(sys.argv[1:])
