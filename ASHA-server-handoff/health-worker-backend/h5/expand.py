# -*- coding: utf-8 -*-
"""Hinglish / Hindi / Marathi / Bengali / Telugu words -> the English words the protocols use, so BM25 over English sections can find them.
Keys are written in ordinary spelling and phonetically folded on load (the questions are folded the same way)."""
from __future__ import annotations

import re
from typing import Dict, List

from .normalize import fold_roman

_RAW = {
    # question words / structure
    "kab": "when", "kitna kitne kitni": "how many how much", "kaise": "how", "kyu kyon": "why", "kahan": "where refer",
    "kab tak": "till until maximum", "maximum": "maximum upper limit", "minimum": "minimum", "kam se kam": "at least minimum",
    "upar": "above or more", "niche": "below less", "gap antar beech": "gap interval minimum gap between doses", "shuru": "start begin",
    "band": "stop", "chhoot chhut chhut": "missed", "late": "late delay", "dobara": "again restart", "pehle": "first before", "pehla pehli": "first",
    "doosra dusra dosra dusre": "second 2nd", "teesra tisra teesri": "third 3rd", "chautha chauthi": "fourth 4th", "pehla pehli pehle": "first 1st before", "baad": "after", "sabse": "most", "hamesha": "always",
    "roz": "daily every day", "ek saath": "together same time", "dobara se": "restart", "kitne baar": "how many times",
    # people / places
    "bachcha bacha bache bachche bachchi bachi": "child baby infant", "navjat navjaat nobojato janme": "newborn", "paida": "born birth", "janam janm": "birth born",
    "maa mother": "mother", "beneficiary labharthi": "pregnant woman mother", "garbh garbhvati pregnant pregnancy": "pregnancy pregnant", "prasav delivery dilivari": "delivery",
    "ghar": "home", "aspatal hospital": "hospital", "sarkari": "government", "operation": "caesarean", "ward": "ward village",
    "anganwadi": "anganwadi", "didi anm": "anm", "doctor": "medical officer doctor", "marij": "patient", "buzurg": "adult",
    # vaccines
    "tika tike teeka tikakaran": "vaccine immunisation", "sui": "injection", "boond": "drops", "rota rotavirus": "rvv rotavirus", "khasra": "mr measles rubella",
    "polio": "opv polio fipv", "booster": "booster", "dose": "dose", "free muft": "free", "tikakaran diwas": "immunisation session wednesday saturday",
    "pura": "complete", "chhutne": "missed", "birth dose": "birth dose", "hepatitis": "hepatitis b", "shahad": "honey", "ghutti": "ghutti",
    "tt": "td tt tetanus", "td": "td tetanus diphtheria", "session": "session site wait 30 minutes", "30 minute": "30 minutes",
    # symptoms
    "dast": "diarrhoea loose stool", "loose": "diarrhoea", "motion motions": "diarrhoea stool", "patle": "diarrhoea", "bukhar taap": "fever", "khansi": "cough",
    "saans": "breathing breath breaths", "pasli": "chest indrawing", "sujan suji suje": "swelling oedema", "ulti": "vomiting vomit", "dudh doodh": "breastfeeding breast milk",
    "stan": "breast", "pilana pilane pila": "give feed drink", "naal": "cord umbilicus umbilical", "peeliya peela": "jaundice yellow", "peeli peele": "pallor pale yellow jaundice", "peep": "pus",
    "khun khoon": "bleeding blood", "jhatke jhatka mirgi": "convulsions fits", "behosh": "unconscious", "sust": "lethargic drowsy", "dard": "pain",
    "sir dard": "headache head pain", "sar dard": "headache head pain", "pet": "abdominal abdomen belly", "pair": "feet foot", "hath haath": "hands hand", "aankh": "eyes", "chehra muh": "face",
    "dhundhla dhundh": "blurring vision blurred", "chakkar": "dizziness", "paseena": "sweating", "kaanp": "tremors", "kamzori kamzor": "weakness weak",
    "thakan thaki": "tiredness tired", "khoon ki kami": "anaemia", "thanda thandi": "cold", "garam": "warm hot fever", "dhansi dhans": "sunken", "chutki": "skin pinch",
    "pallor": "pallor pale palmar", "hatheli": "palms palmar", "talve": "soles", "peele": "yellow jaundice",
    # nutrition / MUAC
    "naap naapna naapte": "measure muac", "baanh": "arm muac", "feeta": "tape muac", "dubla dubli": "thin wasted", "kuposhan": "malnutrition", "bhookh": "appetite hungry",
    "kam wajan": "low birth weight", "wajan": "weight", "nehlana nehla nahlana nahlane": "bathe bathing bath", "kapde": "cloth", "kmc kangaroo": "kangaroo mother care skin to skin warm",
    "upar ka khana": "complementary feeding food", "khana": "food feeding",
    # medicines / supplements
    "lal goli": "red ifa tablet iron folic acid", "aayaran": "iron ifa", "goli": "tablet", "dawai": "medicine", "keede": "deworming albendazole worms", "ors": "ors", "jeevan rakshak": "ors",
    "zinc": "zinc", "calcium": "calcium", "folic": "folic acid", "iron": "iron ifa", "vitamin a": "vitamin a", "misri": "sugar misri toffee", "namak": "salt", "nashta": "meal food",
    "khali pet": "empty stomach", "khane": "meals food", "subah": "morning", "raat": "night",
    # pregnancy / schedule
    "mahwari": "lmp last menstrual period", "maahvari": "lmp", "aakhri": "last", "tareekh": "date", "mahine mahina": "months month", "hafte hafta": "weeks week", "saal": "years year",
    "din": "days day", "jaanch": "check-up test screening", "checkup": "check-up", "trimester": "trimester", "edd": "edd expected date of delivery lmp 280 days",
    "pmsma": "pmsma 9th of every month", "jssk": "jssk free", "gaadi": "transport ambulance", "ambulance": "ambulance 102 108", "tareekh nikale": "edd lmp 280 days",
    # NCD / BP / sugar
    "bp": "blood pressure bp hypertension", "sugar madhumeh": "sugar diabetes blood sugar", "exercise vyayam": "physical activity exercise at least 30 minutes", "niyamit": "regular",
    "screening": "screening", "cbac": "cbac score", "high risk": "high risk", "confirm": "diagnosis confirm", "fasting": "fasting", "random": "random",
    "low sugar": "low blood sugar hypoglycaemia below 70 mg dl", "dawai band": "stop medicines", "insulin": "insulin medicine", "tension": "stress",
    # visit list
    "list": "list", "visit": "visit home visit", "overdue": "overdue", "priority": "priority", "high-risk": "high risk", "due": "due", "hbnc": "hbnc home visits", "hbyc": "hbyc home visits",
    "umar": "age", "age": "age", "sabse pehle": "first priority", "due list": "due list register",
    # scope
    "hospital kahan": "refer facility", "nrc": "nrc", "sncu": "sncu", "phc": "phc", "mo": "medical officer", "referral": "refer",
}


def _build() -> Dict[str, List[str]]:
    out: Dict[str, List[str]] = {}
    for keys, vals in _RAW.items():
        for k in re.split(r"\s{1,}", keys) if " " in keys and len(keys.split()) > 1 and keys.count("  ") else [keys]:
            pass
    for keys, vals in _RAW.items():
        words = [w.strip() for w in keys.replace("|", " ").split()]
        # a key with one space and two known words is a phrase ("kab tak", "lal goli"); otherwise every word is its own key
        phrase_keys = {"kab tak", "kam se kam", "ek saath", "dobara se", "kitne baar", "tikakaran diwas", "birth dose", "upar ka khana", "lal goli", "khoon ki kami", "vitamin a",
                       "khali pet", "kam wajan", "jeevan rakshak", "sabse pehle", "due list", "low sugar", "dawai band", "tareekh nikale", "hospital kahan", "30 minute", "high risk"}
        if keys in phrase_keys:
            out[fold_roman(keys.lower())] = vals.split()
        else:
            for w in words:
                out.setdefault(fold_roman(w.lower()), []).extend(vals.split())
    return out


EXPAND: Dict[str, List[str]] = _build()
