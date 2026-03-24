#!/usr/bin/env python3
"""Compute first Azure Automation weekday schedule occurrences.

Input JSON on stdin:
  {
    "anchor_rfc3339": "...",
    "timezone": "Europe/London",
    "startup_time": "13:30",
    "shutdown_time": "16:15"
  }

Output JSON on stdout:
  {
    "startup_start": "2026-03-19T13:30:00Z",
    "shutdown_start": "2026-03-19T16:15:00Z"
  }
"""

from __future__ import annotations

import json
import sys
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo


def parse_hhmm(value: str) -> tuple[int, int]:
    hour_str, minute_str = value.split(":", 1)
    return int(hour_str), int(minute_str)


def next_weekday_occurrence(anchor_utc: datetime, tz_name: str, hhmm: str) -> str:
    tz = ZoneInfo(tz_name)
    anchor_local = anchor_utc.astimezone(tz)
    hour, minute = parse_hhmm(hhmm)

    candidate_date = anchor_local.date()
    while True:
        is_weekday = candidate_date.weekday() < 5
        candidate_local = datetime(
            candidate_date.year,
            candidate_date.month,
            candidate_date.day,
            hour,
            minute,
            tzinfo=tz,
        )

        if is_weekday and anchor_local < candidate_local:
            candidate_utc = candidate_local.astimezone(UTC)
            return candidate_utc.strftime("%Y-%m-%dT%H:%M:%SZ")

        candidate_date += timedelta(days=1)


def main() -> int:
    query = json.load(sys.stdin)
    anchor_rfc3339 = query["anchor_rfc3339"].replace("Z", "+00:00")
    anchor_utc = datetime.fromisoformat(anchor_rfc3339).astimezone(UTC)
    timezone = query["timezone"]

    result = {
        "startup_start": next_weekday_occurrence(anchor_utc, timezone, query["startup_time"]),
        "shutdown_start": next_weekday_occurrence(anchor_utc, timezone, query["shutdown_time"]),
    }

    json.dump(result, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
