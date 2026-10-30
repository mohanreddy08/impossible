#!/usr/bin/env bash
# Full pipeline: voiceover -> frames -> music/SFX mix -> final MP4.
set -euo pipefail
cd "$(dirname "$0")"
python3 tts.py                      # build/vo.wav + build/cues.json
node render.js video 4              # build/video.mp4 + build/sfx.json
python3 audio.py                    # build/mix.wav
mkdir -p out
ffmpeg -y -loglevel error -i build/video.mp4 -i build/mix.wav \
  -map 0:v -map 1:a -c:v copy -c:a aac -b:a 192k -t 180 -movflags +faststart out/asha_explainer.mp4
echo "done: out/asha_explainer.mp4"
