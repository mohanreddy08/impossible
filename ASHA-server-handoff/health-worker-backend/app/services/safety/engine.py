"""Deterministic safety/escalation engine. No ML, no network, no LLM: pure rules over a versioned JSON ruleset.

Precedence: ESCALATION_REQUIRED > OUT_OF_SCOPE > CLARIFICATION_REQUIRED > NORMAL_PROTOCOL_QUERY.
A danger sign only escalates when it is CURRENT and NOT negated in its clause. Negated, historical-resolved
and hypothetical mentions do not escalate. Bare symptom words and very short messages route to clarification.
"""
import hashlib
import json
import os
import re
from dataclasses import dataclass, field
from typing import List, Optional

from app.services.text import normalize_text

RULES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rules", "danger_rules.json")
_TOK = re.compile(r"\S+")
_STRIP = ".,;:!?()\"'[]"


@dataclass
class Match:
    rule_id: str
    label: str
    context: str            # CURRENT | NEGATED | HISTORICAL | HYPOTHETICAL
    kind: str               # SEVERE_PATTERN | BARE_MENTION | AMBIGUOUS | OUT_OF_SCOPE
    text: str
    reason: str


@dataclass
class SafetyDecision:
    status: str
    rule_ids: List[str]
    reasons: List[str]
    matches: List[Match]
    ruleset_id: str
    ruleset_version: str
    ruleset_review_status: str
    ruleset_sha256: str
    clinically_validated: bool
    message: Optional[str]
    original_text: str
    normalized_text: str
    needs_human_review: bool = False


class SafetyEngine:
    def __init__(self, path: str = RULES_PATH):
        raw = open(path, "rb").read()
        self.sha256 = hashlib.sha256(raw).hexdigest()
        cfg = json.loads(raw.decode("utf-8"))
        self.cfg = cfg
        c = cfg["cues"]
        self.split = re.compile(c["clause_split"])
        self.neg = {normalize_text(t) for t in c["negation_tokens"]}
        self.neg_after = {normalize_text(t) for t in c["negation_after_tokens"]}   # postpositional (Telugu/transliterated) only
        self.nb, self.na = c["negation_window_before"], c["negation_window_after"]
        self.hist = [normalize_text(p) for p in c["history_phrases"]]
        self.cur = [normalize_text(p) for p in c["current_phrases"]]
        self.hyp = [normalize_text(p) for p in c["hypothetical_phrases"]]
        comp = lambda ps: [re.compile(p, re.UNICODE) for p in ps]  # noqa: E731
        self.rules = [dict(id=r["rule_id"], label=r["label"], pat=comp(r["patterns"]), men=comp(r["mentions"])) for r in cfg["rules"]]
        self.amb = comp(cfg["ambiguous_patterns"])
        self.oos = comp(cfg["out_of_scope_patterns"])
        self.short_max = cfg["short_message_max_tokens"]

    # -- helpers ---------------------------------------------------------
    @staticmethod
    def _has(clause: str, phrases) -> bool:
        padded = " " + clause + " "
        return any(p in padded or (p.strip() and re.search(r"(?<!\w)" + re.escape(p.strip()) + r"(?!\w)", clause)) for p in phrases)

    def _negated(self, clause: str, s: int, e: int) -> bool:
        toks = [(m.group(), m.start(), m.end()) for m in _TOK.finditer(clause)]
        idx = [i for i, (_, a, b) in enumerate(toks) if b > s and a < e]
        if not idx:
            return False
        lo, hi = idx[0], idx[-1]
        before = toks[max(0, lo - self.nb):lo]
        after = toks[hi + 1:hi + 1 + self.na]
        return (any(t.strip(_STRIP) in self.neg for t, _, _ in before)
                or any(t.strip(_STRIP) in self.neg_after for t, _, _ in after))

    def _context(self, clause: str, s: int, e: int) -> str:
        if self._negated(clause, s, e):
            return "NEGATED"
        if self._has(clause, self.hyp):
            return "HYPOTHETICAL"
        if self._has(clause, self.hist) and not self._has(clause, self.cur):
            return "HISTORICAL"
        return "CURRENT"

    # -- main ------------------------------------------------------------
    def evaluate(self, text: str) -> SafetyDecision:
        norm = normalize_text(text)
        clauses = [c.strip() for c in self.split.split(norm) if c and c.strip()]
        matches: List[Match] = []
        for clause in clauses:
            for rule in self.rules:
                severe = []
                for rx in rule["pat"]:
                    for m in rx.finditer(clause):
                        severe.append(m)
                        matches.append(Match(rule["id"], rule["label"], self._context(clause, m.start(), m.end()), "SEVERE_PATTERN", m.group(), "%s phrase matched" % rule["label"]))
                if not severe:
                    for rx in rule["men"]:
                        m = rx.search(clause)
                        if m:
                            matches.append(Match(rule["id"], rule["label"], self._context(clause, m.start(), m.end()), "BARE_MENTION", m.group(), "%s mentioned without severity or context" % rule["label"]))
                            break
            for rx in self.amb:
                m = rx.search(clause)
                if m:
                    matches.append(Match("DSR-AMBIGUOUS", "Unclear complaint", "CURRENT", "AMBIGUOUS", m.group(), "complaint too vague to classify"))
                    break
        oos = [Match("DSR-OUT-OF-SCOPE", "Unsupported medical request", "CURRENT", "OUT_OF_SCOPE", m.group(), "dosage/prescribing/treatment request")
               for rx in self.oos for m in [rx.search(norm)] if m]

        ntok = len(_TOK.findall(norm))
        severe_cur = [m for m in matches if m.kind == "SEVERE_PATTERN" and m.context == "CURRENT"]
        bare_cur = [m for m in matches if m.kind == "BARE_MENTION" and m.context == "CURRENT"]
        amb = [m for m in matches if m.kind == "AMBIGUOUS"]
        short = 0 < ntok <= self.short_max
        human = False
        if severe_cur and not short:
            status, used = "ESCALATION_REQUIRED", severe_cur
        elif oos:
            status, used = "OUT_OF_SCOPE", oos[:1]
        elif severe_cur or bare_cur or amb:
            status, used = "CLARIFICATION_REQUIRED", severe_cur + bare_cur + amb
            human = bool(severe_cur)   # a bare danger-sign keyword: route to clarification AND flag for review
        else:
            status, used = "NORMAL_PROTOCOL_QUERY", []
        reasons = [m.reason + " (%s)" % m.context.lower() for m in used]
        if status == "CLARIFICATION_REQUIRED" and severe_cur:
            reasons.append("message too short to establish context; short-message policy routes to clarification")
        return SafetyDecision(
            status=status, rule_ids=sorted({m.rule_id for m in used}), reasons=reasons, matches=matches + oos,
            ruleset_id=self.cfg["ruleset_id"], ruleset_version=self.cfg["version"],
            ruleset_review_status=self.cfg["review_status"], ruleset_sha256=self.sha256, clinically_validated=bool(self.cfg.get("clinically_validated", False)),
            message=self.cfg["messages"].get(status), original_text=text, normalized_text=norm, needs_human_review=human)


_default: Optional[SafetyEngine] = None


def get_engine() -> SafetyEngine:
    global _default
    if _default is None:
        _default = SafetyEngine()
    return _default
