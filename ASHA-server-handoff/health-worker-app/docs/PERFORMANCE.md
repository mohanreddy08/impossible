# Performance and size - measured vs pending

## Measured (this build, `flutter build apk --release --split-per-abi`)
| Item | Value |
|---|---|
| app-arm64-v8a-release.apk | 20,061,841 bytes (19.1 MiB); Play-style download size 9,229,766 bytes |
| app-armeabi-v7a-release.apk | 17,650,781 bytes |
| app-x86_64-release.apk | 21,480,077 bytes (emulator only) |
| Largest parts (arm64) | libflutter.so 11.7 MB (engine), libapp.so 7.1 MB (Dart code), demo_seed.json 185 KB (12.7 KB compressed) |
| Material icon font | tree-shaken from 1.6 MB to 10.6 KB |
Possible further savings (not done): drop the unused `cupertino_icons` (~116 KB), ship the demo seed only in debug flavours.

## PENDING - needs a physical entry-level Android device (none connected: `adb devices` is empty)
Installed size, cold-start time, resident memory (idle / planner with 80 households / after 1,000 scrolls), screen-load latency on a 2G-like link,
battery effect of auto-sync. **No figures are claimed.** Suggested procedure: `flutter run --profile` + DevTools Performance/Memory,
`adb shell dumpsys meminfo in.healthcompanion.health_companion`, `adb shell am start -W`, throttled network via the emulator `-netspeed gsm`.

## Design choices that bear on performance (verified by tests, not by stopwatch)
Registers are read through SQL `LIMIT/OFFSET` pages of 30 (paging tests); tabs are built lazily; no animation beyond default route transitions;
JSON seed parsing (185 KB) happens only on an explicit "load demo" tap; protocol index is built from approved rows on demand.


## Scroll performance on real devices (measured 14 Oct 2026)
How to run: `flutter drive --no-dds --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart --profile -d <device>`
(optional: `--dart-define=PERF_SERVER=<url> --dart-define=PERF_KEY=<key>` to sync real data first; an admin key gives 500 households in 3 villages, which is what makes the Village filter appear). It scrolls every page up and down and writes frame build/raster times per page. **Use `--profile`: debug builds are much slower than real use.** The test installs its own copy and removes it afterwards, so reinstall the app after running it.
- **vivo V2141 (real phone), profile build, 80 households:** every page smooth. Worst frame build 5-16 ms, worst raster 4-24 ms; 1 slow frame in about 1,300 on the first run. A second run on a freshly installed copy was noisier (worst build 23-40 ms on several pages, 14-19 slow-build frames per page), so expect occasional hitches on that phone; it did not repeat on the first run.
- **Android emulator, profile build, 500 households / 2,034 visits / 3 villages:** all pages smooth, including Households filtered by village and by village + status (worst build 3-4 ms, worst raster 5-6 ms). Sync page: 8 slow-raster frames (worst 19.6 ms).
- A **debug** build on the phone was noticeably laggy; that is expected and is not what workers run. Release APK: `flutter build apk --release`.
- Not measured: a release build through the harness (profile is the closest equivalent), long sessions, low-RAM phones, 120 Hz scrolling (frames were judged against a 16.6 ms budget).
- Changes made from this review: date formatters are now cached instead of being rebuilt for every list card on every redraw.

## Sync fixes found while testing with 500 households
- Switching login (e.g. worker -> admin) or server on a phone kept the old sync position, so only the newest changes were pulled and referrals arrived without their visits (a `FOREIGN KEY` error stopped sync). The app now resets its sync position when the login or server changes (it stores a one-way tag, never the key), and a missing-parent error also resets it so the next sync repairs itself. Three tests cover this.


## Footprint of the offline Ask path (measured 28 Oct 2026, Apple M-series Mac, 10 cores, 16 GB, CPU only)
Reproduce: `OLLAMA=127.0.0.1:11500 health-worker-backend/.venv/bin/python health-worker-backend/scripts/benchmark_footprint.py --llm`
(Ollama option `num_gpu=0` forces CPU. Nothing needs the internet: models and data are local.)

| Item | Value |
|---|---|
| Danger-sign layer (deterministic rules, no model) | a JSON file of regular expressions, runs on the phone and the server before anything else, well under 1 ms |
| Retrieval model `bge-m3`: size on disk / memory loaded | 1,158 MB / 1,244 MB |
| Question embedding, CPU only (22 Telugu questions) | median 20 ms, p95 24 ms |
| Whole answer path with the approved passage as the answer (no LLM) | median < 0.1 s, max < 0.1 s once the passage vectors are cached (first question after a restart about 0.4 s) |
| Optional LLM `qwen3:8b` (only for long passages): size on disk / memory loaded | 5,225 MB / 5,946 MB |
| LLM generation on CPU, Telugu | about 7 to 14 tokens/s (two runs: 13.8 and 7.3); a 48-token Telugu answer took 10.8 to 14.2 s |
| Phone app (release, vivo/Realme-class phone) | start 0.34 s; about 172 MB memory (PSS) idle; release APKs, one per phone type (`flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64`): 64-bit ARM 55.6 MB, 32-bit ARM 43.2 MB, no x86 (arm64: ONNX Runtime 34 MB, Flutter engine 11.7 MB, app code 8 MB); the 131 MB offline Telugu speech model is NOT in the APK, it is downloaded once from the server. Before the 32-bit and x86 copies were left out the APK was 138.5 MB |

Reading it: the answer path that wins on efficiency is retrieval plus the approved passage word for word (about 1.2 GB, about 20 ms, no large model). The 8B
model is 5x the memory and cannot meet a 10-second limit on CPU for long answers, so it is optional and every answer has the approved text as the fallback.
Not measured: a CPU-only server without Apple silicon, and sustained load.

## Danger-sign detection (rules v0.3.0-draft)
- `scripts/evaluate_safety.py`: 142 supplied cases, 48 of 48 escalations detected, no false positives.
- `scripts/evaluate_danger_variants.py` (80 spoken, misspelled, transliterated and negated phrases written by the developer, including "bleeding in third
  trimester" and the "దాగట్లేదు" slip): 67 of 67 escalations detected, all 80 correct. The phone runs the same rules (`test/danger_variants_test.dart`).
  These phrases were used to write the rules, so they show coverage, not a blind test; the organisers' set is the real test.
- Any bleeding in pregnancy or after delivery now escalates (not only "heavy"), negated forms do not. Rules remain a developer draft, not clinically reviewed.

## Screen sizes (checked on a real phone, 28 Oct 2026)
- Portrait phone: unchanged. Landscape phone (2720 x 1224 px): the header becomes a single compact row and the bottom bar puts icon and label side by side, so the
  content gets most of the screen.
- Tablet: content is a centred column at most 840 dp wide (the bottom bar at most 640 dp); the gradient header stays full width. Checked by emulating a 1600 x 2560
  screen (`adb shell wm size 1600x2560` + `wm density 240`) in portrait and landscape; reset afterwards with `wm size reset`, `wm density reset`.
  Not checked on a physical tablet.
- Rotation works (no orientation lock); the 32-bit ARM APK was inspected (ARM EABI5 libraries, minSdk 24) but not run: the test phone is 64-bit only.
