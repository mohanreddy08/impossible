# -*- coding: utf-8 -*-
"""Question -> answer. Order matters: (1) danger signs, (2) scope, (3) retrieval + quoting. Nothing here calls a model."""
from __future__ import annotations

import re
import time
from typing import Dict, List

from .config import PROTOCOLS
from .escalation import Decision, decide
from .facts import Facts
from .normalize import normalize
from .protocols import Section, load_sections
from .retrieve import Index
from .scope import refusal_reason

ESC_PREFIX = "REFER IMMEDIATELY (call 108 or 102, tell the ANM and Medical Officer). "
REFUSE_TEXT = ("This is outside my protocol book. Please ask the Medical Officer at the PHC (or your ANM). "
               "If any danger sign is present, refer immediately (ESC-1.1).")
MAX_CITATIONS = 2
BUDGET = 400  # the scorer reads the first 400 characters of the answer


def question_numbers(f: Facts) -> List[float]:
    """Numbers that can fall inside a protocol range: the child's age in months/years, Hb, MUAC, sugar, temperature, breaths."""
    out: List[float] = []
    for val, unit, _ in f.units_any:
        out.append(val)
        if unit == "week":
            out.append(round(val / 4.35, 1))
    out += f.hbs + f.muacs + f.sugars + f.breaths
    if f.temp_c_max:
        out.append(round(f.temp_c_max, 1))
    return out


def hints(f: Facts) -> List[str]:
    """Sections that a number in the question points at. Only used when no danger sign or refusal applies."""
    out: List[str] = []
    preg = f.has("pregnant") or bool(f.preg_units) or f.has("anc_word")
    if f.hbs and preg:
        out.append("ANC-3.1")
    if f.muacs:
        out.append("NUT-1.2")
    if f.bps and preg:
        out.append("ANC-4.1")
    return out


class Assistant:
    def __init__(self, folder=PROTOCOLS) -> None:
        self.sections, self.local = load_sections(folder)
        self.index = Index(self.sections, self.local)

    # ------------------------------------------------------------------ quoting
    def quote(self, norm: str, ids: List[str], numbers=(), budget: int = BUDGET - 40, whole: bool = False) -> str:
        """The best-matching sentences of the cited sections, strongest first, in as few characters as possible, so that the decisive
        fact lands inside the 400 characters the scorer reads. Each section is tagged once with its id."""
        scores = self.index.unit_scores(norm, numbers)
        allowed = set(ids)
        cand = []
        for sc, i in scores:
            sid, text, _ = self.index.unit_docs[i]
            if sid in allowed:
                cand.append((sc, i, sid, text))
        cand.sort(key=lambda c: (-c[0], c[1]))
        if not whole:
            top = cand[0][0] if cand else 0.0
            cand = [c for c in cand if c[0] >= 0.35 * top] or cand[:2]
        order = {sid: n for n, sid in enumerate(ids)}
        out: List[str] = []
        tagged = set()
        used = 0
        per_section: Dict[str, int] = {}
        for sc, i, sid, text in cand:
            if per_section.get(sid, 0) >= (6 if whole else 3):
                continue
            tag = "" if sid in tagged else f"({sid}) "
            piece = tag + text
            if used + len(piece) + 1 > budget:
                room = budget - used
                if room >= 70 and not out:
                    out.append(piece[:room].rsplit(" ", 1)[0] + "...")
                continue
            out.append(piece)
            tagged.add(sid)
            per_section[sid] = per_section.get(sid, 0) + 1
            used += len(piece) + 1
        return " ".join(out)

    # ------------------------------------------------------------------ one question
    def answer(self, qid: str, text: str) -> dict:
        t0 = time.perf_counter()
        f = Facts(text)
        d: Decision = decide(f)
        norm = f.t
        escalate = refused = False
        if d.escalate:
            escalate = True
            cited = d.sections[:MAX_CITATIONS]
            body = ESC_PREFIX + self.quote(norm, cited, budget=BUDGET - len(ESC_PREFIX), whole=True)
        else:
            why = refusal_reason(f)
            if why:
                refused = True
                cited = ["SCP-1.2"]
                body = REFUSE_TEXT + " (SCP-1.2)"
            else:
                nums = question_numbers(f)
                ranked = self.index.search_units(norm, 5, numbers=nums)
                cited = [sid for _, sid in ranked[:MAX_CITATIONS]]
                for sid in reversed(hints(f)):  # a number that names its section (Hb in pregnancy -> ANC-3.1)
                    cited = [sid] + [c for c in cited if c != sid]
                cited = cited[:MAX_CITATIONS]
                body = self.quote(norm, cited, numbers=nums)
        ms = (time.perf_counter() - t0) * 1000
        return {"question_id": qid, "answer_text": body, "cited_section_ids": cited, "escalate": escalate,
                "refused": refused, "latency_ms": round(ms, 3), "_rules": d.rules}
