"""Section detection and passage splitting. Passage text is an exact slice of the page text (offsets), never re-joined."""
import re
from dataclasses import dataclass
from typing import List, Optional

from app.services.protocol_import.extract import Page

_MD = re.compile(r"^#{1,6}\s+(.+?)\s*#*$")
_NUM = re.compile(r"^(\d+(?:\.\d+){0,3})[.)]?\s+(\S.{1,118})$")
_LABEL = re.compile(r"^(?:section|chapter|part)\s+([0-9IVXivx]+)\s*[:.\-]?\s*(.*)$", re.I)
_PARA = re.compile(r"\n[ \t]*\n")


@dataclass
class Draft:
    page_number: Optional[int]
    section_id: Optional[str]
    section_title: Optional[str]
    text: str
    ordinal: int


def _heading(line: str):
    """Return (section_id|None, title) if the single-line paragraph looks like a heading, else None."""
    s = line.strip()
    if not s or len(s) > 120 or "\n" in s:
        return None
    m = _MD.match(s)
    if m:
        return (None, m.group(1).strip())
    m = _LABEL.match(s)
    if m:
        return (m.group(1), (m.group(2) or s).strip())
    m = _NUM.match(s)
    if m and not s.endswith((".", ",", ";", ":")) and not m.group(2)[0].islower():      # "2 apples in a box" is body text, not a heading
        return (m.group(1), m.group(2).strip())
    letters = [c for c in s if c.isalpha()]
    if len(letters) >= 3 and s == s.upper() and any(c.isascii() for c in letters) and len(s) <= 80 and not s.endswith((".", ",")):
        return (None, s)
    return None


def split_pages(pages: List[Page], max_chars: int = 900) -> List[Draft]:
    drafts: List[Draft] = []
    sec_id: Optional[str] = None
    sec_title: Optional[str] = None
    auto = 0
    ordinal = 0
    for pg in pages:
        text = pg.text
        spans, pos = [], 0
        for m in _PARA.finditer(text):
            spans.append((pos, m.start())); pos = m.end()
        spans.append((pos, len(text)))
        group: Optional[List[int]] = None            # [start, end] of the passage being built

        def flush():
            nonlocal group, ordinal
            if group and text[group[0]:group[1]].strip():
                ordinal += 1
                drafts.append(Draft(pg.number, sec_id, sec_title, text[group[0]:group[1]], ordinal))
            group = None

        for a, b in spans:
            chunk = text[a:b]
            if not chunk.strip():
                continue
            h = _heading(chunk)
            if not h and "\n" in chunk:
                # PDF text often puts the heading on the line directly above its body (no blank line)
                first, _, rest = chunk.partition("\n")
                h2 = _heading(first)
                if h2 and h2[0] is not None and rest.strip():                         # only numbered/'Section N' headings, to avoid false positives
                    flush()
                    sec_id, sec_title = h2[0], h2[1]
                    off = a + len(first) + 1
                    group = [off + (len(rest) - len(rest.lstrip("\n "))), b]
                    continue
            if h:
                flush()
                auto += 0 if h[0] else 1
                sec_id = h[0] or "S%d" % auto
                sec_title = h[1]
                continue
            if group is None:
                group = [a, b]
            elif (b - group[0]) <= max_chars:
                group[1] = b
            else:
                flush()
                group = [a, b]
        flush()
    return drafts
