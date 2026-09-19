#!/usr/bin/env python3
"""Generates board/boards/main.json (BOMBA BAY): one big loop sampled every ~3.7 m with four
branches (a raised bridge, two inner cuts, an outside item-rich detour). Deterministic (seed 11).
Run from the repo root: python3 tools/gen_board.py"""
import math, json, random
from collections import Counter

rng = random.Random(11)
def dist(a, b): return math.dist(a, b)

def loop_pt(t):
    rw = 1.0 + 0.06 * math.sin(3 * t + 0.6)
    return (24.0 * math.cos(t) * rw, 18.0 * math.sin(t) * (1.0 + 0.10 * math.cos(2 * t)))

loop = []
N = 6000
prev = loop_pt(0.0); loop.append(prev); acc = 0.0
for i in range(1, N + 1):
    t = 2 * math.pi * i / N
    p = loop_pt(t); acc += dist(p, prev); prev = p
    if acc >= 3.7:
        loop.append(p); acc = 0.0
if dist(loop[-1], loop[0]) < 3.0:
    loop.pop()
L = len(loop)

def elev(i):
    return round((0.45 * (1 + math.sin(i * 2 * math.pi / L * 2 + 0.8))) / 0.15) * 0.15

spaces = []
def add(id, pos, typ, nxt, goal=False):
    spaces.append({"id": id, "position": [round(pos[0], 2), round(pos[1], 2), round(pos[2], 2)],
                   "type": typ, "next": list(nxt), "goal": goal})

def bowed(a, b, nx, nz, bulge, f):
    return (a[0] + (b[0] - a[0]) * f + nx * bulge * math.sin(f * math.pi),
            a[1] + (b[1] - a[1]) * f + nz * bulge * math.sin(f * math.pi))

def make_branch(i, j, side, y, taken):
    """Interior points of a path from loop[i] to loop[j], bowed toward (side=+1) or away from
    (side=-1) the board centre by the smallest bulge that keeps every point 3.1 m from every
    loop space and every other branch space. Spacing along the path is ~3.9 m."""
    a = loop[i]; b = loop[j]
    dx, dz = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(dx, dz)
    nx, nz = -dz / ln, dx / ln
    mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    if (nx * -mid[0] + nz * -mid[1]) * side < 0:
        nx, nz = -nx, -nz
    for bulge in [x * 0.5 for x in range(4, 44)]:
        fine = [bowed(a, b, nx, nz, bulge, f / 300.0) for f in range(301)]
        seg = [dist(fine[m], fine[m + 1]) for m in range(300)]
        length = sum(seg)
        k = max(1, round(length / 3.9) - 1)
        step = length / (k + 1)
        pts = []
        acc = 0.0; want = step; m = 0
        while len(pts) < k and m < 300:
            acc += seg[m]; m += 1
            if acc >= want:
                pts.append((fine[m][0], y, fine[m][1])); want += step
        ok = all(dist((p[0], p[2]), q) >= 3.1 for p in pts for q in loop) and \
             all(dist(p, q) >= 3.1 for p in pts for q in taken)
        if ok and len(pts) == k:
            return pts
    raise SystemExit("no bulge works for branch %d-%d" % (i, j))

q = L // 4
branches = [
    ("A", 3, 20, 1, 1.2),    # long bridge across the middle
    ("B", 8, 14, 1, 0.9),    # inner cut, top
    ("C", 25, 32, 1, 0.6),   # inner cut, bottom right
    ("D", 15, 19, -1, 0.3),  # outside detour, top left, item-rich
]

def pick_type(is_branch, kind):
    r = rng.random()
    if kind == "D":
        return "item" if r < 0.5 else ("coin" if r < 0.8 else "event")
    if is_branch:
        return "lose" if r < 0.28 else ("coin" if r < 0.6 else ("item" if r < 0.8 else "blank"))
    if r < 0.40: return "coin"
    if r < 0.64: return "blank"
    if r < 0.76: return "item"
    if r < 0.88: return "lose"
    return "event"

branch_pts = {}
taken = []
for name, i, j, side, y in branches:
    branch_pts[name] = make_branch(i, j % L, side, y, taken)
    taken += branch_pts[name]

for i, (x, z) in enumerate(loop):
    nxt = ["L%d" % ((i + 1) % L)]
    for name, bi, bj, side, y in branches:
        if bi == i:
            nxt.append("%s1" % name)
    typ = "start" if i == 0 else pick_type(False, "")
    if i in (1, 2) and typ == "lose":
        typ = "coin"
    if i == L // 2 + 1:
        typ = "shield"   # the one safe spot, opposite the start
    add("L%d" % i, (x, elev(i), z), typ, nxt)
for name, bi, bj, side, y in branches:
    pts = branch_pts[name]
    for m, p in enumerate(pts):
        nxt = ["%s%d" % (name, m + 2)] if m + 1 < len(pts) else ["L%d" % (bj % L)]
        add("%s%d" % (name, m + 1), p, pick_type(True, name), nxt)

for i in range(2, L, 5):
    s = spaces[i]
    if s["type"] in ("coin", "blank", "event"):
        s["goal"] = True
for name, bi, bj, side, y in branches:
    k = len(branch_pts[name])
    mid = "%s%d" % (name, (k + 1) // 2)
    for s in spaces:
        if s["id"] == mid and s["type"] != "lose":
            s["goal"] = True

board = {"id": "main", "display_name": "BOMBA BAY", "start": "L0", "spaces": spaces}
json.dump(board, open("board/boards/main.json", "w"), indent=1)

byid = {s["id"]: s for s in spaces}
mn = min(((dist(a["position"], b["position"]), a["id"], b["id"]) for ai, a in enumerate(spaces) for b in spaces[ai + 1:]))
hops = [(dist(s["position"], byid[n]["position"]), s["id"], n) for s in spaces for n in s["next"]]
forks = [s["id"] for s in spaces if len(s["next"]) > 1]
print("spaces", len(spaces), "loop", L, "forks", forks, "goals", sum(1 for s in spaces if s["goal"]))
print("min pair %.2f (%s-%s)" % mn, "hop min %.2f max %.2f" % (min(hops)[0], max(hops)[0]))
print(dict(Counter(s["type"] for s in spaces)))
assert mn[0] >= 3.0 and max(hops)[0] <= 5.6, "geometry check failed"
