# -*- coding: utf-8 -*-
"""Parses data/protocols/*.md into leaf sections (### ANC-1.2 ...), the units the answers are quoted from."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Dict, List, Tuple

_LEAF = re.compile(r"^###\s+([A-Z]{2,4}-\d+\.\d+)\s+(.*)$")
_GROUP = re.compile(r"^##\s+([A-Z]{2,4}-\d+)\s+(.*)$")
_LOCAL = re.compile(r"^>\s*Local terms:\s*(.*)$")


class Section:
    def __init__(self, sid: str, title: str, doc: str) -> None:
        self.id, self.title, self.doc = sid, title, doc
        self.lines: List[str] = []
        self.group = ""

    @property
    def text(self) -> str:
        return "\n".join(self.lines).strip()

    def units(self) -> List[str]:
        """Quotable pieces: bullets, sentences and table rows ("Check-up 4th: Between 36 weeks and term"), markdown cleaned."""
        out: List[str] = []
        header: List[str] = []
        for raw in self.lines:
            line = raw.strip()
            if not line:
                header = []
                continue
            if line.startswith("|"):
                cells = [c.strip() for c in line.strip("|").split("|")]
                if all(re.fullmatch(r":?-{2,}:?", c) for c in cells):
                    continue
                if not header:
                    header = cells
                    continue
                pairs = [f"{h}: {c}" if h and len(cells) > 2 and i > 0 else c for i, (h, c) in enumerate(zip(header, cells))]
                out.append(clean(" - ".join(pairs) if len(cells) > 2 else f"{cells[0]}: {cells[-1]}"))
                continue
            line = re.sub(r"^[-*]\s+", "", line)
            for sent in re.split(r"(?<=[.;!?])\s+(?=[A-Z(*])", line):
                s = clean(sent)
                if len(s) > 2:
                    out.append(s)
        return out


def clean(s: str) -> str:
    s = re.sub(r"[*_`]+", "", s)
    s = re.sub(r"\(\s*(?:[A-Z]{2,4}-\d+(?:\.\d+)?(?:\s*[,;]\s*)?)+\)", lambda m: m.group(0), s)
    return re.sub(r"\s+", " ", s).strip()


def load_sections(folder: Path) -> Tuple[Dict[str, Section], Dict[str, str]]:
    """({leaf id: Section}, {hinglish term: english term} read from the 'Local terms' line of each document)."""
    sections: Dict[str, Section] = {}
    local: Dict[str, str] = {}
    for path in sorted(folder.glob("*.md")):
        doc = path.name.split("_")[0]
        cur = None
        group = ""
        for line in path.read_text(encoding="utf-8").splitlines():
            m = _LEAF.match(line)
            if m:
                cur = Section(m.group(1), clean(m.group(2)), doc)
                cur.group = group
                sections[cur.id] = cur
                continue
            g = _GROUP.match(line)
            if g:
                group = clean(g.group(2))
                cur = None
                continue
            if line.startswith("## Sources"):
                cur = None
                continue
            lm = _LOCAL.match(line)
            if lm:
                for part in lm.group(1).split(";"):
                    if "=" in part:
                        en, hi = part.split("=", 1)
                        local[clean(hi.strip().rstrip("."))] = clean(en)
                continue
            if line.startswith("#"):
                cur = None
                continue
            if cur is not None:
                cur.lines.append(line)
    return sections, local
