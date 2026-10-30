"""POST /api/v1/ask must give exactly what h5.pipeline gives (and what golden/golden.json recorded) for all 240 questions:
same answer text, same cited section ids, same escalate and refused flags."""
import json
import os

import pytest

from app.tests.conftest import H5_DIR, login, needs_pack

pytestmark = needs_pack
GOLDEN = os.path.join(os.path.dirname(H5_DIR), "golden", "golden.json")


@pytest.fixture(scope="module")
def golden():
    if not os.path.exists(GOLDEN):
        pytest.skip("golden/golden.json not found")
    g = json.load(open(GOLDEN, encoding="utf-8"))
    assert len(g) == 240
    return g


def test_ask_matches_h5_pipeline_and_golden_for_240_questions(web, golden):
    from pathlib import Path

    from h5.pipeline import Assistant
    engine = Assistant(Path(H5_DIR) / "protocols")
    c = web(rate_limit_per_minute=0)
    h = login(c, "anm")
    mismatches = []
    for g in golden:
        r = c.post("/api/v1/ask", json={"question": g["text"]}, headers=h)
        assert r.status_code == 200, (g["id"], r.text)
        api = r.json()
        direct = engine.answer(g["id"], g["text"])
        for field, want, have in (("answer", g["answer"], api["answer_text"]), ("cited", g["cited"], api["cited_section_ids"]),
                                  ("escalate", g["escalate"], api["escalate"]), ("refused", g["refused"], api["refused"]),
                                  ("pipeline", direct["answer_text"], api["answer_text"])):
            if want != have:
                mismatches.append((g["id"], field))
        if api["escalate"]:
            assert api["outcome"] == "ESCALATED" and api["answer_text"].startswith("REFER IMMEDIATELY")
        if api["refused"]:
            assert api["outcome"] == "REFUSED" and api["cited_section_ids"] == ["SCP-1.2"]
    assert mismatches == []
    assert sum(g["escalate"] for g in golden) > 0 and sum(g["refused"] for g in golden) > 0
