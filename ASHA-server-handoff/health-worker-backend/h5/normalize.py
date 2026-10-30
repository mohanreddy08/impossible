"""Turns a messy health-worker question into one canonical Latin string that the rules and retrieval can match.

  "बच्चे के दस्त में खून आ रहा है"  ->  "bache ke dast men khun a raha hai"
  "Khoon  aa raha h!!"            ->  "khun a raha h"

Steps (kept simple on purpose so the Dart port in the app gives the identical result):
  1. lower-case, Unicode NFC
  2. Devanagari -> Latin (a small phonetic transliteration; Hindi/Marathi)
  3. digits written in Devanagari -> ASCII digits
  4. punctuation -> spaces (keeps digits, '.', '/', '-' and ':' because of 98.6, 140/90, Penta-3, 10:30)
  5. phonetic folding of Roman spellings: aa/ee/ii/oo/uu -> a/i/i/u/u, ai/ei -> e, w -> v, repeated letters (and chch/shsh...) -> one, 'chh' -> 'ch'
"""
from __future__ import annotations

import re
import unicodedata

_CONS = {
    "क": "k", "ख": "kh", "ग": "g", "घ": "gh", "ङ": "n", "च": "ch", "छ": "ch", "ज": "j", "झ": "jh", "ञ": "n",
    "ट": "t", "ठ": "th", "ड": "d", "ढ": "dh", "ण": "n", "त": "t", "थ": "th", "द": "d", "ध": "dh", "न": "n",
    "प": "p", "फ": "f", "ब": "b", "भ": "bh", "म": "m", "य": "y", "र": "r", "ल": "l", "ळ": "l", "व": "v",
    "श": "sh", "ष": "sh", "स": "s", "ह": "h", "\u0958": "k", "\u0959": "kh", "\u095a": "g", "\u095b": "j", "\u095c": "d", "\u095d": "dh", "\u095e": "f",
}
_VOWELS = {"अ": "a", "आ": "a", "इ": "i", "ई": "i", "उ": "u", "ऊ": "u", "ए": "e", "ऐ": "ai", "ओ": "o", "औ": "au", "ऋ": "ri", "ऑ": "o"}
_MATRAS = {"ा": "a", "ि": "i", "ी": "i", "ु": "u", "ू": "u", "े": "e", "ै": "ai", "ो": "o", "ौ": "au", "ृ": "ri", "ॉ": "o"}
_NASAL = {"ं": "n", "ँ": "n", "ः": "h"}
_VIRAMA = "्"
_NUKTA = "़"
_DIGITS = {ord(c): str(i) for i, c in enumerate("०१२३४५६७८९")}


def _is_dev(ch: str) -> bool:
    return "ऀ" <= ch <= "ॿ"


def devanagari_to_latin(text: str) -> str:
    """Phonetic Latin for Devanagari; every other character is passed through unchanged."""
    text = unicodedata.normalize("NFC", text).translate(_DIGITS)
    # the nukta dot (ज़ ड़ फ़ ...) only refines a sound: drop it and read the base letter. The one-character forms are listed in _CONS.
    text = text.replace(_NUKTA, "")
    out = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in _CONS:
            out.append(_CONS[ch])
            nxt = text[i + 1] if i + 1 < n else ""
            if nxt in _MATRAS:
                out.append(_MATRAS[nxt])
                i += 2
                continue
            if nxt == _VIRAMA:
                i += 2
                continue
            # inherent 'a', dropped at the end of a word (schwa deletion)
            end_of_word = (nxt == "" or not _is_dev(nxt) or nxt in _NASAL)
            if not end_of_word:
                out.append("a")
            i += 1
            continue
        if ch in _VOWELS:
            out.append(_VOWELS[ch])
        elif ch in _MATRAS:
            out.append(_MATRAS[ch])
        elif ch in _NASAL:
            out.append(_NASAL[ch])
        elif ch in (_VIRAMA, _NUKTA, "ऽ", "॥", "।"):
            out.append(" " if ch in ("॥", "।") else "")
        else:
            out.append(ch)
        i += 1
    return "".join(out)


_KEEP = re.compile(r"[^a-z0-9./:\- ]+")


def fold_roman(s: str) -> str:
    """Phonetic folding so that khoon/khun, peela/pila, bachcha/bacha spellings meet. Applied to questions AND to every rule word."""
    s = s.replace("chh", "ch")
    for a, b in (("aa", "a"), ("ee", "i"), ("ii", "i"), ("oo", "u"), ("uu", "u"), ("ai", "e"), ("ei", "e")):
        s = s.replace(a, b)
    s = s.replace("w", "v")
    s = re.sub(r"(ch|sh|kh|gh|th|dh|bh|jh)\1", r"\1", s)  # bachcha -> bacha
    s = re.sub(r"([a-z])\1+", r"\1", s)  # sabb -> sab
    return s


_ESC_TOKEN = re.compile(r"(\\.|\[[^\]]*\]|\(\?[:=!<]+|[0-9{},*+?|()^$.])")


def fold_pattern(p: str) -> str:
    """fold_roman for the letters of a regex source, leaving escapes (\\b, \\d, ...) and character classes alone."""
    out, i = [], 0
    for m in _ESC_TOKEN.finditer(p):
        out.append(fold_roman(p[i:m.start()]))
        out.append(m.group(0))
        i = m.end()
    out.append(fold_roman(p[i:]))
    return "".join(out)


_TOKEN_MAP = {"nahin": "nahi", "nhi": "nahi", "nehi": "nahi", "nahe": "nahi", "nahn": "nahi"}


def normalize(text: str) -> str:
    t = unicodedata.normalize("NFC", text or "").lower()
    t = devanagari_to_latin(t)
    t = t.replace("–", "-").replace("—", "-").replace("−", "-")
    t = re.sub(r"(\d)\s*°\s*", r"\1 ", t)
    t = _KEEP.sub(" ", t)
    t = fold_roman(t)
    t = re.sub(r"(?<![0-9])[.\-:/]+(?![0-9a-z])", " ", t)  # stray separators
    t = re.sub(r"\s+", " ", t).strip()
    return " ".join(_TOKEN_MAP.get(w, w) for w in t.split(" "))
