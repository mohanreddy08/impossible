"""Where the hackathon data lives. Set H5_DATA to the pack's data/ folder; nothing from the pack is copied into git."""
import os
from datetime import date
from pathlib import Path

TODAY = date(2026, 10, 26)  # the visit list is made for this day (VIS-1.1)

_DEFAULT = Path.home() / "Downloads" / "H5_Frontline_Health_Worker_Companion" / "data"
DATA = Path(os.environ.get("H5_DATA", str(_DEFAULT)))
PROTOCOLS = DATA / "protocols"
