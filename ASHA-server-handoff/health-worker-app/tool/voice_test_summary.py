#!/usr/bin/env python3
"""Prints the Voice Test result table.

  adb pull /sdcard/Android/data/in.healthcompanion.health_companion/files/voice_test.csv
  python3 tool/voice_test_summary.py voice_test.csv [voice_test_ram.csv]

For every engine and network state (online / offline): how many takes were Correct, Some words wrong and Wrong, the average time after
Stop in milliseconds, how often the right danger rule fired and Q&A returned the right passage, and the peak memory (total PSS) the app
reached while that engine was being used (needs the file from tool/voice_test_ram.sh). If a take was rated twice the latest rating wins.
"""
import csv
import sys


def load(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    rows = load(sys.argv[1])
    ram = []
    if len(sys.argv) > 2:
        for r in load(sys.argv[2]):
            try:
                ram.append((int(r["phone_epoch_ms"]), int(r["total_pss_kb"])))
            except (ValueError, KeyError):
                pass
    latest = {}
    for r in rows:
        latest[(r["session"], r["sentence_id"], r["engine"], r["network"])] = r
    groups = {}
    for r in latest.values():
        groups.setdefault((r["engine"], r["network"]), []).append(r)

    baseline = None
    if ram and rows:
        first = min(int(r["started_at_ms"]) for r in rows if r["started_at_ms"].isdigit())
        before = [p for t, p in ram if t < first]
        baseline = min(before) if before else min(p for _, p in ram)

    head = ["Engine", "Net", "Takes", "Correct", "Some wrong", "Wrong", "Avg ms", "Danger ok", "Q&A ok", "Peak RAM MB"]
    table = []
    for (engine, net), rs in sorted(groups.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        n = len(rs)
        cnt = lambda k: sum(1 for r in rs if r["rating"] == k)
        avg = round(sum(int(r["ms_after_stop"] or 0) for r in rs) / n)
        peak = ""
        if ram:
            vals = []
            for r in rs:
                a, b = int(r["started_at_ms"] or 0), int(r["ended_at_ms"] or 0) + 2000
                vals += [p for t, p in ram if a <= t <= b]
            if vals:
                peak = f"{max(vals) / 1024:.0f}"
        table.append([
            engine, net, n, cnt("correct"), cnt("some_wrong"), cnt("wrong"), avg,
            f'{sum(r["danger_ok"] == "1" for r in rs)}/{n}', f'{sum(r["qa_ok"] == "1" for r in rs)}/{n}', peak,
        ])
    widths = [max(len(str(x)) for x in col) for col in zip(head, *table)]
    line = lambda cells: "  ".join(str(c).ljust(w) for c, w in zip(cells, widths))
    print(line(head))
    print(line(["-" * w for w in widths]))
    for t in table:
        print(line(t))
    if baseline:
        print(f"\nApp memory before the first take: {baseline / 1024:.0f} MB (total PSS). Peak RAM above is the whole app, not the engine alone.")


if __name__ == "__main__":
    main()
