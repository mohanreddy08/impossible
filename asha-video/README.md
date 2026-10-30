# ASHA explainer video (180 s, 1920x1080, 30 fps)

Motion-graphics explainer for the hackathon jury, built the Hyperframes way:
every scene is HTML/CSS, a deterministic `render(t)` function draws the frame at
time `t`, and headless Chromium screenshots each of the 5,400 frames into ffmpeg.
No stock footage. All data on screen is made up (HH-SYN-xxxxx codes, masked phone numbers).

Output: `out/asha_explainer.mp4`

## Pipeline

| Step | File | What it does |
|---|---|---|
| 1 | `vo_script.json`, `tts.py` | Voiceover lines per scene (423 words). Offline Kokoro TTS (`af_heart`), one clip per line, laid out inside each scene window. Writes `build/vo.wav` and `build/cues.json` (start/end of every line). |
| 2 | `index.html`, `style.css`, `app.js` | The 11 scenes. Animation times are written against voice cues (`data-in="c2+0.5"` = 0.5 s after line 2 of the scene starts), so picture and voice stay in sync. Taps (`data-tap`) draw a ripple and log a click; red alerts (`data-whoosh`) log a whoosh. |
| 3 | `render.js` | Playwright renders frames in 4 parallel pages, pipes PNGs to x264. `node render.js preview 12.5 61` writes stills to `build/preview/` for checking. |
| 4 | `audio.py` | Generates a soft ambient pad (no lyrics), soft clicks and a low whoosh, puts the music 12 dB under the speech RMS, and mixes to `build/mix.wav`. |
| 5 | `build.sh` | Runs everything and muxes `out/asha_explainer.mp4`. |

Requirements: Python 3 with `kokoro-onnx soundfile scipy numpy`, the Kokoro model files
(`kokoro-v1.0.onnx`, `voices-v1.0.bin`, from the kokoro-onnx GitHub release) in `$KOKORO_DIR`,
Node with Playwright + Chromium, ffmpeg. Fonts: Inter (system) and Noto Sans Telugu (`assets/`).

## Scene timing

| # | Time | Scene |
|---|---|---|
| 1 | 0:00–0:12 | Why ASHA is needed |
| 2 | 0:12–0:24 | How it is done today |
| 3 | 0:24–0:34 | What ASHA does |
| 4 | 0:34–0:58 | All features, end to end |
| 5 | 0:58–1:20 | Voice input and the Ask page |
| 6 | 1:20–1:38 | The safety layer |
| 7 | 1:38–1:56 | The AI agent and where it runs |
| 8 | 1:56–2:20 | Telugu voice: what we tested, why Whisper |
| 9 | 2:20–2:38 | App size, data and devices |
| 10 | 2:38–2:50 | How we tested |
| 11 | 2:50–3:00 | Honest limits and close (last 2 s hold still) |

## Claims guard-rails followed
- Safety rules shown as a developer draft, not clinically validated.
- No 100% accuracy claims; all numbers are scoped to our own test sets.
- 1 GB / 2 GB / 32-bit phones shown as not tested / built, not run.
- The answer-writing AI is shown on the Mac server; only Whisper and the safety rules run on the phone.
- Whisper is described as chosen for size, not accuracy.
- No real logos, names, patients or phone numbers.
