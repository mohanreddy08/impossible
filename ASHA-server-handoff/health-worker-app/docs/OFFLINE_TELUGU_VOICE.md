# Offline Telugu voice (the app's own model)

Many phones have no Telugu offline speech pack (the Google pack list on the two phones we tried offers no Telugu). So the app
carries its own offline Telugu recogniser. The phone downloads it **once** from the project's server, then recognises Telugu
with no internet and nothing leaves the phone.

## What it is
Whisper-tiny fine-tuned for Telugu, int8, run with ONNX Runtime on the phone (WhisperAsr.kt): the app computes the 80-band log-mel spectrogram
itself, runs the encoder, then the decoder token by token (greedy, key/value cache) and turns the token bytes into text. Audio stays in memory.

| Part | Size | Source | Licence |
|---|---|---|---|
| `encoder.int8.onnx` | 12.9 MB | `ippocode/indic-asr-onnx`, `models/whisper-tiny-te/` (sherpa-onnx int8 export of `vasista22/whisper-telugu-tiny`) | Apache-2.0 |
| `decoder.int8.onnx` | 30.3 MB (published: 89.8 MB) | same, with the 51865 x 384 token-embedding table (79.7 MB of full-precision floats) stored as int8 with per-row scales: `scripts/shrink_whisper_decoder.py` | Apache-2.0 |
| `tokens.txt` | 0.8 MB | same | Apache-2.0 |

Pack: **44.0 MB** (published pack: 103.6 MB). It replaced the AI4Bharat IndicConformer pack (138 MB) on request, to save space. Runtime: ONNX Runtime for Android 1.31.1.
`tool/whisper_reference.py` is a numpy/onnxruntime decoder with the same steps, used to check the phone; `tool/whisper_eval_fleurs.py` scores a pack on FLEURS.

## Accuracy and speed (measured, not assumed)
FLEURS Telugu (read sentences, clean audio, first 60 clips, about 11 s each), word error rate (WER) / character error rate (CER):

| Model | WER | CER |
|---|---|---|
| IndicConformer int8 (previous pack, 138 MB) | 20.7% | 5.8% |
| Whisper-tiny-te, published pack, Mac | 38.2% | 13.8% |
| Whisper-tiny-te, 44 MB pack, Mac (full ONNX Runtime optimisation) | 39.1% | 15.4% |
| Whisper-tiny-te, 44 MB pack, at the optimisation level the phone effectively uses | **44.8%** | **19.2%** |

With noise added (white noise + 120 Hz hum + 3 short bursts at 10 dB, 40 clips) the published Whisper pack scored 57.7% WER against 27.5% for IndicConformer: Whisper
was not better in noise in this test. Synthetic noise and read speech are not field recordings; mixed Telugu-English speech was not tested.
**Why the phone is worse than the Mac:** with the same spectrogram (identical to 4e-6) the Android build of ONNX Runtime gives an encoder output that differs by about 27%
(relative RMS) from the Mac build's default; the Mac only matches the phone when graph optimisation is lowered. Setting full optimisation on Android did not change it.
**Speed on the test phone (vivo-class 64-bit phone, 4 threads):** 6 to 11 s per 4 to 11 s clip (the encoder always processes 30 s of padded audio). Memory about 310 MB (total PSS) while loaded.
Slower phones (for example 2 GB Cortex-A55 devices) were not tested and will be slower still.
Recognised text only fills the question box: the worker checks it and presses Check, and the safety rules run on what is submitted.

## Serving it (server)
1. `python scripts/shrink_whisper_decoder.py --src <folder with the 3 published files> --out <folder2>` (needs `pip install onnx numpy`), then put the 3 files in a folder.
2. `python scripts/build_telugu_asr_pack.py --src <folder2>` (in `health-worker-backend`): copies them to `models/te-asr/` and writes
   `manifest.json` with each file's SHA-256. The folder is large and is not in git.
3. Endpoints (API key required like the rest): `GET /api/v1/speech-models/te` (manifest) and
   `GET /api/v1/speech-models/te/files/{name}` (supports HTTP Range, so a dropped download resumes).
   `SPEECH_MODEL_DIR` overrides the folder.

## On the phone
Settings -> "Telugu voice for this app (offline)" -> Download (about 44 MB, use Wi-Fi). Nothing downloads until that tap.
Files are checked against the manifest's SHA-256; a damaged file is discarded and the pack is not marked ready. After that,
Ask -> Telugu -> mic works offline. Voice order for Telugu: the phone's own offline pack if it has one, then this model, then the
phone's online speech service only if "Online speech" is switched on and there is internet, otherwise the app says why and the
worker types.

