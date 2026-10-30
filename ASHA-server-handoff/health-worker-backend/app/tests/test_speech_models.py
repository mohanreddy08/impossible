import hashlib
import json

import pytest

KEYS = "worker|WRK-SYN-001|wk-one-key;admin||admin-key"


def _pack(tmp_path):
    files = {"model.int8.onnx": b"M" * 5000, "vocab.txt": b"<unk> 0\n", "nemo80.onnx": b"P" * 100}
    for n, b in files.items():
        (tmp_path / n).write_bytes(b)
    (tmp_path / "secret.txt").write_text("not in the manifest")
    (tmp_path / "manifest.json").write_text(json.dumps({
        "id": "test", "language": "te", "blank_id": 256,
        "files": [{"name": n, "size": len(b), "sha256": hashlib.sha256(b).hexdigest()} for n, b in files.items()]}))
    return files


def test_manifest_and_download_with_resume(make_client, tmp_path):
    files = _pack(tmp_path)
    c = make_client(auth_mode="api_key", api_keys=KEYS, speech_model_dir=str(tmp_path))
    h = {"X-API-Key": "wk-one-key"}
    m = c.get("/api/v1/speech-models/te", headers=h).json()
    assert [f["name"] for f in m["files"]] == list(files)
    f = m["files"][0]
    assert f["url"].endswith("/te/files/model.int8.onnx") and f["size"] == 5000
    full = c.get(f["url"], headers=h)
    assert full.status_code == 200 and full.content == files["model.int8.onnx"]
    assert hashlib.sha256(full.content).hexdigest() == f["sha256"]
    part = c.get(f["url"], headers={**h, "Range": "bytes=4000-"})
    assert part.status_code == 206 and part.content == files["model.int8.onnx"][4000:], "an interrupted download can resume"


def test_requires_a_key(make_client, tmp_path):
    _pack(tmp_path)
    c = make_client(auth_mode="api_key", api_keys=KEYS, speech_model_dir=str(tmp_path))
    assert c.get("/api/v1/speech-models/te").status_code == 401
    assert c.get("/api/v1/speech-models/te/files/vocab.txt").status_code == 401


@pytest.mark.parametrize("name", ["secret.txt", "manifest.json", "..%2Fetc%2Fpasswd", "nope.onnx"])
def test_only_manifest_files_are_served(make_client, tmp_path, name):
    _pack(tmp_path)
    c = make_client(auth_mode="api_key", api_keys=KEYS, speech_model_dir=str(tmp_path))
    r = c.get("/api/v1/speech-models/te/files/" + name, headers={"X-API-Key": "wk-one-key"})
    assert r.status_code == 404


def test_missing_pack_is_a_clean_404(make_client, tmp_path):
    c = make_client(auth_mode="api_key", api_keys=KEYS, speech_model_dir=str(tmp_path / "none"))
    r = c.get("/api/v1/speech-models/te", headers={"X-API-Key": "wk-one-key"})
    assert r.status_code == 404
