#!/usr/bin/env python3
"""How a failed codex-call is reported by /codex-pro:codex-visual-xval (#23): its error class, and
whether the request may have left the machine. Pure functions; scripts/xval.py records the result.
"""
import re


# Failures codex-call reports before any network request: the only ones that leave a round unsent.
# A closed list, matched on codex-call's own wording; no other failure may be inferred to be unsent
# from its wording, because codex-call prints `HTTP 0: (no body)` for every failure before a response
# arrives, an upload that finished before the connection dropped included (#23 verify round 3, T1).
# A precise answer needs codex-call to report what it sent: PsychQuant/parallel-ai-agents#89.
UNSENT = (
    (r"^--image ", "target_invalid"),                       # the image checks
    (r"^unknown option: ", "runtime_unavailable"),
    (r"^--max-time must be a positive integer", "runtime_unavailable"),
    (r"^cannot read prompt file: ", "runtime_unavailable"),
    (r"^empty prompt$", "runtime_unavailable"),
    (r"auth\.json", "oauth_invalid"),                       # reading the token store
    (r"^(open lock failed|flock failed): ", "runtime_unavailable"),   # the token-refresh lock
    (r"^(refresh response missing access_token|post-refresh: tokens missing)$", "oauth_invalid"),
    (r"\binvalid_grant\b", "oauth_invalid"),                # the token endpoint refused the refresh
)


def classify(stderr: str, status: int) -> tuple[str, str, bool]:
    """(error class, detail, sent). codex-call reports a failure as one `error: <message>` line.
    Judge that line, and match whole markers ("HTTP 429") rather than digits: an image path inside a
    run directory named after its timestamp can contain "429" or "401" (#23 verify I1)."""
    lines = re.findall(r"^error: (.*)$", stderr, re.MULTILINE)
    message = (lines[-1] if lines else stderr).strip()
    low = message.lower()
    detail = message[-500:]
    for pattern, error in UNSENT:
        if re.search(pattern, message):
            return error, detail, False
    if re.search(r"\bhttp 429\b", low) or "rate limit" in low or "usage limit" in low:
        return "rate_limit", detail, True
    if re.search(r"\bhttp 40[13]\b", low) or "unauthorized" in low or "refresh_token" in low or "token expired" in low:
        return "oauth_invalid", detail, True
    if "timed out" in low or "timeout" in low:
        return "timeout", detail, True
    if re.match(r"http 0\b", low):
        return "backend_error", (f"{detail} (no response arrived; codex-call does not say whether the request "
                                 "was sent, so it is counted as sent)"), True
    # The request may have been made and the backend or the connection failed. This is the default:
    # a failure that is not known to come before sending is treated as sent (#23 verify round 3, T1).
    return "backend_error", (detail if re.search(r"\bhttp \d{3}\b", low) else f"codex-call exit {status}: {detail}"), True
