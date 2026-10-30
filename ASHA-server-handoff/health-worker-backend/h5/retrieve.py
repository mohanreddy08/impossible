# -*- coding: utf-8 -*-
"""BM25 over the protocol's leaf sections, with the Hinglish -> English expansion. No model, no download; 107 sections."""
from __future__ import annotations

import math
import re
from collections import Counter
from typing import Dict, Iterable, List, Tuple

from .expand import EXPAND
from .normalize import normalize
from .protocols import Section

_TOK = re.compile(r"[a-z]+|\d+(?:\.\d+)?")
_STOP = set("sir madam sahab gaya gayi gaye chala chali chale unka unki unke uska uski uske ab didi madam sir ji namaste parivar mayke hu hun hoon raha rahi rahe diya diye liya bol bata batao batana pooch poochni baat ek ke ki ka ko se me men mein hai he h hu ho hota hoti hote raha rahi rahe the tha thi aur ya to ye yeh wo woh is us par pe kya kar karo karna kare liye ek do kuch koi bhi nahi na ne hi bahut thoda sa the a an of in on at for is are was be and or if it this that with to by from as do does did can could should would will may i my me we our you your".split())


def stem(w: str) -> str:
    if w.isdigit() or "." in w:
        return w
    for suf in ("ing", "es", "ed", "s"):
        if len(w) > len(suf) + 3 and w.endswith(suf) and not w.endswith("ss"):
            return w[: -len(suf)]
    return w


def tokenize(text_normalised: str) -> List[str]:
    return [stem(t) for t in _TOK.findall(text_normalised) if t not in _STOP]


def expand_query(norm: str) -> List[Tuple[str, float]]:
    """(token, weight): the question's own tokens (weight 1) plus the English words they stand for. An expansion is shared among its
    words (a word that expands into 4 terms gives each 0.5), so a common word cannot outvote a rare, specific one."""
    words = norm.split()
    out: List[Tuple[str, float]] = []
    seen_phrase = set()
    for i, w in enumerate(words):
        groups: List[List[str]] = []
        for n in (3, 2):
            ph = " ".join(words[i: i + n])
            if len(ph.split()) == n and ph in EXPAND and (i, n) not in seen_phrase:
                groups.append(EXPAND[ph])
                seen_phrase.add((i, n))
        if w in EXPAND:
            groups.append(EXPAND[w])
        for g in groups:
            toks: List[str] = []
            for t in g:
                toks.extend(tokenize(normalize(t)))
            if toks:
                wt = 1.0 / len(toks)
                out.extend((t, wt) for t in toks)
    base = [(t, 1.0) for t in tokenize(norm)]
    have = {t for t, _ in base}
    return base + [(t, w) for t, w in out if t not in have]


