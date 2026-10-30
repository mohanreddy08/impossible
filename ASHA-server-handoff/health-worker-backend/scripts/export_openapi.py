#!/usr/bin/env python3
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.main import app
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "openapi.json")
json.dump(app.openapi(), open(out, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print("wrote", out, "-", len(app.openapi()["paths"]), "paths")
