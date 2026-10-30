"""Builds the offline Telugu speech model pack that the backend serves to phones.

    python scripts/shrink_whisper_decoder.py --src DIR_WITH_ORIGINAL_PACK --out DIR      # once: 90 MB decoder -> 30 MB
    python scripts/build_telugu_asr_pack.py --src DIR [--out models/te-asr]

DIR must contain:  encoder.int8.onnx  decoder.int8.onnx  tokens.txt
  Whisper-tiny fine-tuned for Telugu (vasista22/whisper-telugu-tiny), sherpa-onnx int8 export, Apache-2.0:
  https://huggingface.co/ippocode/indic-asr-onnx  (models/whisper-tiny-te/)
  The decoder is the output of shrink_whisper_decoder.py (token-embedding table stored as int8; the published one is 90 MB).
Writes the files plus manifest.json (size + SHA-256 per file). Re-run after replacing any file.
"""
import argparse, hashlib, json, shutil
from pathlib import Path

FILES = ["encoder.int8.onnx", "decoder.int8.onnx", "tokens.txt"]


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", default="models/te-asr")
    a = ap.parse_args()
    src, out = Path(a.src), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    files = []
    for n in FILES:
        if not (src / n).is_file():
            raise SystemExit(f"missing {src / n}")
        if src.resolve() != out.resolve():
            shutil.copyfile(src / n, out / n)
        files.append({"name": n, "size": (out / n).stat().st_size, "sha256": sha256(out / n)})
    manifest = {
        "id": "whisper-tiny-telugu-int8-emb8",
        "language": "te",
        "sample_rate": 16000,
        "features": 80,
        "licence": "Apache-2.0 (OpenAI Whisper architecture; vasista22/whisper-telugu-tiny fine-tune; sherpa-onnx int8 export by ippocode)",
        "source": "https://huggingface.co/ippocode/indic-asr-onnx/tree/main/models/whisper-tiny-te",
        "files": files,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("wrote", out / "manifest.json", "-", sum(f["size"] for f in files) / 1_000_000, "MB")


if __name__ == "__main__":
    main()
