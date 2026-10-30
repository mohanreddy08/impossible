# -*- coding: utf-8 -*-
"""Everything the rules need to know about a question, read from its normalised text: which concepts it mentions (and whether a
mention is negated, as in "pair me sujan ni"), and the numbers in it (ages, durations, breath counts, temperature, weight, BP ...).

Deliberately plain: regexes and small loops only, so the Dart version (lib/domain/h5/h5_facts.dart) behaves the same way."""
from __future__ import annotations

import re
from typing import Dict, List, Optional, Tuple

from .lexicon import CONCEPTS
from .normalize import fold_pattern, normalize

_COMPILED: Dict[str, List["re.Pattern[str]"]] = {}


def compiled_source(raw: str) -> str:
    """The exact regex source the engine compiles for a lexicon pattern (word-start + phonetic folding)."""
    return fold_pattern(raw if not re.match(r"[A-Za-z0-9]", raw) else r"\b" + raw)


def _concept(name: str) -> List["re.Pattern[str]"]:
    pats = _COMPILED.get(name)
    if pats is None:
        # a pattern that starts with a letter or digit must start a word ("liver" must not match inside "delivery")
        pats = [re.compile(compiled_source(p)) for p in CONCEPTS[name]]
        _COMPILED[name] = pats
    return pats


def _rx(p: str) -> "re.Pattern[str]":
    return re.compile(fold_pattern(p))


_UNITS = {
    "year": _rx(r"(?:sal|saal|years?|yrs?|varsh\w*|vars|vayasu|varshachya)"),
    "month": _rx(r"(?:mahin\w*|months?|nelal\w*|mahinya|masa)"),
    "week": _rx(r"(?:hafte?|haft\w*|weeks?|hapta|sapt\w*)"),
    "day": _rx(r"(?:din|dino|days?|divas\w*|dibas|rojul\w*|dinon)"),
    "hour": _rx(r"(?:ghant\w*|hours?|hrs?)"),
}
_DAYS = {"year": 365.0, "month": 30.4, "week": 7.0, "day": 1.0}
_NUM_UNIT = _rx(r"(\d+(?:\.\d+)?)\s*(?:th\s+)?(sal|saal|years?|yrs?|varsh\w*|vars|vayasu|varshachya|mahin\w*|months?|nelal\w*|mahinya|masa|hafte?|haft\w*|weeks?|hapta|sapt\w*|din|dino|days?|divas\w*|dibas|rojul\w*|dinon)\b")
_AGE_NEXT = {"ka", "ki", "ke", "old", "vala", "vali", "ko", "ho", "hu", "hui", "hue", "hai", "he", "hoga", "huya", "hua", "yeh"}
_DURATION_NEXT = {"se", "tak", "roz", "pehle", "pahle", "bad", "baad", "me", "men", "mein", "late", "pe", "par", "chal", "ho", "hue", "ke", "lage", "lag"}
_FUNC = {"ka", "ki", "ke", "se", "tak", "ko", "me", "men", "pe", "par"}


def _unit_of(word: str) -> str:
    for name in ("year", "month", "week", "day", "hour"):
        if _UNITS[name].fullmatch(word):
            return name
    return ""


