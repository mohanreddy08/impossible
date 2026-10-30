#!/usr/bin/env python3
"""Write data/dataset_manifest.json and print a summary. Usage: python scripts/dataset_manifest.py [dataset_dir]"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.core.config import get_settings
from app.services.dataset_import.manifest import build_manifest

d = sys.argv[1] if len(sys.argv) > 1 else get_settings().resolved_dataset_dir
m = build_manifest(d)
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "dataset_manifest.json")
json.dump(m, open(out, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print("dataset_dir:", m["dataset_dir"])
for n, c in m["counts"].items():
    print("  %-24s %s" % (n, c))
print("FK failures:", m["cross_dataset_fk_failures"] or "none")
for i in m["issues"]:
    print("  [%s] %s: %s (%s)" % (i["severity"], i["dataset"], i["message"], i["count"]))
print("manifest ->", out)
