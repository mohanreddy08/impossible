"""Multilingual text embeddings from an Ollama server (bge-m3 by default: it understands Telugu, English and mixes of both).

The only place that touches the network for embeddings (replaced in tests). Vectors are kept per passage text in a small cache (memory,
plus a JSON file when RAG_CACHE_PATH is set) so a restart does not re-embed the whole protocol library."""
import hashlib
import json
import math
import os
import threading
from typing import List, Optional, Sequence

import httpx

from app.core.config import Settings


class EmbedUnavailable(Exception):
    """The embedding service did not answer (down, slow, or the model is missing)."""


def _post_embed(payload: dict, timeout: float, base_url: str) -> httpx.Response:
    return httpx.post(base_url.rstrip("/") + "/api/embed", json=payload, timeout=timeout)


def _unit(v: Sequence[float]) -> List[float]:
    n = math.sqrt(sum(x * x for x in v)) or 1.0
    return [x / n for x in v]


def embed(texts: Sequence[str], s: Settings, timeout: Optional[float] = None) -> List[List[float]]:
    """Unit-length vectors for the texts, in order. Raises EmbedUnavailable on any failure."""
    base = s.rag_embed_base_url or s.llm_base_url
    if not base or "api.anthropic.com" in base:
        raise EmbedUnavailable("no embedding server is configured")
    try:
        r = _post_embed({"model": s.rag_embed_model, "input": list(texts)}, timeout or s.rag_embed_timeout_seconds, base)
    except httpx.HTTPError as e:
        raise EmbedUnavailable(type(e).__name__)
    if r.status_code != 200:
        raise EmbedUnavailable("status %d" % r.status_code)
    try:
        vecs = r.json()["embeddings"]
    except (ValueError, KeyError, TypeError):
        raise EmbedUnavailable("bad reply")
    if len(vecs) != len(texts) or not all(vecs):
        raise EmbedUnavailable("wrong number of vectors")
    return [_unit(v) for v in vecs]


_lock = threading.Lock()
_mem: dict = {}
_file_loaded: set = set()


def _key(model: str, text: str) -> str:
    return hashlib.sha256((model + "\x00" + text).encode("utf-8")).hexdigest()


def _load_file(path: str) -> None:
    if path in _file_loaded:
        return
    _file_loaded.add(path)
    try:
        with open(path, encoding="utf-8") as f:
            _mem.update(json.load(f))
    except (OSError, ValueError):
        pass


def _save_file(path: str) -> None:
    try:
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(_mem, f)
        os.replace(tmp, path)
    except OSError:
        pass


def passage_vectors(texts: Sequence[str], s: Settings, timeout: float = 120.0) -> List[List[float]]:
    """Vectors for passage texts, from the cache where possible (raises EmbedUnavailable if a missing one cannot be computed)."""
    with _lock:
        if s.rag_cache_path:
            _load_file(s.rag_cache_path)
        keys = [_key(s.rag_embed_model, t) for t in texts]
        missing = [i for i, k in enumerate(keys) if k not in _mem]
        for start in range(0, len(missing), 16):
            chunk = missing[start:start + 16]
            for i, v in zip(chunk, embed([texts[i] for i in chunk], s, timeout)):
                _mem[keys[i]] = v
        if missing and s.rag_cache_path:
            _save_file(s.rag_cache_path)
        return [_mem[k] for k in keys]


def clear_cache() -> None:
    with _lock:
        _mem.clear()
        _file_loaded.clear()
