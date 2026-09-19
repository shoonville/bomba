#!/usr/bin/env python3
"""Compare SHOT debug lines between a host log and a client log for one peer: where does the
client's predicted hit test disagree with the server's authoritative one?"""
import re, sys
host_log, client_log = sys.argv[1], sys.argv[2]
peer = int(sys.argv[3]) if len(sys.argv) > 3 else None
rx = re.compile(r"SHOT peer=(-?\d+) tick=(\d+) kind=(\w+) victim=(-?\d+) dist=([\d.]+) view=([\d.]+) o=([-\d.,]+) d=([-\d.,]+) hh=([-\d.]+)")
def load(p):
    out = {}
    for line in open(p, errors="replace"):
        m = rx.search(line)
        if m:
            k = (int(m.group(1)), int(m.group(2)))
            out[k] = dict(kind=m.group(3), victim=int(m.group(4)), dist=float(m.group(5)), view=float(m.group(6)),
                          o=m.group(7), d=m.group(8), hh=float(m.group(9)))
    return out
h, c = load(host_log), load(client_log)
if peer is None:
    peers = {k[0] for k in c if k[0] > 1}
    peer = sorted(peers)[0] if peers else 0
keys = sorted(k for k in c if k[0] == peer)
hits_c = sum(1 for k in keys if c[k]["kind"] in ("body", "head"))
agree = 0; missing = 0; mism = []
for k in keys:
    if k not in h:
        missing += 1; continue
    a, b = c[k], h[k]
    same = a["kind"] == b["kind"] and a["victim"] == b["victim"]
    if same:
        agree += 1
    else:
        mism.append((k, a, b))
print(f"peer {peer}: client shots {len(keys)}, predicted hits {hits_c}, server saw {len(keys)-missing}, agree {agree}, disagree {len(mism)}, missing on server {missing}")
for k, a, b in mism[:12]:
    print(f"  tick {k[1]}: client {a['kind']}/{a['victim']} d={a['dist']:.1f} view={a['view']:.1f} o={a['o']} dir={a['d']}")
    print(f"             server {b['kind']}/{b['victim']} d={b['dist']:.1f} view={b['view']:.1f} o={b['o']} dir={b['d']}")
