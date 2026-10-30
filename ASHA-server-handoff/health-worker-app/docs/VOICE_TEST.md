# Voice Test (hidden screen)

Compares the phone's **online Telugu speech** with the **app's own offline Telugu model** (the 44 MB download in Settings) on 20 health-worker sentences.
For each take it records the transcript, the time after Stop, whether the right danger rule fired and whether Q&A returned the right passage,
and you rate it Correct / Some words wrong / Wrong. Everything goes to a CSV on the phone.

## One-time setup
1. Build and install a release APK with the screen switched on (release keeps the same version code, so `install -r` keeps the phone's data):
   ```bash
   flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --dart-define=VOICE_TEST=true
   adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   ```
   (Debug builds also have the screen, but a debug build cannot be installed over a split release build: Android refuses the "downgrade" and flutter would uninstall the app and wipe its data.)
2. For the offline card: Settings -> Download Telugu voice (about 44 MB, once). Without it that card reports `languageMissing`.
3. Open the screen: More -> Settings -> scroll down -> **long-press "App version"**. The chips show whether the offline model is installed.

## Running a test
- Start the memory sampler on the Mac **before** the first sentence (Ctrl-C when finished):
  ```bash
  tool/voice_test_ram.sh            # writes voice_test_ram.csv: phone clock, total PSS, RSS, once a second
  ```
- For each sentence: **Record** in the online card, read the sentence, **Stop**; then the same in the offline card. Rate each take. Next.
  The two engines cannot share the microphone, so you read each sentence twice (once per engine).
- Run everything **once with internet on, once in airplane mode**. The screen stamps each row with the network state it saw. Online speech
  fails offline (that is a result: it is recorded as an error with no text).
- The Summary button shows the table on the phone. A take rated twice keeps the latest rating.

## Reading the results
```bash
adb pull /sdcard/Android/data/in.healthcompanion.health_companion/files/voice_test.csv
python3 tool/voice_test_summary.py voice_test.csv voice_test_ram.csv
```
Prints, per engine and network: Takes, Correct, Some wrong, Wrong, average ms after Stop, Danger ok, Q&A ok, and peak RAM (the **whole app's** total PSS while that engine was in use).

To start over: `adb shell rm /sdcard/Android/data/in.healthcompanion.health_companion/files/voice_test.csv`.

## Editing the sentences
`assets/voice_test/sentences.json` (rebuild), or put an edited copy on the phone as `voice_test_sentences.json` next to the CSV (no rebuild; the phone copy wins). Each sentence says what should happen: `ESCALATION` + `rule` (a danger rule id), `ANSWER` + `section` (text the top passage's section title must contain), or `OUT_OF_SCOPE`.
`test/voice_test_screen_test.dart` checks that every sentence, typed perfectly, already passes, so a failure on the phone is the speech engine's.

## Notes
- Timing: "ms after stop" is the time from tapping Stop to the final text. If the online service ended the take by itself (after a pause) there is no Stop tap and the value is 0 (the CSV column `ended_by` says `auto`).
- Q&A runs exactly as in the Ask screen, so with internet on it may ask the server; the sentences are chosen to be answered from the phone's own sample passages.
- Audio is never saved by the app; the recorder feeds the recogniser straight from memory.
