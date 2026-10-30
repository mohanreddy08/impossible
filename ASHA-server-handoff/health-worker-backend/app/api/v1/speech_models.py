"""Offline Telugu speech-to-text model pack, served once to each phone.

The phone downloads these files a single time (on the worker's tap), checks their SHA-256 against the manifest, and then
recognises Telugu speech fully on the device. Files live in settings.speech_model_dir (built by scripts/build_telugu_asr_pack.py);
they are large and are NOT part of the code or the database. Requests are authenticated like every other endpoint.
"""
import json
import re
from pathlib import Path

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse

from app.core.config import Settings, get_settings
from app.core.errors import NotFound
from app.core.security import Principal, get_principal

router = APIRouter(prefix="/speech-models", tags=["speech-models"])

_NAME = re.compile(r"^[A-Za-z0-9._-]{1,80}$")


def _manifest(st: Settings) -> dict:
    f = Path(st.speech_model_dir) / "manifest.json"
    if not f.is_file():
        raise NotFound("no Telugu speech model is installed on this server")
    return json.loads(f.read_text(encoding="utf-8"))


@router.get("/te")
def telugu_manifest(_: Principal = Depends(get_principal), st: Settings = Depends(get_settings)):
    """Model id, licence, and every file with its size and SHA-256 (the phone verifies each file after download)."""
    m = _manifest(st)
    for f in m["files"]:
        f["url"] = f"/api/v1/speech-models/te/files/{f['name']}"
    return m


@router.get("/te/files/{name}")
def telugu_file(name: str, _: Principal = Depends(get_principal), st: Settings = Depends(get_settings)):
    """One model file. Supports HTTP Range, so an interrupted download on a poor connection can resume."""
    # only names listed in the manifest can be fetched (no path traversal, no stray files)
    if not _NAME.match(name) or name not in {f["name"] for f in _manifest(st)["files"]}:
        raise NotFound("file not found")
    p = Path(st.speech_model_dir) / name
    if not p.is_file():
        raise NotFound("file not found")
    return FileResponse(p, media_type="application/octet-stream", filename=name)