## Tried with a spoken voice (with the previous IndicConformer model; not repeated for Whisper)
Eight Telugu health sentences: most came out exactly or with one letter off (e.g. the bleeding, not-feeding and breathing sentences),
and each got the right alert. Some words were garbled (ఊపిరి -> ఊపిది, ఫిట్స్ -> థిట్స్, శ్వాస -> శవాస on one take): a keyword safety rule cannot see
a word the recogniser wrote wrongly. Three consequences, all in the app now:
- the breathing, fits, unconscious and bleeding patterns accept the common spelling variants (స్వాస, శవాస, మూర్చ, సృహ, రక్తశ్రావం ...);
- "ఊపిరి ఆడటం లేదు" (the breath is not coming = cannot breathe) is a danger sign: the word లేదు is part of the symptom, but the negation rule used to
  read it as "no problem", so it was shown as no danger sign; it now escalates;
- when the checked text came from voice and no danger sign was found, the screen says the words may be wrong and to fix them and check again.
Still true: a badly misheard key word can hide a danger sign. A synthetic voice is not a real worker; measure with real recordings. The new patterns are
draft and need the same clinical review as the rest of the rule set.

## Putting the model on a phone from this Mac
The pack lives on the Mac in `health-worker-backend/models/te-asr/`. The phone fetches it with the app's own Download button:
1. Start the backend on the Mac (a dev setup with `AUTH_MODE=disabled`, e.g. `uvicorn app.main:app --port 8798`).
2. Connect the phone by USB and run `adb reverse tcp:8798 tcp:8798`, so the phone reaches the Mac as `http://127.0.0.1:8798` (the app allows plain http only for that address).
3. On the phone: Settings -> Server address `http://127.0.0.1:8798` -> Save -> "Download Telugu voice". It takes a few seconds over USB and the card then says Ready. The phone can stay OFFLINE (Wi-Fi and data off) while doing this, so nothing syncs.
4. Clear the server address again if it should not stay set. The pack stays on the phone and works with no server and no internet.

## Release build: keep ONNX Runtime's class names
ONNX Runtime's native code finds its own Java classes by name. The release build's shrinker (R8) used to rename them, which aborted the app the first
time the model ran ("JNI DETECTED ERROR ... java_class == null"); debug builds are not shrunk, so only release builds could crash. `android/app/proguard-rules.pro`
keeps them. After every release build run `bash tool/check_release_keeps_ort.sh`: it fails if any `ai.onnxruntime` class was renamed.

## Build size
ONNX Runtime adds one native library per CPU type. `flutter build apk --release --target-platform android-arm,android-arm64`
gives about 138 MB (ONNX Runtime alone is 34 MB per CPU type); `--split-per-abi` gives one smaller APK per CPU type; an app bundle (Play Store) splits automatically.

## Testing without speaking
The hidden Voice Test screen (see VOICE_TEST.md) has a button that runs `files/test.wav` (16 kHz mono 16-bit WAV, copied with adb) through the on-device model and
writes `files/test_out.txt` (milliseconds, then the text). A debuggable build also registers a broadcast doing the same. Tests: `test/telugu_voice_test.dart`
(download, resume, checksum, routing, screens), `app/tests/test_speech_models.py` (server).

## Why a Telugu question can get "No verified answer" offline
1. The phone only holds the small SAMPLE document (64 passages, English + Telugu: danger signs, hygiene, app workflow). A real question about fever,
   diet, vaccines etc. has no approved text to answer from, offline or online. Real approved protocols must be installed first.
2. A question that names a symptom without detail (e.g. "జ్వరం వస్తే ఏమి చేయాలి") gets "Medium: more details needed" from the safety rules before any search.
3. The keyword search used to ignore too few Telugu question words (ఏమిటి, ఏమి...) and matched only identical spellings, so "చేతులు ఎలా కడుక్కోవాలి" missed the
   passage that says కడుక్కోండి. It now ignores more Telugu question words and matches Telugu words with the same stem (5+ letters, 70% of the shorter word).
4. With "Online AI help" on and no server set, a question with no local match says "Cannot verify offline ... no server address", which reads like a failure.
5. A recogniser slip in the key word (గడుకోవాలి for కడుక్కోవాలి) still defeats the search: fix the words in the box and press Check again.