class Facts:
    def __init__(self, text: str):
        self.raw = text or ""
        self.t = normalize(self.raw)
        self.tokens = self.t.split()
        self._cache: Dict[str, List[Tuple[int, int]]] = {}
        self._parse_numbers()

    # ----------------------------------------------------------------- concepts
    def spans(self, name: str) -> List[Tuple[int, int]]:
        sp = self._cache.get(name)
        if sp is None:
            sp = []
            for pat in _concept(name):
                for m in pat.finditer(self.t):
                    if m.end() > m.start():
                        sp.append((m.start(), m.end()))
            self._cache[name] = sp
        return sp

    def has(self, name: str) -> bool:
        return bool(self.spans(name))

    # concepts whose own wording already contains the negation ("doodh nahi pi raha"): never judged negated again
    _SELF_NEG = {"not_feeding", "not_drinking", "vomit_all", "movement", "poor_appetite", "stroke", "unconscious", "hands_feet_only",
                 "skin_slow", "skin_very_slow", "weak_cry", "stridor", "breath_fast", "blue", "cold_touch", "lethargic", "limp_limbs"}

    def negated(self, span: Tuple[int, int], name: str = "") -> bool:
        """A negation word right after (the next two words) or right before (the previous word): 'sujan ni', 'khun nahi aa raha', 'nahi pee'."""
        if name in self._SELF_NEG:
            return False
        after = " ".join(self.t[span[1]:].split()[:2])
        before = " ".join(self.t[:span[0]].split()[-1:])
        neg = _concept("neg")
        return any(p.search(after) for p in neg) or any(p.search(before) for p in neg)

    def has_pos(self, name: str) -> bool:
        """Mentioned at least once without a negation next to it."""
        return any(not self.negated(s, name) for s in self.spans(name))

    def near(self, a: str, b: str, window: int = 40) -> bool:
        """Concept a and concept b both appear within [window] characters of each other (either order)."""
        for s1 in self.spans(a):
            for s2 in self.spans(b):
                if s1 == s2:
                    continue
                if s2[0] - s1[1] <= window and s1[0] - s2[1] <= window:
                    return True
        return False

    def near_pos(self, a: str, b: str, window: int = 40) -> bool:
        for s1 in self.spans(a):
            if self.negated(s1, a):
                continue
            for s2 in self.spans(b):
                if s1 == s2 or self.negated(s2, b):
                    continue
                if s2[0] - s1[1] <= window and s1[0] - s2[1] <= window:
                    return True
        return False

    def count_pos(self, names: List[str]) -> int:
        return sum(1 for n in names if self.has_pos(n))

    # ----------------------------------------------------------------- numbers
    def _parse_numbers(self) -> None:
        t = self.t
        self.ages: List[float] = []  # days: "N unit ka|ki|ke|old"
        self.durations: List[float] = []  # days: "N unit se|tak|roz ..."
        self.timeagos: List[float] = []  # days: "N unit pehle|baad"
        self.preg_units: List[Tuple[float, str]] = []  # "8 mahine ki pregnant" -> (8, 'month')
        self.units_any: List[Tuple[float, str, str]] = []  # (value, unit, next word)
        for m in _NUM_UNIT.finditer(t):
            val = float(m.group(1))
            unit = _unit_of(m.group(2))
            if not unit or unit == "hour":
                continue
            rest = t[m.end(): m.end() + 40].split()
            nxt = rest[0] if rest else ""
            nxt2 = rest[1] if len(rest) > 1 else ""
            days = val * _DAYS[unit]
            self.units_any.append((val, unit, nxt))
            before = t[max(0, m.start() - 14): m.start()]
            before_wide = t[max(0, m.start() - 26): m.start()]
            rest_text = t[m.end(): m.end() + 30]
            rest_text = re.sub(r"^\s*(?:ka|ki|ke|old|vala|vali|ho|hu|gaya|gayi|chuka|chuki)\b\s*", " ", rest_text) if nxt in ("ka", "ki", "ke", "old", "vala", "vali", "ho", "hu") else rest_text
            preg_after = re.match(r"\s*(?:ki|ka|ke)?\s*(?:pregn\w*|prgn\w*|garbh\w*|gharbh\w*|preg\b)", t[m.end():m.end() + 24]) is not None
            if preg_after and unit in ("month", "week"):
                self.preg_units.append((val, unit))
                continue
            if nxt in ("se", "tak", "roz") or nxt2 in ("se", "tak") and nxt in ("ho", "chal"):
                self.durations.append(days)
            elif nxt in ("pehle", "pahle", "bad", "baad") or (nxt == "ke" and nxt2 in ("bad", "baad", "pehle")):
                self.timeagos.append(days)
            elif nxt in ("ka", "ki", "ke", "old", "vala", "vali") or (nxt in ("ho", "hu") and nxt2 in ("gaya", "gayi", "chuka", "chuki")):
                person = r"(?:pillav\w*|bach\w*|baby|babu|navjat\w*|nobojato|beta|beti|bete|ladk\w*|shishu|mulal\w*|amma|chach\w*|aadmi|aurat|mahila|kak[ai]|dad[ai]|nan[ai]|saas|sasur|patient|marij\w*|bahu|ladki)"
                if re.match(r"\s*(?:\w+\s+){0,1}" + fold_pattern(person), rest_text) or re.search(fold_pattern(person) + r"\s+(?:\w+\s+){0,2}$", before_wide):
                    self.ages.append(days)
            elif nxt in ("hue", "hu", "ho") and any(p_.search(before) for p_ in _concept("delivery")):
                self.timeagos.append(days)
            elif re.match(fold_pattern(r"(?:pillav\w*|babu|bachar|mulal\w*|shishu|bach\w*|baby|navjat\w*)"), nxt):
                self.ages.append(days)  # "2 years pillavadiki", "8 nelala babu ki": the unit is followed by 'child'
            elif re.search(r"(?:bach\w*|baby|navjat\w*|beta|beti|bete)\s+(?:\w+\s+)?$", before) and nxt in ("hai", "he"):
                self.ages.append(days)
        # the baby's age may also be written before the unit without 'ka': "bachcha 20 din ka" is covered; "baby 6 din" is not
        self.age_days: Optional[float] = min(self.ages) if self.ages else None

        def floats(pattern: str, group: int = 1, lo: float = 0, hi: float = 1e9) -> List[float]:
            out = []
            for mm in re.finditer(fold_pattern(pattern), t):
                try:
                    v = float(mm.group(group))
                except (ValueError, IndexError, TypeError):
                    continue
                if lo <= v <= hi:
                    out.append(v)
            return out

        # breath counts per minute
        b = floats(r"(?:saans|breath\w*|swas\w*|hanf\w*)\W+(?:\w+\W+){0,3}?(\d{2,3})\b(?!\s*/)", 1, 20, 130)
        b += floats(r"\bminute\s+(?:me|men|mein)\s+(\d{2,3})\b", 1, 20, 130)
        b += floats(r"\b(\d{2,3})\s*(?:per\s*minute|/\s*min|bar\b|baar\b|count\b|breaths?\b|\bmin\b)", 1, 20, 130)
        b += floats(r"\bgin\w*\s+(?:\w+\s+){0,2}(\d{2,3})\b", 1, 20, 130)
        self.breaths = b

        # temperature (C): 94-108 reads as Fahrenheit, 35-42.5 as Celsius
        temps: List[float] = []
        near_fever = []
        for mm in re.finditer(r"(?<![\d/.:])(\d{2,3}(?:\.\d)?)(?![\d/:])", t):
            try:
                v = float(mm.group(1))
            except ValueError:
                continue
            ctx = t[max(0, mm.start() - 40): mm.end() + 22]
            marked = re.search(r"\b(?:f|degree|deg|c|fahrenheit|celsius)\b", t[mm.end(): mm.end() + 14]) is not None
            if re.search(fold_pattern(r"bukh\w*|taap|fever|temperature|temp\b|degree|jvar|daggu|garam|thanda"), ctx) or marked:
                if 94 <= v <= 108:
                    temps.append((v - 32) * 5 / 9)
                    near_fever.append(v)
                elif 35 <= v <= 42.5 and (marked or re.search(r"\.\d", mm.group(1))):
                    temps.append(v)
        self.temps_c = temps
        self.temp_c_max: Optional[float] = max(temps) if temps else None
        self.temp_f_min: Optional[float] = (min(temps) * 9 / 5 + 32) if temps else None

        w = floats(r"(\d(?:\.\d{1,2})?)\s*(?:kg|kilo|kgs)\b", 1, 0.5, 9)
        self.weights_kg = w
        self.bps = [(int(a), int(c)) for a, c in re.findall(r"\b(\d{2,3})\s*/\s*(\d{2,3})\b", t) if 60 <= int(a) <= 260 and 30 <= int(c) <= 160]
        self.bp_systolic_only = floats(r"\bbp\s*(?:ka\s*)?(?:aaya\s*)?(\d{3})\b(?!\s*/)", 1, 80, 260)
        self.hbs = floats(r"\bhb\s*(?:ka\s*)?(?:level\s*)?(?:aaya\s*)?(\d{1,2}(?:\.\d)?)\b", 1, 2, 20)
        self.sugars = floats(r"sugar\s*(?:level\s*)?(?:ka\s*)?(?:random\s*)?(?:aaya\s*)?(\d{2,3})\b", 1, 20, 700) + floats(r"\brbs\s*(\d{2,3})\b", 1, 20, 700)
        self.muacs = floats(r"\bmuac\s*(?:ka\s*)?(?:aaya\s*)?(\d{1,2}(?:\.\d)?)\b", 1, 5, 25)
        self.hours = floats(r"(\d+(?:\.\d)?)\s*(?:ghant\w*|hours?|hrs?)\b", 1, 1, 100)
        pads = floats(r"(\d{1,2})\s*(?:pads?|ped|paid|kapde)\b", 1, 1, 60)
        self.pads = pads
        self.pad_minutes = floats(r"\b(?:pads?|ped|paid|kapda)\s+(\d{1,2})(?:\s*-\s*\d{1,2})?\s*(?:minute|min)\w*", 1, 1, 60) + floats(r"\b(\d{1,2})\s*(?:minute|min)\w*\s+(?:me|men)\s+(?:\w+\s+){0,2}(?:pads?|ped|paid|bhar)", 1, 1, 60)
        self.counts_near: List[float] = floats(r"(\d{1,3})(?:\s*-\s*\d{1,3})?\s*(?:honge|hai|he|count)?\b", 1, 1, 200)

    # convenience
    def baby_age_days(self) -> Optional[float]:
        return self.age_days
