import sys
import os
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.abspath("backend"))

from app.api.endpoints import normalize_timestamp, IST

test_cases = [
    ("2026-08-31T07:42:00.000", "Naive client local time"),
    ("2026-08-31 07:42:00", "Space separated naive time"),
    ("2026-08-31", "Date only"),
    ("2026-08-31T02:12:00.000Z", "UTC Z timestamp (7:42 AM IST)"),
    ("2026-08-31T07:42:00+05:30", "Explicit IST timestamp"),
    (None, "None / Current fallback"),
]

print("TIMESTAMP NORMALIZATION TESTS:")
for inp, desc in test_cases:
    out = normalize_timestamp(inp)
    dt = datetime.fromisoformat(out)
    dt_ist = dt.astimezone(IST)
    print(f"[{desc}]\n  Input:  {inp}\n  Output: {out}\n  IST:    {dt_ist.strftime('%d %b %Y, %I:%M:%S %p')}\n")
