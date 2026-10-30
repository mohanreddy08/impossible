"""Load test: N phones sync at the same time (each with its own phone API key), like the app does: push a batch from the outbox, then pull.

    python scripts/load_test.py --base http://127.0.0.1:8000 --admin-user admin --admin-password ... --phones 50 --rounds 5

Each round per phone: one push of --ops new records (a household + visits; the first round also re-sends the previous batch to exercise
the idempotent duplicate path) and one pull. Reports p50/p95/max latency per request type, errors, and checks that no household was
created twice. Writes nothing but synthetic records with ids LT-<run>-*."""
import argparse
import asyncio
import os
import statistics
import sys
import time
import uuid

import httpx


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))] if xs else float("nan")


async def phone(n: int, key: str, a, run: str, out: dict):
    h = {"X-API-Key": key, "User-Agent": "load-test/1.0"}
    async with httpx.AsyncClient(base_url=a.base, timeout=60, verify=not a.insecure) as c:
        prev = None
        for r in range(a.rounds):
            hid = "LT-%s-%02d-%02d" % (run, n, r)
            ops = [dict(op_id="op-%s-%d-%d-h" % (run, n, r), entity_type="household", entity_id=hid, op_type="create",
                        payload=dict(village_id="VIL-SYN-01", assigned_worker_id=a.worker(n), household_member_count=3, eligible_followup_categories=["ROUTINE"]))]
            for k in range(a.ops - 1):
                ops.append(dict(op_id="op-%s-%d-%d-v%d" % (run, n, r, k), entity_type="visit", entity_id="LTV-%s-%02d-%02d-%02d" % (run, n, r, k), op_type="create",
                                payload=dict(household_id=hid, worker_id=a.worker(n), scheduled_date="2026-11-%02d" % (k % 27 + 1), visit_reason="ROUTINE")))
            body = dict(installation_id="install-%s-%03d" % (run, n), operations=ops + (prev or []))
            t = time.perf_counter()
            try:
                resp = await c.post("/api/v1/sync/push", json=body, headers=h)
                out["push"].append((time.perf_counter() - t) * 1000)
                if resp.status_code != 200:
                    out["errors"].append("push %d" % resp.status_code)
                else:
                    res = resp.json()["results"]
                    out["acked"] += sum(1 for x in res if x["acknowledged"] and not x["duplicate"])
                    out["dups"] += sum(1 for x in res if x["duplicate"])
                    out["retry"] += sum(1 for x in res if x["status"] == "FAILED_RETRYABLE")
            except httpx.HTTPError as e:
                out["errors"].append(type(e).__name__)
            prev = ops if r == 0 else None                      # round 2 re-sends round 1: the "phone never saw the answer" case
            t = time.perf_counter()
            try:
                resp = await c.get("/api/v1/sync/pull", params=dict(entity_types="household,visit,referral", limit=200), headers=h)
                out["pull"].append((time.perf_counter() - t) * 1000)
                if resp.status_code != 200:
                    out["errors"].append("pull %d" % resp.status_code)
            except httpx.HTTPError as e:
                out["errors"].append(type(e).__name__)


async def main_async(a) -> int:
    run = uuid.uuid4().hex[:6]
    async with httpx.AsyncClient(base_url=a.base, timeout=60, verify=not a.insecure) as c:
        tok = (await c.post("/api/v1/auth/login", json=dict(username=a.admin_user, password=a.admin_password))).json()["access_token"]
        adm = {"Authorization": "Bearer " + tok}
        keys = []
        for n in range(a.phones):
            r = await c.post("/api/v1/admin/phones", json=dict(worker_id=a.worker(n), label="load-test %s #%d" % (run, n)), headers=adm)
            r.raise_for_status()
            keys.append((r.json()["key_id"], r.json()["api_key"]))
    out = dict(push=[], pull=[], errors=[], acked=0, dups=0, retry=0)
    t0 = time.perf_counter()
    await asyncio.gather(*(phone(n, k, a, run, out) for n, (_, k) in enumerate(keys)))
    wall = time.perf_counter() - t0
    async with httpx.AsyncClient(base_url=a.base, timeout=60, verify=not a.insecure) as c:
        found = (await c.get("/api/v1/dashboard/households", params=dict(q="LT-" + run, limit=200), headers=adm)).json()["total"]
        for kid, _ in keys:                                      # clean up: these keys are of no use after the test
            await c.post("/api/v1/admin/phones/%s/revoke" % kid, json={}, headers=adm)
    expected = a.phones * a.rounds
    print("phones=%d rounds=%d ops/push=%d  wall=%.1fs  requests=%d" % (a.phones, a.rounds, a.ops, wall, len(out["push"]) + len(out["pull"])))
    for k in ("push", "pull"):
        xs = out[k]
        print("  %-5s n=%-4d p50=%7.1f ms  p95=%7.1f ms  max=%7.1f ms  mean=%7.1f ms" % (k, len(xs), pct(xs, 50), pct(xs, 95), max(xs), statistics.mean(xs)))
    allx = out["push"] + out["pull"]
    print("  all   n=%-4d p95=%7.1f ms" % (len(allx), pct(allx, 95)))
    print("  ops stored=%d  duplicates answered=%d  retryable=%d  errors=%d %s" % (out["acked"], out["dups"], out["retry"], len(out["errors"]), sorted(set(out["errors"]))[:5]))
    print("  households created=%d (expected %d, each exactly once)" % (found, expected))
    return 0 if found == expected and not out["errors"] else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="http://127.0.0.1:8000")
    ap.add_argument("--admin-user", default="admin")
    ap.add_argument("--admin-password", default=os.environ.get("ADMIN_PASSWORD"))
    ap.add_argument("--phones", type=int, default=50)
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--ops", type=int, default=5, help="operations per push (1 household + visits)")
    ap.add_argument("--insecure", action="store_true", help="do not verify TLS (self-signed test servers only)")
    a = ap.parse_args(argv)
    if not a.admin_password:
        ap.error("--admin-password (or ADMIN_PASSWORD) is required")
    workers = ["WRK-SYN-%03d" % i for i in range(1, 7)]
    a.worker = lambda n: workers[n % len(workers)]
    return asyncio.run(main_async(a))


if __name__ == "__main__":
    sys.exit(main())
