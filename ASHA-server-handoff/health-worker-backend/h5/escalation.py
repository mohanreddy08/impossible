# -*- coding: utf-8 -*-
"""The hard-coded danger-sign layer (ESC protocol). It runs BEFORE retrieval, before any model, and never depends on one.

    decision = decide(Facts(question))      # decision.escalate, decision.sections (ESC leaf ids, best first), decision.rules

One rule per sign of the ESC document, each tied to its leaf section so the answer can cite it. Numbers come straight from the protocol:
  newborn: breathing >= 60/min, temperature > 99 F (37.2 C) or < 95.9 F (35.5 C), weight < 1.8 kg, >= 10 pustules ...
  child: fast breathing >= 50/min (2-12 months) or >= 40/min (12 months-5 years) WITH cough, fever > 7 days, diarrhoea >= 14 days ...
  pregnancy: any bleeding, BP >= 140/90, labour pain > 12 h, Hb < 7 ... ; after delivery: > 5 pads or a pad soaked in < 5 min, > 38 C ...
  adults with BP/sugar: BP >= 180/110, chest pain, stroke signs, low sugar ...
If a sign is described for a person, we escalate (ESC-1.2: when not sure, treat it as present). A question that only asks what a
threshold is ("kitne se upar tez maane") is not a person with a sign and is answered normally.
"""
from __future__ import annotations

import re
from typing import List, Tuple

from .facts import Facts
from .normalize import fold_pattern


class Decision:
    def __init__(self) -> None:
        self.rules: List[str] = []
        self.sections: List[str] = []
        self.subject = ""

    @property
    def escalate(self) -> bool:
        return bool(self.rules)

    def add(self, rule: str, *sections: str) -> None:
        if rule not in self.rules:
            self.rules.append(rule)
        for s in sections:
            if s not in self.sections:
                self.sections.append(s)


_HYPOTHETICAL = re.compile(fold_pattern(r"aaye\s+to|ae\s+to|ho\s+to\b|kise\s+kehte|kitne\s+se\s+(?:upar|kam|zyada|jyada)|kitna\s+ho\s+to|maane|maana\s+jata|kab\s+maana|se\s+upar\s+aaye"))
_HOWTO = re.compile(fold_pattern(r"kaise\s+(?:check|pata|dekh|jaanch|naap|kare|karte)|how\s+to"))


def subject_of(f: Facts) -> Tuple[bool, bool, bool, bool]:
    """(pregnant, postpartum, newborn, child) -- a question may be about more than one person; each flag is judged on its own."""
    age = f.age_days
    ago = min(f.timeagos) if f.timeagos else None
    preg = f.has("pregnant") or (f.has("pregnant_month_phrase") and not f.has("baby")) or bool(f.preg_units) or f.has("anc_word")
    pp = f.has("postpartum_phrase") and (ago is None or ago <= 45) and (f.has("mother") or f.has("delivery"))
    newborn = f.has("newborn_word") or f.has("cord") or (age is not None and age <= 59 and f.has("baby"))
    child = f.has("baby") and not newborn and (age is None or 60 <= age <= 1830)
    if f.has("newborn_word") and age is not None and age > 59:
        newborn = False
        child = True
    if pp and newborn and ago is not None and age is None:
        newborn = f.has("newborn_word") and not f.has("mother")
    return preg, pp, newborn, child


def _bleeding_positive(f: Facts) -> bool:
    """Bleeding mentioned for real: not negated and not 'khun ki kami' (anaemia) / 'khun ki jaanch' (blood test)."""
    for s in f.spans("bleeding"):
        if f.negated(s, "bleeding"):
            continue
        after = f.t[s[1]: s[1] + 14]
        if re.match(r"\s*(?:ki\s+(?:kami|jach|kam)|ka\s+test|badh|jach)", after):
            continue
        return True
    return False


