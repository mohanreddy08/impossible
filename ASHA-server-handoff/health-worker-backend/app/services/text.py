"""Unicode/whitespace normalisation shared by safety and retrieval (pure functions, device-portable)."""
import re
import unicodedata

_INVISIBLE = dict.fromkeys(map(ord, "​‌‍⁠﻿"), None)
_QUOTES = {ord("’"): "'", ord("‘"): "'", ord("“"): '"', ord("”"): '"'}
_TOKEN = re.compile(r"[0-9A-Za-zÀ-ɏఀ-౿]+")


def normalize_text(s: str) -> str:
    s = unicodedata.normalize("NFC", s or "")
    s = s.translate(_INVISIBLE).translate(_QUOTES)
    s = re.sub(r"\s+", " ", s).strip()
    return s.casefold()


def tokenize(s: str):
    return _TOKEN.findall(normalize_text(s))
