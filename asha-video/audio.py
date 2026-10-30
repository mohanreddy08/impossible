"""Generate soft ambient music + UI sounds and mix them with the voiceover.
Music is set 12 dB under the voice (RMS of speech vs RMS of music).
Writes build/mix.wav (48 kHz stereo)."""
import json, os
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly, butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(HERE, "build")
SR, DUR = 48000, 180.0
N = int(SR * DUR)
rng = np.random.default_rng(7)
t = np.arange(N) / SR

# ---------- voice ----------
vo, vsr = sf.read(os.path.join(B, "vo.wav"), dtype="float32")
vo = resample_poly(vo, SR, vsr).astype(np.float32)[:N]
vo = np.pad(vo, (0, N - len(vo)))
win = int(0.05 * SR)
frames = vo[: len(vo) // win * win].reshape(-1, win)
fr_rms = np.sqrt((frames ** 2).mean(axis=1))
speech_rms = np.sqrt((fr_rms[fr_rms > 0.01] ** 2).mean())

# ---------- music: slow pad, D major colours, 8 s per chord ----------
def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)

chords = [[50, 57, 61, 66, 69], [47, 54, 59, 62, 66], [43, 55, 59, 62, 66], [45, 52, 57, 61, 64]]  # Dmaj7 Bm7 Gmaj7 A
CH = 8.0
music = np.zeros((N, 2), dtype=np.float64)
for k in range(int(DUR / CH) + 1):
    notes = chords[k % len(chords)]
    s0 = k * CH - 1.5  # overlap for crossfade
    a, b = max(0, int(s0 * SR)), min(N, int((s0 + CH + 3.0) * SR))
    if a >= b:
        continue
    tt = t[a:b] - s0
    L = CH + 3.0
    env = np.clip(tt / 2.5, 0, 1) * np.clip((L - tt) / 2.5, 0, 1)
    env = env ** 1.5
    for j, m in enumerate(notes):
        f = midi(m)
        for det, pan in ((-0.12, 0.3), (0.12, 0.7)):
            ph = 2 * np.pi * (f * (1 + det / 100)) * tt + rng.uniform(0, 6.28)
            w = np.sin(ph) + 0.25 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
            amp = (0.5 if j == 0 else 0.22) * env
            music[a:b, 0] += w * amp * (1 - pan)
            music[a:b, 1] += w * amp * pan
    # soft bell arpeggio, one note every 2 s
    for i in range(4):
        st = k * CH + i * 2.0 + 0.3
        ia = int(st * SR)
        if ia >= N:
            break
        ln = min(int(3.0 * SR), N - ia)
        tb = np.arange(ln) / SR
        f = midi(notes[(i * 2 + 1) % len(notes)] + 12)
        bell = (np.sin(2 * np.pi * f * tb) + 0.3 * np.sin(2 * np.pi * 2.01 * f * tb)) * np.exp(-tb * 1.6) * 0.12
        pan = 0.35 if i % 2 else 0.65
        music[ia:ia + ln, 0] += bell * (1 - pan)
        music[ia:ia + ln, 1] += bell * pan

music = sosfilt(butter(2, 2200, "low", fs=SR, output="sos"), music, axis=0)
# gentle slow swell + fades (fade in 2 s, fade out over the last 4 s)
music *= (0.85 + 0.15 * np.sin(2 * np.pi * t / 23))[:, None]
fade = np.clip(t / 2.0, 0, 1) * np.clip((DUR - t) / 4.0, 0, 1)
music *= fade[:, None]
music_rms = np.sqrt((music[int(3 * SR):int(170 * SR)] ** 2).mean())
music *= (speech_rms * 10 ** (-12 / 20)) / music_rms  # 12 dB under the voice

# ---------- UI sounds ----------
def click():
    ln = int(0.05 * SR)
    tb = np.arange(ln) / SR
    s = np.sin(2 * np.pi * 1700 * tb) * np.exp(-tb * 140) + 0.4 * np.sin(2 * np.pi * 900 * tb) * np.exp(-tb * 90)
    s += 0.15 * rng.standard_normal(ln) * np.exp(-tb * 400)
    return s * 0.5

def whoosh():
    ln = int(1.1 * SR)
    tb = np.arange(ln) / SR
    noise = rng.standard_normal(ln)
    out = np.zeros(ln)
    # sweep a low band-pass over a few blocks
    blk = int(0.02 * SR)
    for i in range(0, ln, blk):
        x = i / ln
        fc = 180 + 650 * np.sin(np.pi * x)
        sos = butter(2, [fc * 0.6, fc * 1.4], "band", fs=SR, output="sos")
        out[i:i + blk] = sosfilt(sos, noise[max(0, i - 2000):i + blk])[-len(noise[i:i + blk]):]
    env = np.sin(np.pi * np.clip(tb / 1.1, 0, 1)) ** 2
    return out * env * 0.9

sfx_list = json.load(open(os.path.join(B, "sfx.json")))
sfx = np.zeros(N)
lvl = {"click": speech_rms * 10 ** (-6 / 20) / 0.18, "whoosh": speech_rms * 10 ** (-8 / 20) / 0.25}
for e in sfx_list:
    s = click() if e["type"] == "click" else whoosh()
    start = e["t"] - (0.55 if e["type"] == "whoosh" else 0.0)  # whoosh peaks as the red alert lands
    ia = int(max(0, start) * SR)
    ln = min(len(s), N - ia)
    sfx[ia:ia + ln] += s[:ln] * lvl[e["type"]]

mix = music.copy()
mix[:, 0] += vo + sfx
mix[:, 1] += vo + sfx
peak = np.abs(mix).max()
mix *= 10 ** (-1.0 / 20) / peak
sf.write(os.path.join(B, "mix.wav"), mix.astype(np.float32), SR)
print(f"speech rms {speech_rms:.4f}, music set to -12 dB, sfx events {len(sfx_list)}, gain {10**(-1/20)/peak:.2f}")