def decide(f: Facts) -> Decision:
    d = Decision()
    preg, pp, nb, child = subject_of(f)
    baby = f.has("baby")
    hyp = bool(_HYPOTHETICAL.search(f.t))
    d.subject = "newborn" if nb else "postpartum" if pp else "pregnant" if preg else "child" if child else "adult"

    fits = f.has_pos("fits")
    unconscious = f.has_pos("unconscious")
    lethargic = f.has_pos("lethargic")
    not_feeding = f.has_pos("not_feeding")
    not_drinking = f.has_pos("not_drinking")
    vomit_all = f.has_pos("vomit_all")
    fever = f.has("fever")
    cough = f.has("cough")
    after_vaccine = f.has("vaccine_ctx") and f.has_pos("fits")
    ncd = f.has("ncd_context")
    adult_ctx = f.has("adult_patient") and not baby

    # ---------------------------------------------------------------- ESC-2 pregnancy
    if preg and not nb:
        bleed = _bleeding_positive(f)
        if bleed and not f.near("bleeding", "stool_ctx", 18) and not (pp and (f.pads or f.pad_minutes)):
            d.add("preg-bleeding", "ESC-2.1")
        if fits or unconscious:
            d.add("preg-fits-or-faint", "ESC-2.2")
        if any(a >= 140 or b >= 90 for a, b in f.bps) and not hyp:
            d.add("preg-bp-140-90", "ESC-2.3")
        if f.has_pos("blur_vision") or f.has_pos("swelling_face") or (f.has_pos("headache") and f.has("severe")):
            d.add("preg-preeclampsia-signs", "ESC-2.3")
        if (f.temp_c_max is not None and f.temp_c_max > 38.0) or (fever and f.has_pos("high_fever")):
            d.add("preg-high-fever", "ESC-2.4")
        if any(h < 7.0 for h in f.hbs) and not hyp:
            d.add("preg-hb-below-7", "ESC-2.5")
        if f.has_pos("pallor") and (f.has_pos("breath_fast") or f.has("severe")) and not hyp:
            d.add("preg-severe-pallor", "ESC-2.5")
        if f.has_pos("breath_fast") and not hyp:
            d.add("preg-breathless", "ESC-2.5")
        if f.has("belly_pain") and f.has("severe") and not f.has("improving"):
            d.add("preg-severe-belly-pain", "ESC-2.6")
        if f.has_pos("vomit") and (vomit_all or f.has("severe")):
            d.add("preg-excessive-vomiting", "ESC-2.6")
        if f.has_pos("foul") and (f.has("vaginal_ctx") or f.has("pregnant")) and not f.has("cord"):
            d.add("preg-foul-discharge", "ESC-2.8")
        if f.has("limb_first") or f.has("placenta_stuck") or f.has("twins"):
            d.add("labour-complication", "ESC-2.8")

    # these name the pregnancy themselves (a baby that stopped moving, the water bag, labour pain), so "pregnant" need not be written
    if f.has_pos("movement") and not nb:
        d.add("reduced-foetal-movement", "ESC-2.7")
    if f.has_pos("water_bag") and not hyp and not nb:
        d.add("water-bag-leaking", "ESC-2.8")
    if f.hours and f.has("labour_pain") and max(f.hours) > 12:
        d.add("labour-over-12h", "ESC-2.8")

    # ---------------------------------------------------------------- ESC-3 mother after delivery
    if pp and not (nb and not f.has("mother")):
        if (f.pads and max(f.pads) > 5) or (f.pad_minutes and min(f.pad_minutes) < 5):
            d.add("pp-heavy-bleeding", "ESC-3.1")
        elif _bleeding_positive(f) and f.has("severe") and not hyp:
            d.add("pp-heavy-bleeding", "ESC-3.1")
        if (f.temp_c_max is not None and f.temp_c_max > 38.0) or (fever and f.has_pos("high_fever")) or (f.has_pos("foul") and fever):
            d.add("pp-fever-or-foul-discharge", "ESC-3.2")
        if fits or unconscious or f.has_pos("abnormal_behavior") or (f.has_pos("headache") and f.has_pos("blur_vision")):
            d.add("pp-fits-or-abnormal", "ESC-3.3")
        if f.has_pos("breath_fast") or (f.has_pos("pallor") and f.has("severe")) or (f.has("belly_pain") and f.has("severe")):
            d.add("pp-breathless-pallor-pain", "ESC-3.4")

    # ---------------------------------------------------------------- ESC-4 newborn / young infant (up to 2 months)
    if nb:
        if not_feeding or f.has_pos("weak_cry") or f.has_pos("limp_limbs") or lethargic or unconscious or fits:
            d.add("nb-feeding-cry-activity-fits", "ESC-4.1")
        if (f.breaths and max(f.breaths) >= 60) or f.has_pos("chest_indraw") or f.has_pos("blue") or (f.has_pos("breath_fast") and not hyp):
            d.add("nb-breathing", "ESC-4.2")
        if not hyp:
            if (f.temp_c_max is not None and f.temp_c_max > 37.2) or (fever and f.temp_c_max is None and f.has_pos("fever")):
                d.add("nb-fever", "ESC-4.3")
            if (f.temp_f_min is not None and f.temp_f_min < 95.9) or (f.has_pos("cold_touch") and not f.has("hands_feet_only")):
                d.add("nb-cold", "ESC-4.3")
        cord_bad = f.near("cord", "pus", 45) or f.near("cord", "red_area", 45) or f.near("cord", "bleeding", 45) or f.near("cord", "foul", 45)
        if cord_bad and not f.has("generic_question"):
            d.add("nb-cord-infection", "ESC-4.4")
        if f.has("pustules") and f.has("pus"):
            for s in f.spans("pustules"):
                window = f.t[max(0, s[0] - 40): s[1] + 40]
                nums = [int(x) for x in re.findall(r"\b(\d{1,3})\b", window)]
                if nums and max(nums) >= 10:
                    d.add("nb-pustules-10-plus", "ESC-4.4")
                    break
        if f.has_pos("jaundice") and (f.has("day_one") or f.has("palms_soles") or (f.age_days is not None and f.age_days >= 14)):
            d.add("nb-jaundice", "ESC-4.4")
        if f.has_pos("distended") or (f.has_pos("vomit") and f.has("severe")):
            d.add("nb-distended-or-vomiting", "ESC-4.4")
        if f.has_pos("stool_blood"):
            d.add("nb-blood-in-stool", "ESC-4.4")
        if any(w < 1.8 for w in f.weights_kg) and not hyp:
            d.add("nb-weight-below-1.8", "ESC-4.4")

    # ---------------------------------------------------------------- ESC-5 child 2 months - 5 years
    if child or (baby and not nb):
        gds = fits or unconscious or lethargic or not_feeding or not_drinking or vomit_all
        if not_feeding or not_drinking or vomit_all or fits or unconscious or lethargic:
            d.add("child-general-danger-sign", "ESC-5.1")
        age = f.age_days
        thr = 50 if (age is not None and age < 365) else 40
        if f.breaths and max(f.breaths) >= thr and not hyp:
            d.add("child-fast-breathing", "ESC-5.2")
        if f.has_pos("chest_indraw") or f.has_pos("stridor") or (f.has_pos("blue")):
            d.add("child-chest-indrawing-or-stridor", "ESC-5.2")
        if f.has_pos("stool_blood") and not hyp:
            d.add("child-blood-in-stool", "ESC-5.3")
        diar = f.has("diarrhoea")
        if diar and f.durations and max(f.durations) >= 14:
            d.add("child-diarrhoea-14-days", "ESC-5.3")
        sev = (1 if (lethargic or unconscious) else 0) + (1 if f.has_pos("dehydr_sunken") else 0) + (1 if (not_drinking) else 0) + (1 if f.has_pos("skin_very_slow") else 0)
        if sev >= 2:
            d.add("child-severe-dehydration", "ESC-5.3")
        sam = (f.muacs and min(f.muacs) < 11.5)
        if diar and sam:
            d.add("child-diarrhoea-with-sam", "ESC-5.3")
        if fever and (gds or f.has_pos("stiff_neck")):
            d.add("child-fever-with-danger-sign", "ESC-5.4")
        if fever and f.durations and max(f.durations) > 7 and not diar:
            d.add("child-fever-over-7-days", "ESC-5.4")
        oedema = f.has_pos("swelling_feet") and (f.has("pitting") or "dono" in f.tokens) and not _HOWTO.search(f.t)
        if oedema:
            d.add("child-oedema-both-feet", "ESC-5.5", "NUT-2.1")
        if sam and (f.has_pos("poor_appetite") or f.has_pos("wasted") or lethargic or f.has_pos("breath_fast") or f.has_pos("pallor") or f.has_pos("irritable") or oedema):
            d.add("child-sam-with-complication", "ESC-5.5", "NUT-2.1")
        if age is not None and age < 184 and (f.has_pos("wasted") or (not_feeding and f.has("weak_cry"))) :
            d.add("infant-wasted-or-too-weak-to-suckle", "ESC-5.5")
        if f.has_pos("wasted") and f.has_pos("not_feeding") and not d.rules:
            d.add("infant-wasted-or-too-weak-to-suckle", "ESC-5.5")
        if after_vaccine or (f.has("vaccine_ctx") and (f.has_pos("breath_fast") or f.has_pos("swelling_face"))) and not f.has("improving"):
            if fits or f.has_pos("breath_fast") or f.has_pos("swelling_face") or lethargic:
                d.add("child-reaction-after-vaccine", "ESC-5.6")
        if f.has_pos("pallor") and f.has("palms_soles") and f.has("severe"):
            d.add("child-severe-palmar-pallor", "ESC-5.7")

    # ---------------------------------------------------------------- ESC-6 adults with hypertension / diabetes (and other adults)
    if not baby and not preg and not pp:
        if any(a >= 180 or b >= 110 for a, b in f.bps) and not hyp:
            d.add("adult-bp-180-110", "ESC-6.4")
        if any(x >= 180 for x in f.bp_systolic_only) and not hyp:
            d.add("adult-bp-180-110", "ESC-6.4")
        if f.has_pos("chest_pain"):
            d.add("adult-chest-pain", "ESC-6.1")
        if f.has_pos("stroke"):
            d.add("adult-stroke-signs", "ESC-6.2")
        low = f.has("low_sugar_word") or (f.sugars and min(f.sugars) < 70)
        if (f.sugars and min(f.sugars) < 70 and not hyp) or (ncd and f.has_pos("low_sugar_signs") and (f.has_pos("sweat") or f.has_pos("confus") or f.has("low_sugar_word")) and not hyp and adult_ctx):
            d.add("adult-low-sugar", "ESC-6.3")
        if unconscious and (ncd or adult_ctx or f.has("adult_patient")):
            d.add("adult-unconscious", "ESC-6.3", "ESC-1.3")
    # ---------------------------------------------------------------- ESC-1.4 other life-threatening emergencies (anyone)
    if f.has_pos("emergency_other") and not hyp:
        d.add("other-emergency", "ESC-1.4")
    if unconscious and not d.rules:
        d.add("unconscious", "ESC-1.4")
    return d
