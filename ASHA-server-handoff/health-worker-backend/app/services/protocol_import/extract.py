"""Page extraction for protocol source files. Exact text is preserved (only CRLF -> LF); nothing is rewritten or 'cleaned'.

Supported: .txt/.md (pages separated by form-feed '\\f' or by a line '[[PAGE n]]'), .pdf (pypdf, one entry per PDF page).
Limits (documented, not hidden): scanned PDFs have no text layer (reported as warnings, no OCR); Indic-script PDFs can extract
badly depending on how the font was embedded - for Telugu sources prefer a text/JSONL export that a human has checked.
PDF page numbers are physical page indexes; printed page labels can be supplied via DocumentMeta.page_offset."""
import os
import re
from dataclasses import dataclass, field
from typing import List, Optional

_MARK = re.compile(r"^\[\[PAGE\s+(\d+)\]\]\s*$", re.M)


@dataclass
class Page:
    number: Optional[int]          # None when the source gives no page information (never guessed)
    text: str


@dataclass
class Extraction:
    pages: List[Page]
    warnings: List[str] = field(default_factory=list)


def _norm(t: str) -> str:
    return t.replace("\r\n", "\n").replace("\r", "\n")


def extract_pages(path: str) -> Extraction:
    ext = os.path.splitext(path)[1].lower()
    if ext in (".txt", ".md"):
        text = _norm(open(path, encoding="utf-8").read())
        if _MARK.search(text):
            parts = _MARK.split(text)                       # ['pre', '1', 'text', '2', 'text', ...]
            pages = [Page(int(parts[i]), parts[i + 1].strip("\n")) for i in range(1, len(parts) - 1, 2)]
            pre = parts[0].strip()
            warn = ["text before the first [[PAGE n]] marker was ignored"] if pre else []
            return Extraction(pages, warn)
        if "\f" in text:
            return Extraction([Page(i, p.strip("\n")) for i, p in enumerate(text.split("\f"), 1) if p.strip()])
        return Extraction([Page(None, text.strip("\n"))], ["no page markers found: page_number is unknown for every passage"])
    if ext == ".pdf":
        from pypdf import PdfReader
        reader = PdfReader(path)
        pages, warn = [], []
        for i, pg in enumerate(reader.pages, 1):
            t = _norm(pg.extract_text() or "")
            if not t.strip():
                warn.append("page %d has no extractable text (scanned image? OCR is not performed)" % i)
                continue
            pages.append(Page(i, t))
        return Extraction(pages, warn)
    raise ValueError("unsupported file type %r (use .txt, .md or .pdf; use import_datasets for JSONL passages)" % ext)
