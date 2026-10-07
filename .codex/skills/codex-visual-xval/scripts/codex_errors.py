#!/usr/bin/env python3
"""A failed codex-call for /codex-pro:codex-visual-xval (#23): its error class, and the check made
before calling it. Pure functions; scripts/xval.py records the result.

Every failure of a call counts as sent (#23 verify round 5, V1). No wording can show that nothing
left the machine: codex-call prints the backend's error events as they come, and prints every
failure before a response as `HTTP 0`. Two rounds of matching codex-call's own messages each left
a gap (round 3, T1; round 4, U1), and the narrowed list also counted a missing login as sent
(round 5, V2). What commonly fails before sending is therefore checked here, before the call.
"""
import json
import os
import re


def classify(stderr: str, status: int) -> tuple[str, str]:
    """(error class, detail). codex-call reports a failure as `error: <message>`, and the message can
    run over several lines (an HTTP body). Judge its first line, and match whole markers ("HTTP 429")
    rather than digits: an image path inside a run directory named after its timestamp can contain
    "429" or "401" (#23 verify I1). The class names the likely cause; the call counts as sent."""
    first = re.search(r"^error: (.*)$", stderr, re.MULTILINE)
    message = (first.group(1) if first else stderr).strip()
    low = message.lower()
    detail = message[-500:]
    if message.startswith("--image "):
        return "target_invalid", detail
    if re.search(r"\bhttp 429\b", low) or "rate limit" in low or "usage limit" in low:
        return "rate_limit", detail
    if (re.search(r"\bhttp 40[13]\b", low) or "unauthorized" in low or "refresh_token" in low
            or "invalid_grant" in low or "token expired" in low or message.startswith("auth.json")):
        return "oauth_invalid", detail
    if "timed out" in low or "timeout" in low:
        return "timeout", detail
    if re.match(r"http 0\b", low):
        return "backend_error", f"{detail} (no response arrived; codex-call does not say whether the request was sent)"
    return "backend_error", detail if re.search(r"\bhttp \d{3}\b", low) else f"codex-call exit {status}: {detail}"


def login_problem() -> str | None:
    """Whether Codex is logged in: the token store codex-call reads exists and holds its tokens. Only
    the presence of the tokens is checked; nothing in the file is reported."""
    path = os.path.join(os.path.expanduser("~"), ".codex", "auth.json")
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return "Codex is not logged in (there is no ~/.codex/auth.json)"
    except (OSError, ValueError):
        return "the Codex token store ~/.codex/auth.json cannot be read"
    tokens = data.get("tokens") if isinstance(data, dict) else None
    if not (isinstance(tokens, dict)
            and all(isinstance(tokens.get(k), str) and tokens[k] for k in ("access_token", "refresh_token"))):
        return "the Codex token store ~/.codex/auth.json holds no tokens"
    return None
