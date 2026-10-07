#!/usr/bin/env python3
"""How a failed codex-call is reported by /codex-pro:codex-visual-xval (#23): its error class, and
whether the request may have left the machine. Pure functions; scripts/xval.py records the result.
"""
import re


# Failures codex-call reports before any network request: the only ones that leave a round unsent.
# A closed list of codex-call's own messages, each matched against the WHOLE first `error:` line it
# prints (#23 verify round 4, U1). Matching anywhere let a backend message that mentioned
# `auth.json` withdraw a sent request, and the last line could be one a multi-line backend body
# supplied. No other failure may be inferred to be unsent from its wording: codex-call prints
# `HTTP 0: (no body)` for every failure before a response, an upload that finished included, and a
# failed token refresh prints `HTTP <status>` exactly as a failed request does (round 3, T1).
# Residual until codex-call marks what it sent (PsychQuant/parallel-ai-agents#89): a backend error
# event is printed without a prefix, so one that read exactly like a line below would still match.
UNSENT = (
    (r"--image .+", "target_invalid"),                      # the image checks
    (r"unknown option: .+", "runtime_unavailable"),
    (r"--max-time must be a positive integer( \(got .*\))?", "runtime_unavailable"),
    (r"cannot read prompt file: .+", "runtime_unavailable"),
    (r"empty prompt", "runtime_unavailable"),
    (r"auth\.json is not an object", "oauth_invalid"),      # the token store
    (r"auth\.json missing tokens\.access_token/refresh_token", "oauth_invalid"),
    (r"(open lock|flock) failed: .+", "runtime_unavailable"),   # the token-refresh lock
    (r"refresh response missing access_token|post-refresh: tokens missing", "oauth_invalid"),
)


def classify(stderr: str, status: int) -> tuple[str, str, bool]:
    """(error class, detail, sent). codex-call reports a failure as `error: <message>`, and the
    message can run over several lines (an HTTP body). Judge its first line, and match whole markers
    ("HTTP 429") rather than digits: an image path inside a run directory named after its timestamp
    can contain "429" or "401" (#23 verify I1)."""
    first = re.search(r"^error: (.*)$", stderr, re.MULTILINE)
    message = (first.group(1) if first else stderr).strip()
    low = message.lower()
    detail = message[-500:]
    for pattern, error in UNSENT:
        if re.fullmatch(pattern, message):
            return error, detail, False
    if re.search(r"\bhttp 429\b", low) or "rate limit" in low or "usage limit" in low:
        return "rate_limit", detail, True
    if (re.search(r"\bhttp 40[13]\b", low) or "unauthorized" in low or "refresh_token" in low
            or "invalid_grant" in low or "token expired" in low):
        return "oauth_invalid", detail, True
    if "timed out" in low or "timeout" in low:
        return "timeout", detail, True
    if re.match(r"http 0\b", low):
        return "backend_error", (f"{detail} (no response arrived; codex-call does not say whether the request "
                                 "was sent, so it is counted as sent)"), True
    # The request may have been made and the backend or the connection failed. This is the default:
    # a failure that is not known to come before sending is treated as sent (#23 verify round 3, T1).
    return "backend_error", (detail if re.search(r"\bhttp \d{3}\b", low) else f"codex-call exit {status}: {detail}"), True
