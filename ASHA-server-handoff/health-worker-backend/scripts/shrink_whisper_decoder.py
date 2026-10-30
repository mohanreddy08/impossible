"""Shrinks the Whisper decoder from the published sherpa-onnx pack: its 51865 x 384 token-embedding table is stored as 32-bit floats
(79.7 MB of the 89.8 MB file). Stores it as int8 with one scale per row and puts a DequantizeLinear in front of it (same tensor name,
so every user of it, the lookup and the output projection, is unchanged). Result: decoder 90 MB -> 30 MB, pack 103.6 -> 44.0 MB.
Measured on 60 FLEURS Telugu clips: word error 38.2% -> 39.1% (see docs/OFFLINE_TELUGU_VOICE.md).

    pip install onnx numpy
    python scripts/shrink_whisper_decoder.py --src DIR --out DIR2     # DIR has the three published files; DIR2 gets all three
"""
import argparse, shutil
from pathlib import Path

import numpy as np
import onnx
from onnx import helper, numpy_helper

NAME = "textDecoder.token_embedding.weight"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    src, out = Path(a.src), Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    m = onnx.load(str(src / "decoder.int8.onnx"))
    g = m.graph
    init = next(i for i in g.initializer if i.name == NAME)
    w = numpy_helper.to_array(init).astype(np.float32)
    scale = np.maximum(np.abs(w).max(axis=1), 1e-8) / 127.0
    q = np.clip(np.round(w / scale[:, None]), -127, 127).astype(np.int8)
    g.initializer.remove(init)
    g.initializer.extend([numpy_helper.from_array(q, NAME + "_q8"), numpy_helper.from_array(scale.astype(np.float32), NAME + "_scale")])
    dq = helper.make_node("DequantizeLinear", [NAME + "_q8", NAME + "_scale"], [NAME], name="token_embedding_dequant", axis=0)
    nodes = list(g.node)
    del g.node[:]
    g.node.extend([dq] + nodes)
    onnx.checker.check_model(m)
    onnx.save(m, str(out / "decoder.int8.onnx"))
    for n in ("encoder.int8.onnx", "tokens.txt"):
        shutil.copyfile(src / n, out / n)
    print("mean abs weight error", float(np.abs(q.astype(np.float32) * scale[:, None] - w).mean()))


if __name__ == "__main__":
    main()
