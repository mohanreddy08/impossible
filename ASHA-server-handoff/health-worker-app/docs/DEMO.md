# Running the demo from this Mac

One command starts the backend, a small local LLM and the Telugu voice pack, and links the phone over the USB cable.

```bash
cd health-worker-backend
scripts/demo_server.sh start     # start (first run creates demo/demo.env with test keys and demo/demo.db with synthetic data)
scripts/demo_server.sh check     # self test: 6 checks (server, login, data, Telugu pack, LLM, AI explanation within 10 s)
scripts/demo_server.sh status
scripts/demo_server.sh stop
scripts/demo_server.sh reset     # stop, delete the demo database, start again with pristine data
```

What runs: the FastAPI backend on port 8800 (API-key login), and its OWN Ollama on port 11500. A normal Ollama on
port 11434 (and whatever models it keeps loaded) is never touched or stopped. Two models, both only on the Mac: `bge-m3` (finds the approved passages in Telugu, English or mixed) and `qwen3:8b` (writes the answer; the only model tried that writes correct Telugu), set in `demo/demo.env` (`DEMO_EMBED_MODEL`, `DEMO_LLM_MODEL`).
The model runs ONLY on the Mac server: nothing of it is inside the app, so the app stays small.

## The phone (one time per phone)
Settings -> Server address `http://127.0.0.1:8800` -> Access key = the `DEMO_WORKER_KEY` line in `health-worker-backend/demo/demo.env` -> Save ->
"Test connection" says the server is available. Switch **Online AI help** ON. Telugu voice: Settings -> "Download Telugu voice" (once).
The cable must stay connected: `demo_server.sh start` runs `adb reverse`, which is how the phone reaches the Mac (the app allows plain http only to 127.0.0.1).
After unplugging/replugging, run `scripts/demo_server.sh start` again (it is safe to repeat) to re-link.

## Demo script (about 3 minutes)
1. **Online.** Ask "What should I do if nobody is at home during a visit?" Spinner "Asking the AI server...", then the card "Explained by your server's AI".
2. **Offline.** Turn Wi-Fi and mobile data off (the header says Offline). Ask the same question: the card appears at once, "Explained on this phone".
   Ask a danger sign ("newborn baby is suffering to breath right now"): High strip and the red alert, no network involved.
3. **Telugu voice offline.** Telugu, tap the mic, say a sentence, stop: the Telugu text appears (about 1 word in 5 can be wrong: check it, as the screen says).
4. **Sync.** Still offline, open the first overdue visit and save it: the header says "1 waiting to sync". Turn the network back on: it says synced, and the
   Mac server's record changes to COMPLETED (`curl -H "X-API-Key: <admin key>" 'http://127.0.0.1:8800/api/v1/visits?household_id=HH-SYN-00193'`).

## Reset between runs
The save in step 4 uses up one demo visit. To start clean on both sides:
1. `scripts/demo_server.sh reset`
2. Phone: Settings -> "Delete all data on this phone" -> confirm.
3. Phone: Settings -> "Load synthetic demo data" (this also brings back the sample protocol text; without it every question says "No verified answer").
4. Phone: More -> Sync centre -> Sync now. Home should show 14 due today, 14 overdue, 25 upcoming, 27 pending referrals.

## What the local model can and cannot do
The server asks `qwen2.5:3b` to explain only the passages the phone found, at temperature 0 (the same answer each time, usually 1 second). It is good in
English but still sometimes adds advice that is not in the passage ("ask a neighbour..."), and its Telugu is poor. Two guards cover that:
- the server refuses an explanation that is in the wrong language or does not stay with the approved passages (`LLM_WRONG_LANGUAGE`, `LLM_NOT_GROUNDED`);
- Telugu questions are not sent to the model at all by default (`DEMO_LLM_TELUGU=false` in `demo/demo.env`): the phone shows the approved Telugu text itself.
In both cases the card says why and shows the approved text. Smaller models were tried and rejected: `gemma3:270m` echoes the prompt and invents advice, `qwen2.5:0.5b`
is weak. After changing the model or the Telugu setting: `scripts/demo_server.sh stop && scripts/demo_server.sh start`.

## Server RAG (Telugu answers)
`POST /api/v1/health-qa/rag` on the server: safety rules first, then bge-m3 retrieval over the approved passages, then the answer. A short approved passage IS the
answer (returned word for word, no model call, instant); only a long passage goes to qwen3:8b, behind guards (language, grounding, doses, 9 s budget) with the
approved text as the fallback. The phone calls it after its own search, only online with AI help on; a danger sign never goes there.
Sample passages are loaded by `scripts/load_sample_protocol.py` (marked TEST_FIXTURE_ONLY). Measured on 22 development questions: 17/18 answered correctly,
4/4 not-covered ones refused. The long-passage (model) path still has to be measured on the real hackathon documents.
**Hackathon dataset:** `scripts/import_protocols.py`, reviewer approval, restart `demo_server.sh` (the vector cache rebuilds itself), then re-run `scripts/telugu_rag_eval.py` with questions from the new data.

## Troubleshooting
- "Test connection" fails: run `scripts/demo_server.sh status` and `check`; re-run `start` to re-link the cable; confirm the key was typed in full.
- Every question says "No verified answer": the sample protocol text is missing (see step 3 of Reset).
- Explanation always says "Explained on this phone": Online AI help is off, no server address is set, the phone is offline, or the model is slow (over 10 s).
- Everything is synthetic data and test keys on one laptop: a demo, not a deployment.
