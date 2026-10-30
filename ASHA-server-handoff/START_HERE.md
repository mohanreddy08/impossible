# ASHA server hand-off (read this first)

This folder is a copy of the private ASHA repo (commit 7e943f2) plus three things git leaves out:

- `h5-pack-data/`  the hackathon pack's data folder (synthetic: protocols, household register, questions) and `evaluate.py`. Set `H5_DATA` to this folder.
- `health-worker-app/assets/h5/`  generated data for the phone app (rules, protocols, register, households, 6 village maps).
- `golden/`  outputs of the Python engine for the parity tests (240 answers, 346 visit rows).

What is where
- `health-worker-backend/`  FastAPI server. Sync contract: `docs/API_CONTRACT.md`, `docs/FLUTTER_INTEGRATION_GUIDE.md`. `h5/` = the protocol engine (stdlib Python).
- `health-worker-app/`  Flutter phone app (do not change its sync contract).
- `health-worker-datasets/`  sample datasets.
- `SERVER_BUILD_PROMPT.md`  the prompt to give the AI that builds the web server.

Quick check on the new computer
    cd health-worker-backend
    python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -r requirements-dev.txt
    H5_DATA=../h5-pack-data .venv/bin/python -m pytest -q          # expect 552 passed, 1 skipped
    H5_DATA=../h5-pack-data .venv/bin/python -m h5.run --split dev --out /tmp/sub
    python3 ../h5-pack-data/evaluate.py --submission /tmp/sub --truth ../h5-pack-data/dev_truth.jsonl   # expect 0.9581

No secrets are included (no demo.env, keys, models or databases). All data is synthetic.

Server + supervisor website (added after the hand-off): read `README.md` (3-command local start, tunnel, Render, phone setup),
`docs/DEMO.md` (3-minute demo) and `docs/SERVER_DESIGN.md` (contract summary, schema, API, test results). Expected now: 594 passed, 1 skipped.
