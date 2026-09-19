#!/usr/bin/env python3
"""How stale/mislabelled is a client's view of remote players? Compares the client's recorded
remote history (peer,tick,pos) with the host's authoritative trajectory at the same tick."""
import csv, sys, statistics
host_traj, client_remote = sys.argv[1], sys.argv[2]
def load(p):
    rows = {}
    with open(p) as f:
        for row in csv.DictReader(f):
            rows[(int(row["peer"]), int(row["tick"]))] = (float(row["x"]), float(row["y"]), float(row["z"]))
    return rows
h, c = load(host_traj), load(client_remote)
by_peer = {}
for k, pos in c.items():
    t = h.get(k)
    if t is None:
        continue
    e = sum((a - b) ** 2 for a, b in zip(pos, t)) ** 0.5
    by_peer.setdefault(k[0], []).append((k[1], e))
for peer, lst in sorted(by_peer.items()):
    errs = [e for _, e in lst]
    big = [(t, e) for t, e in lst if e > 0.3]
    p95 = sorted(errs)[int(0.95 * (len(errs) - 1))]
    print(f"peer {peer}: {len(errs)} ticks compared, mean err {statistics.mean(errs):.4f} m, p95 {p95:.4f} m, max {max(errs):.3f} m, >0.3m: {len(big)}")
    for t, e in big[:8]:
        print(f"   tick {t}: {e:.3f} m")
