"""Synthesize the voiceover line by line with Kokoro (offline neural TTS),
lay the lines out inside each scene window and write build/vo.wav plus
build/cues.json (absolute start/end of every line, used by the scenes)."""
import json, os, sys
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.environ.get("KOKORO_DIR", "/tmp/claude-0/tts")
SR = 24000
TOTAL = 180.0
LEAD, TAIL, GAP_MIN, GAP_MAX = 0.45, 0.5, 0.28, 1.5

script = json.load(open(os.path.join(HERE, "vo_script.json")))
k = Kokoro(os.path.join(MODEL_DIR, "kokoro-v1.0.onnx"), os.path.join(MODEL_DIR, "voices-v1.0.bin"))


def trim(a, thr=0.004):
    idx = np.where(np.abs(a) > thr)[0]
    if len(idx) == 0:
        return a
    s, e = max(idx[0] - int(0.02 * SR), 0), min(idx[-1] + int(0.06 * SR), len(a))
    return a[s:e]


def synth(text, speed):
    a, sr = k.create(text, voice=script["voice"], speed=speed, lang="en-us")
    assert sr == SR
    return trim(np.asarray(a, dtype=np.float32))


out = np.zeros(int(TOTAL * SR), dtype=np.float32)
cues = {}
for sc in script["scenes"]:
    speed = script["speed"]
    tail = sc.get("tail", TAIL)
    avail = sc["end"] - sc["start"] - LEAD - tail
    while True:
        clips = [synth(t, speed) for t in sc["lines"]]
        total = sum(len(c) for c in clips) / SR
        n = len(clips)
        need = total + GAP_MIN * (n - 1)
        if need <= avail or speed > 1.25:
            break
        speed += 0.04
        print(f"scene {sc['id']}: too long ({need:.1f}s > {avail:.1f}s), speed -> {speed:.2f}")
    gap = min(GAP_MAX, (avail - total) / max(n - 1, 1)) if n > 1 else 0
    gap = max(gap, GAP_MIN)
    used = total + gap * (n - 1)
    lead = LEAD + max(0.0, (avail - used) * 0.35)
    t = sc["start"] + lead
    cues[sc["id"]] = []
    for text, c in zip(sc["lines"], clips):
        i = int(t * SR)
        out[i:i + len(c)] += c
        cues[sc["id"]].append([round(t, 3), round(t + len(c) / SR, 3), text])
        t += len(c) / SR + gap
    print(f"scene {sc['id']}: speech {total:.1f}s / window {sc['end']-sc['start']}s, gap {gap:.2f}, speed {speed:.2f}, ends {t-gap:.2f}")

os.makedirs(os.path.join(HERE, "build"), exist_ok=True)
sf.write(os.path.join(HERE, "build", "vo.wav"), out, SR)
json.dump(cues, open(os.path.join(HERE, "build", "cues.json"), "w"), indent=1)
words = sum(len(l.split()) for s in script["scenes"] for l in s["lines"])
print("words:", words)