class Index:
    def __init__(self, sections: Dict[str, Section], local_terms: Dict[str, str], k1: float = 1.4, b: float = 0.55) -> None:
        self.sections = sections
        self.ids = list(sections)
        self.k1, self.b = k1, b
        self.docs: List[List[str]] = []
        # the documents' "Local terms" lines teach the expansion too (garbh = pregnancy, lal goli = IFA ...)
        self.local = {}
        for hi, en in local_terms.items():
            for term in re.split(r"[/,]", hi):
                term = normalize(term).strip()
                if term:
                    self.local[term] = tokenize(normalize(en))
        for sid in self.ids:
            s = sections[sid]
            toks = tokenize(normalize(s.title)) * 3 + tokenize(normalize(s.group)) + tokenize(normalize(s.text))
            toks += tokenize(normalize(sid.replace("-", " ").replace(".", " ")))
            self.docs.append(toks)
        # sentence-level documents: every quotable unit (bullet, sentence, table row) with its section title
        self.unit_docs: List[Tuple[str, str, List[str]]] = []  # (section id, unit text, tokens)
        for sid in self.ids:
            s = sections[sid]
            head = tokenize(normalize(s.title))
            for u in s.units():
                self.unit_docs.append((sid, u, head + tokenize(normalize(u))))
        self.tf = [Counter(d) for d in self.docs]
        self.avg = sum(len(d) for d in self.docs) / len(self.docs)
        df: Counter = Counter()
        for d in self.docs:
            df.update(set(d))
        n = len(self.docs)
        self.idf = {t: math.log(1 + (n - c + 0.5) / (c + 0.5)) for t, c in df.items()}
        self.utf = [Counter(d) for _, _, d in self.unit_docs]
        self.uavg = sum(len(d) for _, _, d in self.unit_docs) / max(1, len(self.unit_docs))
        udf: Counter = Counter()
        for _, _, d in self.unit_docs:
            udf.update(set(d))
        un = len(self.unit_docs)
        self.uidf = {t: math.log(1 + (un - c + 0.5) / (c + 0.5)) for t, c in udf.items()}

    def query_tokens(self, norm: str) -> List[Tuple[str, float]]:
        toks = [(t, w * 2.0 if (w == 1.0 and self.idf.get(t, 0.0) >= 2.4 and not t.isdigit()) else w) for t, w in expand_query(norm)]
        for term, en in self.local.items():
            if term in norm and en:
                toks.extend((t, 1.0 / (len(en) ** 0.5)) for t in en)
        return toks

    def search(self, norm: str, k: int = 5, restrict: Iterable[str] = ()) -> List[Tuple[float, str]]:
        q: Dict[str, float] = {}
        for t, w in self.query_tokens(norm):
            q[t] = q.get(t, 0.0) + w
        allow = set(restrict)
        scores = []
        for i, sid in enumerate(self.ids):
            if allow and sid not in allow:
                continue
            tf, dl = self.tf[i], len(self.docs[i])
            s = 0.0
            for t, qw in q.items():
                f = tf.get(t)
                if not f:
                    continue
                s += self.idf[t] * f * (self.k1 + 1) / (f + self.k1 * (1 - self.b + self.b * dl / self.avg)) * (1 + 0.5 * math.log(1 + qw))
            scores.append((s, sid))
        scores.sort(reverse=True)
        return scores[:k]

    def unit_scores(self, norm: str, numbers=()) -> List[Tuple[float, int]]:
        q: Dict[str, float] = {}
        for t, w in self.query_tokens(norm):
            q[t] = q.get(t, 0.0) + w
        out = []
        for i, (sid, _, d) in enumerate(self.unit_docs):
            tf, dl = self.utf[i], len(d)
            s = 0.0
            for t, qw in q.items():
                f = tf.get(t)
                if f:
                    s += self.uidf[t] * f * (self.k1 + 1) / (f + self.k1 * (1 - self.b + self.b * dl / self.uavg)) * (1 + 0.5 * math.log(1 + qw))
            if s > 0 and numbers:
                s *= 1.0 + 0.35 * range_hits(self.unit_docs[i][1], numbers)
            out.append((s, i))
        return out

    def search_units(self, norm: str, k: int = 5, section_weight: float = 0.35, numbers=()) -> List[Tuple[float, str]]:
        """Section ranking by its best sentence (decisive facts), plus a share of the whole-section score (topic)."""
        us = self.unit_scores(norm, numbers)
        best: Dict[str, float] = {}
        for s, i in us:
            sid = self.unit_docs[i][0]
            if s > best.get(sid, 0.0):
                best[sid] = s
        sec = dict((sid, sc) for sc, sid in self.search(norm, len(self.ids)))
        top_sec = max(sec.values()) or 1.0
        top_unit = max(best.values() or [1.0]) or 1.0
        combined = []
        for sid in self.ids:
            c = best.get(sid, 0.0) / top_unit + section_weight * sec.get(sid, 0.0) / top_sec
            combined.append((c, sid))
        combined.sort(reverse=True)
        return combined[:k]


_RANGE = re.compile(r"(\d+(?:\.\d+)?)\s*(?:months?|years?|weeks?|days?|g/dl|mg/dl|cm)?\s*(?:to|up to|[-–])\s*(\d+(?:\.\d+)?)")


def range_hits(unit_text: str, numbers) -> int:
    """How many of the question's numbers fall inside a 'A-B' / 'A to B' range written in this sentence."""
    hits = 0
    for m in _RANGE.finditer(unit_text.replace("–", "-")):
        lo, hi = float(m.group(1)), float(m.group(2))
        if lo < hi and any(lo <= n <= hi for n in numbers):
            hits += 1
    return hits
