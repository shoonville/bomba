#!/usr/bin/env python3
"""Diff two trajectory CSVs (peer,tick rows). Exit 1 if any overlapping row differs."""
import csv, sys
a, b = sys.argv[1], sys.argv[2]
show = int(sys.argv[3]) if len(sys.argv) > 3 else 6
def load(p):
    rows = {}
    with open(p) as f:
        for row in csv.DictReader(f):
            rows[(int(row["peer"]), int(row["tick"]))] = row
    return rows
ra, rb = load(a), load(b)
common = sorted(set(ra) & set(rb))
if not common:
    print("FAIL: no overlapping ticks (%d vs %d rows)" % (len(ra), len(rb))); sys.exit(1)
cols = ("x", "y", "z", "health", "kills", "deaths", "yaw")
diffs = [k for k in common if any(ra[k][c] != rb[k][c] for c in cols)]
print("compared %d (peer,tick) rows over ticks %d..%d; %d differ" % (len(common), common[0][1], common[-1][1], len(diffs)))
by_peer = {}
for k in diffs:
    by_peer.setdefault(k[0], []).append(k[1])
for p, ticks in sorted(by_peer.items()):
    print("  peer %d: %d rows differ, ticks %s%s" % (p, len(ticks), ticks[:10], "..." if len(ticks) > 10 else ""))
for k in diffs[:show]:
    x, y = ra[k], rb[k]
    changed = {c: (x[c], y[c]) for c in cols if x[c] != y[c]}
    print("  peer %d tick %d: %s" % (k[0], k[1], changed))
sys.exit(1 if diffs else 0)
