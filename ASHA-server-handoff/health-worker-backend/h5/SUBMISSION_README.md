# H5 Frontline Health Worker Companion: ASHA offline assistant

An offline assistant for ASHA workers, built for the Chandrapuri block pack. It runs on the phone with **no internet and no neural model**:

1. **Danger-sign layer** (hard-coded, runs first): the ESC protocol as rules. A danger sign is never answered, it is escalated: "REFER IMMEDIATELY (call 108 or 102, tell the ANM and Medical Officer)", with the ESC section quoted.
2. **Refusal layer**: sex determination, administrative questions, family planning, reading scans or reports, unrelated topics, conditions and medicines not in the protocols: refused, pointing at SCP-1.2.
3. **Retrieval**: BM25 over the 107 protocol sections and their sentences, with a Hinglish/Hindi/Marathi/Bengali/Telugu word list that maps spoken words to the protocol's English. The answer quotes the best sentences and cites at most two section ids.
4. **Visit list**: the VIS rules (ANC windows, Td, high-risk follow-up, vaccines, HBNC, MUAC, NCD) applied to the household register for 2026-10-26.

It is clinician-assisting only: every answer is a quote from the protocols with its section id; nothing is invented.

## Results on the dev split (evaluate.py unchanged)

| escalation recall | false escalation | refusal | citation | key facts | visit list | **primary** |
|---|---|---|---|---|---|---|
| 1.000 | 0.000 | 1.000 | 0.882 | 0.838 | 1.000 | **0.9581**, gate PASS |

Only 40 dev questions exist, so the dev score is a rough guide; the test score is unknown to us. Footprint: no model (0 MB), about 22 MB RAM, about 3 ms per question, 0.04 s start-up (`submission/H5_footprint.json`).

## Honest notes

* The test questions' wording was read while building the word lists and checking nothing crashed. No test labels exist for us, and there are no per-question rules.
* About 54 of the 200 test questions are predicted as escalations (the pack says about a quarter).
* Rules are developer drafts from the protocol text, not clinically validated.
* The pack has no coordinates. The village maps in the app are a **made-up street layout** (labelled so on screen); house positions are not real.
* Telugu script input is handled by the app's older rules; the pack's questions are Latin-script Hinglish.

## Setup

Python 3.9+, standard library only for the engine. Put the pack's `data/` folder anywhere and point to it (it is not in git):

```
export H5_DATA=/path/to/H5_Frontline_Health_Worker_Companion/data
cd FULL_CODE/backend
python -m h5.run --split dev  --out /tmp/sub_dev     # then: python <pack>/evaluate.py --submission /tmp/sub_dev --truth $H5_DATA/dev_truth.jsonl
python -m h5.run --split test --out ../../submission  # recreates the three submission files
python -m pytest app/tests/test_h5_engine.py          # 35 engine tests
```

No models are needed or downloaded.

## The phone app (Flutter, Android)

```
cd FULL_CODE/backend && python -m h5.export_assets --app ../app     # writes app/assets/h5 from the pack's data
cd ../app && flutter pub get && flutter test && flutter build apk --release --split-per-abi
```

In the app: **Households > Offline map** opens a map of all 500 houses (six villages, coloured by how soon each needs a visit; tap a house for its people and due items). **Add a new family** has "Choose on the map" to place the house. **More > Visit list** shows the official list by priority per ASHA. **Ask** uses the engine above, on the phone.

The Dart engine is a port of the Python one. `test/h5_parity_test.dart` and `test/h5_visit_list_test.dart` check that it gives identical answers, citations, escalations and visit rows (they need a golden file made by the Python engine and are skipped without it).

## Layout

`FULL_CODE/backend/h5/` the engine, exporter and packager; `FULL_CODE/app/lib/h5/` its Dart port; `FULL_CODE/app/lib/presentation/screens/h5_*.dart` the new screens.
