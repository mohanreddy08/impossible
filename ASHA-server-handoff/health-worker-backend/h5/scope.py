# -*- coding: utf-8 -*-
"""The refusal layer (SCP-1.2): what this assistant must NOT answer, and must redirect to the Medical Officer / ANM.

It runs after the danger layer: a life-threatening emergency is never refused (ESC-1.4), even if the condition is not in the protocols.
Returns the reason, or '' when the question is in scope. In scope questions must never be refused (a worker turned away scores zero),
so each rule needs a clear signal; the protocols' own medicines (ORS, zinc, IFA, calcium, folic acid, albendazole in pregnancy, vitamin A,
Td, sugar for low blood sugar) are answerable.
"""
from __future__ import annotations

import re

from .facts import Facts
from .normalize import fold_pattern

_NO_DRUG_Q = re.compile(fold_pattern(r"sugar\s+ki\s+dawai\s+(?:wali|wale|vali)"))


def refusal_reason(f: Facts) -> str:
    if f.has("sex_determination"):
        return "sex determination (PC-PNDT)"
    if f.has("admin"):
        return "administrative question"
    if f.has("family_planning"):
        return "family planning / abortion services not in the protocols"
    if f.has("report_reading"):
        return "reading a scan, X-ray or lab report"
    if f.has("unrelated"):
        return "not about health"
    hpv = f.has("protocol_topic") and re.search(r"\bhpv\b", f.t) is not None
    if f.has("disease_not_covered") and not hpv:
        return "condition not covered by the protocols"
    protocol_drug = f.has("dose_in_protocol")
    # albendazole is in the protocols for pregnancy only (ANC-2.4): a child's dose is not
    if re.search(r"albendazole|keede", f.t) and f.has("baby") and not (f.has("pregnant") or bool(f.preg_units)):
        return "medicine dose not in the protocols (albendazole for a child)"
    if f.has("dose_choice_q") and f.has("drug_not_in_protocol") and not protocol_drug:
        return "dose or choice of a medicine not in the protocols"
    if f.has("dose_choice_q") and f.has("tablet_word") and not protocol_drug and not f.has("protocol_topic") and not f.has("bp_word") and re.search(
            fold_pattern(r"kaun\s*s[aei]|koi\s+(?:dawai|goli|ilaaj)|dawai\s+(?:batao|chahiye)"), f.t):
        return "which medicine to give"
    if f.has("drug_not_in_protocol") and re.search(fold_pattern(r"\bmg\b|\bunits?\b|\bml\b"), f.t) and not protocol_drug:
        return "dose of a medicine not in the protocols"
    return ""
