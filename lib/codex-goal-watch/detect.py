#!/usr/bin/env python3
"""Sanitize terminal bytes and classify only narrowly allowed Codex UI states."""
from __future__ import annotations
import re
import sys

raw = sys.stdin.buffer.read().replace(b"\x00", b"").replace(b"\r", b"\n")
raw = re.sub(rb"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", b"", raw)
raw = re.sub(rb"\x1b\[[0-?]*[ -/]*[@-~]", b"", raw)
out = bytearray()
for byte in raw:
    if byte == 8:
        if out and out[-1] != 10:
            out.pop()
    elif byte in (9, 10) or byte >= 32:
        out.append(byte)
text = out.decode("utf-8", "replace")
lines = [line.rstrip() for line in text.splitlines()]
visible = lines[-60:]
tail = visible[-24:]
joined = "\n".join(tail)
limit = bool(re.search(r"(?:you(?:'|’)ve hit your usage limit|usage limit reached)", joined, re.I))
goal = bool(re.search(r"goal hit usage limits\s*\(/goal resume\)", joined, re.I))
complete = bool(re.search(r"goal (?:complete|completed)", joined, re.I))
replace = all(x in joined for x in ("Replace goal?", "1. Replace current goal", "2. Cancel"))
times = re.findall(r"try again at\s+((?:1[0-2]|0?[1-9]):[0-5][0-9]\s*(?:AM|PM|am|pm)|(?:[01]?\d|2[0-3]):[0-5][0-9])", joined)
reset = times[-1] if times else ""
composer = "UNCERTAIN"
for line in reversed(visible[-10:]):
    if not line.strip():
        continue
    # Valid prompt glyphs plus a known mojibake rendering. Nothing broader is trusted.
    m = re.fullmatch(r"\s*(?:›|>|:|\u00e2\u20ac\u00ba)\s?(.*)", line)
    if not m:
        break
    value = m.group(1).strip()
    if not value:
        composer = "EMPTY"
    elif re.fullmatch(r"/goal resume(?:\s+\[Pasted Content [0-9]+ chars\])?", value):
        composer = "RESUME_VISIBLE"
    elif re.fullmatch(r"\[Pasted Content [0-9]+ chars\]", value):
        composer = "HIDDEN_PASTE"
    else:
        composer = "UNKNOWN"
    break
print(f"LIMIT={int(limit)}")
print(f"GOAL={int(goal)}")
print(f"COMPLETE={int(complete)}")
print(f"REPLACE={int(replace)}")
print(f"RESET_TEXT={reset}")
print(f"COMPOSER={composer}")
