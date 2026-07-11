#!/usr/bin/env python3
"""Strict, locale-independent parsing for Codex's displayed reset time."""
from __future__ import annotations
import datetime as dt
import re
import sys
from zoneinfo import ZoneInfo

raw, tz_name, now_raw = sys.argv[1:]
now = dt.datetime.fromtimestamp(int(now_raw), ZoneInfo(tz_name))
zone = ZoneInfo(tz_name)
raw = " ".join(raw.split())

# Explicit dates always win over the daily rollover heuristic. These formats
# cover Codex's customary English display plus ISO and European server views.
for fmt in (
    "%d.%m.%Y %H:%M", "%d.%m.%Y %I:%M %p",
    "%Y-%m-%d %H:%M", "%Y-%m-%d %I:%M %p",
    "%b %d, %Y %I:%M %p", "%B %d, %Y %I:%M %p",
    "%b %d, %Y %H:%M", "%B %d, %Y %H:%M",
):
    try:
        explicit = dt.datetime.strptime(raw, fmt).replace(tzinfo=zone)
    except ValueError:
        continue
    print(int(explicit.timestamp()))
    raise SystemExit(0)

# Month/day forms without a year are unambiguous only relative to the current
# year; a past value is the next annual occurrence.
for fmt in ("%b %d %I:%M %p", "%B %d %I:%M %p", "%b %d %H:%M", "%B %d %H:%M"):
    try:
        partial = dt.datetime.strptime(raw, fmt)
    except ValueError:
        continue
    explicit = partial.replace(year=now.year, tzinfo=zone)
    if explicit < now:
        explicit = explicit.replace(year=now.year + 1)
    print(int(explicit.timestamp()))
    raise SystemExit(0)

m = re.fullmatch(r"(?:(1[0-2]|0?[1-9]):([0-5][0-9])\s*([AaPp][Mm])|([01]?\d|2[0-3]):([0-5][0-9]))", raw)
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
elif candidate > now and (candidate - now).total_seconds() > 12 * 3600:
    candidate -= dt.timedelta(days=1)
print(int(candidate.timestamp()))
