#!/usr/bin/env python3
"""Run the full suite on SQLite and (if pgserver is installed) on real PostgreSQL; write docs/test_report.json with ACTUAL counts per backend.
PostgreSQL is never reported as tested unless the PostgreSQL run really executed."""
import json, os, subprocess, sys, xml.etree.ElementTree as ET
from collections import Counter
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(backend):
    xml = os.path.join(root, "docs", "junit_%s.xml" % backend)
    env = dict(os.environ, TEST_DB=backend)
    p = subprocess.run([sys.executable, "-m", "pytest", "--junitxml", xml, "-q", "-rs"], cwd=root, env=env, capture_output=True, text=True)
    suite = ET.parse(xml).getroot()
    suite = suite if suite.tag == "testsuite" else suite.find("testsuite")
    st, by_file, skipped = Counter(), {}, []
    for c in suite.iter("testcase"):
        f = c.get("classname", "").split(".")[-1]
        sk = c.find("skipped")
        s = "failed" if c.find("failure") is not None or c.find("error") is not None else "skipped" if sk is not None else "passed"
        st[s] += 1; by_file.setdefault(f, Counter())[s] += 1
        if sk is not None: skipped.append("%s::%s - %s" % (f, c.get("name"), sk.get("message")))
    db = "postgresql" if backend == "postgres" else "sqlite"
    return dict(backend=db, total=sum(st.values()), passed=st["passed"], failed=st["failed"], skipped=st["skipped"], skipped_tests=skipped,
                duration_seconds=float(suite.get("time", 0)), exit_code=p.returncode, by_file={k: dict(v) for k, v in sorted(by_file.items())})


reports = [run("sqlite")]
try:
    import pgserver  # noqa: F401
    reports.append(run("postgres"))
except ImportError:
    reports.append(dict(backend="postgresql", status="NOT_RUN", reason="pgserver is not installed (pip install -r requirements-pgtest.txt); PostgreSQL compatibility is UNVERIFIED"))
out = dict(runs=reports)
json.dump(out, open(os.path.join(root, "docs", "test_report.json"), "w"), indent=2)
for r in reports:
    print(json.dumps({k: v for k, v in r.items() if k not in ("by_file", "skipped_tests")}))
sys.exit(1 if any(r.get("failed") or r.get("exit_code") for r in reports) else 0)
