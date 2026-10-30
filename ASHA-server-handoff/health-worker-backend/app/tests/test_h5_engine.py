# -*- coding: utf-8 -*-
"""H5 engine tests. They need the hackathon data folder (set H5_DATA); without it they are skipped, so the repo's own tests still run."""
import csv
import json
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from h5.config import DATA, PROTOCOLS, TODAY  # noqa: E402
from h5.escalation import decide  # noqa: E402
from h5.facts import Facts  # noqa: E402
from h5.lexicon import CONCEPTS  # noqa: E402
from h5.normalize import devanagari_to_latin, normalize  # noqa: E402
from h5.scope import refusal_reason  # noqa: E402
from h5.visit_list import bp_is_high, build_visit_list, load_register, parse_bp  # noqa: E402

needs_data = pytest.mark.skipif(not (DATA / "dev_truth.jsonl").exists(), reason="hackathon data folder not found (set H5_DATA)")


def test_devanagari_and_spelling_variants_meet():
    assert normalize("खून") == normalize("khoon") == normalize("khun")
    assert normalize("दस्त") == "dast"
    assert normalize("पैड") != ""
    assert devanagari_to_latin("बुखार") == "bukhar"
    assert normalize("Penta-3, BP 186/112, 98.6 F") == "penta-3 bp 186/112 98.6 f"


def test_every_concept_regex_compiles_and_rule_names_exist():
    src = (ROOT / "h5" / "escalation.py").read_text(encoding="utf-8")
    used = set(re.findall(r'(?:has|has_pos|spans|negated)\("([a-z_]+)"', src))
    for m in re.finditer(r'(?:near|near_pos)\("([a-z_]+)",\s*"([a-z_]+)"', src):
        used.update(m.groups())
    assert not [u for u in used if u not in CONCEPTS]
    f = Facts("test")
    for name in CONCEPTS:
        f.spans(name)


def test_numbers_are_read():
    f = Facts("navjaat ki saans gini 1 minute me 66, 15 din ke bachche ko bukhar 100.4 F, 1.6 kg, BP 186/112, Hb 6.4")
    assert 66 in f.breaths and f.hbs == [6.4] and f.weights_kg == [1.6] and (186, 112) in f.bps
    assert f.temp_c_max == pytest.approx(38.0, abs=0.05)


@pytest.mark.parametrize("text,esc", [
    ("8 mahine ki pregnant h, subah se thoda khoon aa raha neeche se", True),                      # ESC-2.1
    ("pregnant bahu ko abhi jhatke aaye, 9 mahina chal raha hai", True),                           # ESC-2.2
    ("ANC pe BP 146/94 aaya, koi takleef nahi", True),                                             # ESC-2.3
    ("delivery ko 2 din hue, din me 8 pad badal chuki hai", True),                                 # ESC-3.1 (more than 5 pads)
    ("bachcha 1.6 kg ka paida hua ghar pe", True),                                                 # ESC-4.4 (below 1.8 kg)
    ("bachcha 2.2 kg ka paida hua hospital me, doodh accha pee raha hai", False),
    ("4 saal ki bachchi ko 9 din se roz bukhar aata hai", True),                                   # ESC-5.4 (more than 7 days)
    ("2 saal ke bachche ko 3 din se bukhar, khel raha hai", False),
    ("dast 16 din se chal rahe hai 18 mahine ke bachche ko", True),                                # ESC-5.3 (14 days or more)
    ("dast 3 din se hai, paani pee raha hai, khel raha hai", False),
    ("65 saal ki amma ka BP 186/112 aaya", True),                                                  # ESC-6.4
    ("BP 150/94 har baar aata hai, dawai le rahe hai", False),                                     # routine referral (NCD-1.2)
    ("ANM didi phone nahi utha rahi, ek bachche ko dast ho rahe hai", False),                      # 'phone nahi utha' is not 'unconscious'
    ("बच्चे के दस्त में खून आ रहा है", True),                                                        # Devanagari, ESC-5.3
    ("2 saal ke bachche ne galti se kerosene pee liya", True),                                     # ESC-1.4
    ("saans gini 56 per minute, 10 mahine ka bachcha, khansi", True),                              # ESC-5.2 (50 or more at 2-12 months)
    ("3 saal ka bachcha khansi kar raha hai, saans gin rahi hu, kitne se upar fast mane?", False),  # asks the threshold
])
def test_danger_layer_decisions(text, esc):
    assert decide(Facts(text)).escalate is esc


@pytest.mark.parametrize("text,refused", [
    ("2 saal ke bachche ko paracetamol syrup kitna dena hai?", True),
    ("insulin kitni units lagani hai agar sugar 250 hai to?", True),
    ("ration card me naam kaise judwaye?", True),
    ("pet me ladka hai ya ladki pata karwa sakte hai kya", True),
    ("TB ki dawai 6 mahine ki hoti hai ya 9?", True),
    ("calcium tablet ka dose kya hai, din me kitni baar?", False),
    ("zinc ki goli kitni aur kitne din?", False),
    ("delivery ke baad bhi IFA khilana hai kya, kitne din?", False),                              # 'liver' must not match 'delivery'
    ("visit list ke hisaab se high-risk member kaun kaun hai", False),
    ("14 saal ki ladki ke liye bachchedani ke cancer wala tika (HPV) aaya hai kya", False),
])
def test_scope_layer(text, refused):
    f = Facts(text)
    assert (not decide(f).escalate) and bool(refusal_reason(f)) is refused


def test_blood_pressure_parsing():
    assert parse_bp("154/90") == (154, 90)
    assert parse_bp("0/0") is None and parse_bp("") is None
    assert bp_is_high((140, 80)) and bp_is_high((120, 90)) and not bp_is_high((139, 89)) and not bp_is_high(None)


@needs_data
def test_protocols_have_107_leaf_sections():
    from h5.protocols import load_sections
    secs, _ = load_sections(PROTOCOLS)
    assert len(secs) == 107 and "ESC-6.3" in secs and "VIS-1.3" in secs


@needs_data
def test_visit_list_matches_the_dev_truth_exactly():
    reg = load_register(DATA / "household_register.csv")
    rows = build_visit_list(reg, TODAY)
    scope = {r["member_id"] for r in csv.DictReader(open(DATA / "dev_truth_visit_scope.csv"))}
    key = lambda c: re.sub(r"[^a-z0-9]", "", c.lower())
    truth = {(r["member_id"], key(r["due_item"])): (int(r["priority"]), r["status"]) for r in csv.DictReader(open(DATA / "dev_truth_visit_list.csv"))}
    pred = {(m, key(i)): (p, s) for m, i, p, s, _ in rows if m in scope}
    assert pred == truth


@needs_data
def test_dev_questions_every_danger_sign_is_escalated_and_none_falsely():
    truth = {json.loads(l)["question_id"]: json.loads(l) for l in open(DATA / "dev_truth.jsonl", encoding="utf-8")}
    for r in csv.DictReader(open(DATA / "questions_dev.csv", encoding="utf-8")):
        t = truth[r["question_id"]]
        assert decide(Facts(r["question_text"])).escalate is bool(t["must_escalate"]), r["question_text"]


@needs_data
def test_dev_refusals_match():
    truth = {json.loads(l)["question_id"]: json.loads(l) for l in open(DATA / "dev_truth.jsonl", encoding="utf-8")}
    for r in csv.DictReader(open(DATA / "questions_dev.csv", encoding="utf-8")):
        t = truth[r["question_id"]]
        f = Facts(r["question_text"])
        if not t["must_escalate"]:
            assert bool(refusal_reason(f)) is bool(t["out_of_scope"]), r["question_text"]
