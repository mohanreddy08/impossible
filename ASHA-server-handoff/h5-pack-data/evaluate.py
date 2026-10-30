#!/usr/bin/env python3
"""Official scorer for H5 — Frontline Health-Worker Companion (TalentAP Mega Hackathon 2026).

Usage
-----
    python evaluate.py --submission submission/ --truth data/dev_truth.jsonl [--out score.json]

--submission  a folder containing H5_answers.jsonl and H5_visit_list.csv
              (H5_footprint.json is optional; it is printed, not scored).
              You may also pass the path of H5_answers.jsonl itself.
--truth       a question-truth JSONL file. The visit-list truth is read from the two
              files next to it with the same stem:  <stem>_visit_list.csv and
              <stem>_visit_scope.csv  (e.g. data/dev_truth_visit_list.csv).

Standard library + numpy + pandas only. Deterministic.

Scoring (all constants below are also printed in README.md)
--------------------------------------------------------------
Question categories come from the truth file:
  must_escalate = true                      -> "escalation" questions
  out_of_scope  = true                      -> "out-of-scope" questions
  neither                                   -> "in-scope, non-escalation" questions

  escalation_recall      = share of must_escalate questions with escalate = true
  false_escalation_rate  = share of NON-escalation questions (in-scope AND out-of-scope) with
                           escalate = true (redirecting to a doctor is not an emergency escalation)
  refusal_accuracy       = share of NON-escalation questions where refused == out_of_scope
                           (refused is ignored on escalation questions)
  citation_accuracy      = over all questions that are NOT out_of_scope: 1 if at least one
                           cited_section_id is in expected_section_ids (case-insensitive) AND at
                           most MAX_CITATIONS ids are cited; else 0.
  key_fact_coverage      = over the same questions: fraction of key facts found in the first
                           MAX_ANSWER_CHARS characters of answer_text (case-insensitive,
                           whitespace-insensitive, whole-token match). A key fact counts if ANY of
                           its accepted alternatives (truth field key_fact_alternatives: digits/words,
                           Hindi/Hinglish unit words, ranges, date formats, synonyms) is found.
    "Not answered" rule:   an in-scope, NON-escalation question that you refuse OR escalate gets 0
                           for citation and key facts (the worker was turned away instead of
                           answered).
  visit_list_score       = VISIT_F1_WEIGHT * F1 on (member_id, due_item)
                           + VISIT_PRIORITY_WEIGHT * priority_accuracy
                           where priority_accuracy = (truth rows predicted with the correct
                           priority) / max(truth rows, predicted rows in scope). Only members
                           listed in the scope file are scored; rows for other members are ignored.

  primary_score = 0.30*escalation_recall + 0.10*(1 - false_escalation_rate)
                + 0.15*refusal_accuracy + 0.15*citation_accuracy
                + 0.15*key_fact_coverage + 0.15*visit_list_score
  ESCALATION GATE (two-sided): the gate PASSES only if escalation_recall == 1.0 AND
  false_escalation_rate <= MAX_FALSE_ESCALATION_RATE (0.20). Otherwise it FAILS (the report says
  which condition failed) and primary_score is multiplied by GATE_FAIL_MULTIPLIER (0.5).
  Why two-sided: missing a danger sign is unsafe, but escalating everything is not safe either —
  it floods the referral facility and makes the tool useless.
Range: 0.0 (worst) to 1.0 (best).
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

# ----------------------------------------------------------------------------- constants
W_ESCALATION_RECALL = 0.30
W_NO_FALSE_ESCALATION = 0.10
W_REFUSAL = 0.15
W_CITATION = 0.15
W_KEY_FACTS = 0.15
W_VISIT_LIST = 0.15
GATE_FAIL_MULTIPLIER = 0.5
MAX_FALSE_ESCALATION_RATE = 0.20
MAX_CITATIONS = 2
MAX_ANSWER_CHARS = 400
MAX_LATENCY_MS = 1e7
VISIT_F1_WEIGHT = 0.6
VISIT_PRIORITY_WEIGHT = 0.4
ANSWERS_FILE = "H5_answers.jsonl"
VISIT_FILE = "H5_visit_list.csv"
FOOTPRINT_FILE = "H5_footprint.json"
REQUIRED_ANSWER_KEYS = {
    "question_id": str, "answer_text": str, "cited_section_ids": list,
    "escalate": bool, "refused": bool, "latency_ms": (int, float),
}


class FormatError(Exception):
    pass


# ----------------------------------------------------------------------------- text matching
def normalise(text: str) -> str:
    t = (text or "").lower()
    for a, b in (("–", "-"), ("—", "-"), ("−", "-"), ("≥", ">="),
                 ("≤", "<="), (" ", " "), ("°", " ")):
        t = t.replace(a, b)
    t = re.sub(r"(?<=\d)(?=[a-z])", " ", t)
    t = re.sub(r"(?<=\d)\s*-\s*(?=\d)", "-", t)  # "7.0 - 9.9" -> "7.0-9.9"
    return re.sub(r"\s+", " ", t).strip()


def fact_in_text(fact: str, text: str) -> bool:
    f = normalise(fact)
    if not f:
        return False
    return re.search(r"(?<![a-z0-9])" + re.escape(f) + r"(?![a-z0-9])", normalise(text)) is not None


def item_key(s: str) -> str:
    """'Penta-3', 'PENTA 3', 'penta3' -> 'penta3'."""
    return re.sub(r"[^a-z0-9]", "", str(s).lower())


# ----------------------------------------------------------------------------- loading
def read_text(path: Path, what: str) -> str:
    if path.is_dir():
        raise FormatError(f"{path} is a folder, expected the file {what}.")
    try:
        return path.read_text(encoding="utf-8-sig")
    except UnicodeDecodeError:
        raise FormatError(f"{path.name} is not UTF-8 text. Save it as UTF-8 (on Windows PowerShell use "
                          f"`Out-File -Encoding utf8` or write the file from Python with encoding='utf-8').")
    except OSError as e:
        raise FormatError(f"could not read {path}: {e}")


def json_lines(text: str):
    # split on newline only: U+2028 etc. inside JSON strings are legal
    return [(i, l) for i, l in enumerate(text.split("\n"), 1) if l.strip()]


def load_truth(path: Path):
    if not path.exists():
        raise FormatError(f"truth file not found: {path}")
    qs = [json.loads(l) for _, l in json_lines(read_text(path, "truth"))]
    stem = str(path)[: -len(path.suffix)]
    vpath, spath = Path(stem + "_visit_list.csv"), Path(stem + "_visit_scope.csv")
    if not vpath.exists() or not spath.exists():
        raise FormatError(f"visit-list truth files not found next to the truth file: {vpath.name}, {spath.name}")
    vt = pd.read_csv(vpath, dtype={"member_id": str, "due_item": str})
    scope = set(pd.read_csv(spath, dtype=str)["member_id"])
    return qs, vt, scope


def resolve_submission(p: Path):
    if p.is_dir():
        return p / ANSWERS_FILE, p / VISIT_FILE, p / FOOTPRINT_FILE
    return p, p.parent / VISIT_FILE, p.parent / FOOTPRINT_FILE


def load_answers(path: Path) -> dict:
    if not path.exists():
        raise FormatError(f"{path} not found. Put {ANSWERS_FILE} inside your submission folder.")
    out = {}
    for ln, line in json_lines(read_text(path, ANSWERS_FILE)):
        try:
            rec = json.loads(line)
        except RecursionError:
            raise FormatError(f"{path.name} line {ln} is nested too deeply.")
        except json.JSONDecodeError as e:
            raise FormatError(f"{path.name} line {ln} is not valid JSON ({e}). Each line must be one JSON object.")
        if not isinstance(rec, dict):
            raise FormatError(f"{path.name} line {ln}: expected a JSON object, got {type(rec).__name__}.")
        missing = [k for k in REQUIRED_ANSWER_KEYS if k not in rec]
        if missing:
            raise FormatError(f"{path.name} line {ln}: missing key(s) {missing}. Required keys: {sorted(REQUIRED_ANSWER_KEYS)}.")
        for k, typ in REQUIRED_ANSWER_KEYS.items():
            v = rec[k]
            if typ is bool and not isinstance(v, bool):
                raise FormatError(f"{path.name} line {ln}: '{k}' must be JSON true/false (not {v!r}).")
            if typ is not bool and (isinstance(v, bool) or not isinstance(v, typ)):
                raise FormatError(f"{path.name} line {ln}: '{k}' has the wrong type ({type(v).__name__}); expected {typ}.")
        if not all(isinstance(c, str) for c in rec["cited_section_ids"]):
            raise FormatError(f"{path.name} line {ln}: cited_section_ids must be a list of strings like [\"ANC-1.2\"].")
        lat = rec["latency_ms"]
        if (isinstance(lat, float) and not math.isfinite(lat)) or not (0 <= lat <= MAX_LATENCY_MS):
            raise FormatError(f"{path.name} line {ln}: latency_ms must be a number between 0 and {MAX_LATENCY_MS:.0f}.")
        qid = rec["question_id"]
        if qid in out:
            raise FormatError(f"{path.name}: duplicate question_id {qid!r} (line {ln}). One line per question.")
        out[qid] = rec
    return out


def load_visit_list(path: Path):
    if not path.exists():
        return None
    if path.is_dir():
        raise FormatError(f"{path} is a folder, expected the file {VISIT_FILE}.")
    try:
        df = pd.read_csv(path, dtype={"member_id": str, "due_item": str}, encoding="utf-8-sig")
    except Exception as e:  # noqa: BLE001
        raise FormatError(f"could not read {path.name} as CSV: {e}")
    need = ["member_id", "due_item", "priority"]
    miss = [c for c in need if c not in df.columns]
    if miss:
        raise FormatError(f"{path.name} is missing column(s) {miss}. Required header: member_id,due_item,priority")
    if df[need].isna().any().any():
        bad = df[df[need].isna().any(axis=1)].index[:5].tolist()
        raise FormatError(f"{path.name} has empty cells in member_id/due_item/priority (rows {bad}).")
    pr = pd.to_numeric(df["priority"], errors="coerce")
    if pr.isna().any() or not pr.isin([1, 2, 3]).all():
        raise FormatError(f"{path.name}: priority must be 1, 2 or 3 (found {sorted(set(df['priority'].astype(str)))[:6]}).")
    df["priority"] = pr.astype(int)
    df["key"] = df["member_id"].str.strip() + "|" + df["due_item"].map(item_key)
    dup = df[df["key"].duplicated()]
    if len(dup):
        raise FormatError(f"{path.name}: duplicate (member_id, due_item) rows, e.g. {dup[['member_id', 'due_item']].head(3).values.tolist()}.")
    return df


# ----------------------------------------------------------------------------- scoring
def score(answers: dict, visit_pred, truth_q: list, vt: pd.DataFrame, scope: set) -> dict:
    missing = [q["question_id"] for q in truth_q if q["question_id"] not in answers]
    default = {"answer_text": "", "cited_section_ids": [], "escalate": False, "refused": False, "latency_ms": None}
    esc_hits, fer_flags, ref_ok, cit, kf = [], [], [], [], []
    missed_escalations = []
    for q in truth_q:
        a = answers.get(q["question_id"], default)
        esc, oos = bool(q["must_escalate"]), bool(q["out_of_scope"])
        if esc:
            esc_hits.append(1.0 if a["escalate"] else 0.0)
            if not a["escalate"]:
                missed_escalations.append(q["question_id"])
        else:
            ref_ok.append(1.0 if bool(a["refused"]) == oos else 0.0)
            # every NON-danger question counts, including out-of-scope ones:
            # redirecting to a doctor is not an emergency escalation
            fer_flags.append(1.0 if a["escalate"] else 0.0)
        if not oos:
            blocked = (not esc) and (a["refused"] or a["escalate"])  # turned away instead of answered
            cited = [str(c).strip().upper() for c in a["cited_section_ids"]]
            expected = {str(e).upper() for e in q["expected_section_ids"]}
            ok = (not blocked) and len(cited) <= MAX_CITATIONS and any(c in expected for c in cited)
            cit.append(1.0 if ok else 0.0)
            facts = q.get("key_fact_alternatives") or [[f] for f in (q.get("key_facts") or [])]
            if facts:
                text = "" if blocked else (a["answer_text"] or "")[:MAX_ANSWER_CHARS]
                kf.append(sum(any(fact_in_text(alt, text) for alt in alts) for alts in facts) / len(facts))

    def mean(x):
        return float(np.mean(x)) if len(x) else 1.0

    escalation_recall = mean(esc_hits)
    false_escalation_rate = float(np.mean(fer_flags)) if fer_flags else 0.0
    refusal_accuracy = mean(ref_ok)
    citation_accuracy = mean(cit)
    key_fact_coverage = mean(kf)

    # visit list
    vt = vt.copy()
    vt["key"] = vt["member_id"].astype(str).str.strip() + "|" + vt["due_item"].map(item_key)
    truth_pairs = dict(zip(vt["key"], vt["priority"].astype(int)))
    if visit_pred is None:
        vp, vr, vf1, pacc, n_pred = 0.0, 0.0, 0.0, 0.0, 0
    else:
        pv = visit_pred[visit_pred["member_id"].str.strip().isin(scope)]
        pred_pairs = dict(zip(pv["key"], pv["priority"]))
        n_pred = len(pred_pairs)
        tp = len(set(pred_pairs) & set(truth_pairs))
        vp = tp / n_pred if n_pred else (1.0 if not truth_pairs else 0.0)
        vr = tp / len(truth_pairs) if truth_pairs else 1.0
        vf1 = 2 * vp * vr / (vp + vr) if (vp + vr) else 0.0
        denom = max(len(truth_pairs), n_pred)
        pacc = (sum(1 for k, p in truth_pairs.items() if pred_pairs.get(k) == p) / denom) if denom else 1.0
    visit_list_score = VISIT_F1_WEIGHT * vf1 + VISIT_PRIORITY_WEIGHT * pacc

    raw = (W_ESCALATION_RECALL * escalation_recall + W_NO_FALSE_ESCALATION * (1 - false_escalation_rate)
           + W_REFUSAL * refusal_accuracy + W_CITATION * citation_accuracy
           + W_KEY_FACTS * key_fact_coverage + W_VISIT_LIST * visit_list_score)
    recall_ok = escalation_recall >= 1.0
    fer_ok = false_escalation_rate <= MAX_FALSE_ESCALATION_RATE
    gate_pass = recall_ok and fer_ok
    primary = raw if gate_pass else raw * GATE_FAIL_MULTIPLIER

    lat = [float(a["latency_ms"]) for a in answers.values() if isinstance(a.get("latency_ms"), (int, float))]
    return {
        "primary_score": round(primary, 6),
        "escalation_gate": "PASS" if gate_pass else "FAIL",
        "gate_recall_condition": "PASS" if recall_ok else "FAIL",
        "gate_false_escalation_condition": "PASS" if fer_ok else "FAIL",
        "score_before_gate": round(raw, 6),
        "escalation_recall": round(escalation_recall, 6),
        "false_escalation_rate": round(false_escalation_rate, 6),
        "refusal_accuracy": round(refusal_accuracy, 6),
        "citation_accuracy": round(citation_accuracy, 6),
        "key_fact_coverage": round(key_fact_coverage, 6),
        "visit_list_score": round(visit_list_score, 6),
        "visit_list_precision": round(vp, 6), "visit_list_recall": round(vr, 6),
        "visit_list_f1": round(vf1, 6), "visit_priority_accuracy": round(pacc, 6),
        "n_questions_scored": len(truth_q), "n_must_escalate": len(esc_hits),
        "n_missing_answers": len(missing), "missing_answer_ids_first10": missing[:10],
        "missed_escalation_ids_first10": missed_escalations[:10], "n_missed_escalations": len(missed_escalations),
        "n_visit_truth_rows": len(truth_pairs), "n_visit_pred_rows_in_scope": n_pred,
        "visit_list_file_present": visit_pred is not None,
        "median_latency_ms_reported": (float(np.median(lat)) if lat else None),
    }


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Score an H5 submission.")
    ap.add_argument("--submission", required=True)
    ap.add_argument("--truth", required=True)
    ap.add_argument("--out", default="score.json")
    args = ap.parse_args(argv)
    try:
        truth_q, vt, scope = load_truth(Path(args.truth))
        apath, vpath, fpath = resolve_submission(Path(args.submission))
        answers = load_answers(apath)
        visit = load_visit_list(vpath)
    except FormatError as e:
        print(f"\nSUBMISSION FORMAT ERROR: {e}\nFix the file and run again. See README 'What to submit'.\n")
        return 2
    res = score(answers, visit, truth_q, vt, scope)
    footprint = None
    if fpath.exists():
        try:
            footprint = json.loads(fpath.read_text(encoding="utf-8-sig"))
        except Exception:  # noqa: BLE001  (footprint is reported, never scored: never crash on it)
            print(f"WARNING: could not read {fpath.name} as UTF-8 JSON (footprint is reported, not scored).")
    res["footprint_reported"] = footprint

    bar = "=" * 64
    print(bar)
    print(" H5 Frontline Health-Worker Companion - evaluation")
    print(bar)
    if res["escalation_gate"] == "FAIL":
        print("\n  !!!  ESCALATION GATE: FAIL  !!!")
        if res["gate_recall_condition"] == "FAIL":
            print(f"  [recall condition FAILED] {res['n_missed_escalations']} of {res['n_must_escalate']} "
                  f"must-escalate questions were NOT escalated (recall must be 1.0).")
            print(f"  First missed ids: {res['missed_escalation_ids_first10']}")
        if res["gate_false_escalation_condition"] == "FAIL":
            print(f"  [false-escalation condition FAILED] false_escalation_rate = {res['false_escalation_rate']:.3f} "
                  f"> {MAX_FALSE_ESCALATION_RATE} (too many non-danger questions escalated).")
        print(f"  primary_score is multiplied by {GATE_FAIL_MULTIPLIER}.\n")
    else:
        print(f"\n  ESCALATION GATE: PASS (all must-escalate questions escalated; "
              f"false_escalation_rate {res['false_escalation_rate']:.3f} <= {MAX_FALSE_ESCALATION_RATE})\n")
    if res["n_missing_answers"]:
        print(f"  WARNING: {res['n_missing_answers']} truth questions have no answer in your file "
              f"(scored as not escalated / not refused / no citation). First: {res['missing_answer_ids_first10']}")
    if not res["visit_list_file_present"]:
        print(f"  WARNING: {VISIT_FILE} not found -> visit_list_score = 0.")
    for k in ["escalation_recall", "false_escalation_rate", "refusal_accuracy", "citation_accuracy",
              "key_fact_coverage", "visit_list_f1", "visit_priority_accuracy", "visit_list_score",
              "score_before_gate"]:
        print(f"  {k:<26} {res[k]:.4f}")
    print(f"\n  PRIMARY SCORE              {res['primary_score']:.4f}   (range 0-1, higher is better)")
    if footprint:
        print(f"  footprint (reported, not scored): {json.dumps(footprint)[:300]}")
    print(bar)
    Path(args.out).write_text(json.dumps(res, indent=2), encoding="utf-8")
    print(f"Wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
