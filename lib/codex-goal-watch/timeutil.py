#!/usr/bin/env python3
"""Strict, locale-independent parsing for Codex's displayed reset time."""
from __future__ import annotations
import datetime as dt
import re
import sys
from zoneinfo import ZoneInfo

raw, tz_name, now_raw = sys.argv[1:]
now = dt.datetime.fromtimestamp(int(now_raw), ZoneInfo(tz_name))
m = re.fullmatch(r"\s*(?:(1[0-2]|0?[1-9]):([0-5][0-9])\s*([AaPp][Mm])|([01]?\d|2[0-3]):([0-5][0-9]))\s*", raw)
if not m:
    raise SystemExit(2)
if m.group(1):
    hour = int(m.group(1)) % 12 + (12 if m.group(3).lower() == "pm" else 0)
    minute = int(m.group(2))
else:
    hour, minute = int(m.group(4)), int(m.group(5))
candidate = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
# A displayed time just in the past is a current, just-expired reset. A farther
# past time means the next occurrence, preventing stale-scrollback actions.
if candidate < now and (now - candidate).total_seconds() > 6 * 3600:
    candidate += dt.timedelta(days=1)
print(int(candidate.timestamp()))
