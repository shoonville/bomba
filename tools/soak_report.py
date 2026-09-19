#!/usr/bin/env python3
"""Join host and client soak reports into the numbers NETPLAN.md §11 asks for."""
import csv, glob, json, os, sys, statistics

out = sys.argv[1] if len(sys.argv) > 1 else "reports"
label = sys.argv[2] if len(sys.argv) > 2 else "soak_bad"

def load_summary(p):
    with open(p) as f:
        return json.load(f)

def load_traj(p):
    rows = {}
    with open(p) as f:
        for row in csv.DictReader(f):
            rows[(int(row["peer"]), int(row["tick"]))] = row
    return rows

host = load_summary(os.path.join(out, f"{label}_host_summary.json"))
host_traj = load_traj(os.path.join(out, f"{label}_host_traj.csv"))
print(f"== {label} ==")
print(f"host: ticks {host['start_tick']}..{host['end_tick']}, rollback mean {host['rollback_ticks_mean']:.2f} max {host['rollback_ticks_max']}, "
      f"loop ms mean {host['tick_loop_ms_mean']:.2f} p95 {host['tick_loop_ms_p95']:.2f}, "
      f"up {host['net'].get('bytes_sent',0)/1024:.1f} KB down {host['net'].get('bytes_received',0)/1024:.1f} KB")
for pid, p in host["players"].items():
    print(f"  host view of {p['name']:<14} kills {p['kills']:>2} deaths {p['deaths']:>2} shots {p['shots_fired']:>3} hits_landed {p['hits_landed']:>3}")
print(f"  kills broadcast: {len(host['kills'])}")

for cp in sorted(glob.glob(os.path.join(out, f"{label}_client*_summary.json"))):
    c = load_summary(cp)
    peer = c["peer_id"]
    ct = load_traj(cp.replace("_summary.json", "_traj.csv"))
    # local prediction error: client's own predicted position vs host truth at the same tick
    # Death ticks (host truth): a respawn teleports the body, so the client cannot predict those
    # ticks by design; they are reported separately as snaps and excluded here.
    death_ticks = []
    last_deaths = None
    for (pp, t) in sorted(k for k in host_traj if k[0] == peer):
        d = int(host_traj[(pp, t)]["deaths"])
        if last_deaths is not None and d != last_deaths:
            death_ticks.append(t)
        last_deaths = d
    def near_death(t):
        return any(abs(t - dt) <= 12 for dt in death_ticks)
    errs = []
    errs_all = []
    for (pp, t), row in ct.items():
        if pp != peer:
            continue
        h = host_traj.get((pp, t))
        if h is None:
            continue
        dx = float(row["x"]) - float(h["x"]); dy = float(row["y"]) - float(h["y"]); dz = float(row["z"]) - float(h["z"])
        e = (dx*dx + dy*dy + dz*dz) ** 0.5
        errs_all.append(e)
        if not near_death(t):
            errs.append(e)
    me = c["players"].get(str(peer), {})
    hv = host["players"].get(str(peer), {})
    mean = statistics.mean(errs) if errs else float("nan")
    p95 = sorted(errs)[int(0.95 * (len(errs) - 1))] if errs else float("nan")
    conf = hv.get("hits_landed", 0)
    pred = me.get("hits_predicted", 0)
    rate = (conf / pred) if pred else float("nan")
    cond = c["net"].get("conditioner", {})
    print(f"client #{peer} ({me.get('name','?')}): rtt mean {c['rtt_ms_mean']:.1f} max {c['rtt_ms_max']:.1f} ms | "
          f"rollback mean {c['rollback_ticks_mean']:.2f} max {c['rollback_ticks_max']} | loop p95 {c['tick_loop_ms_p95']:.2f} ms")
    mean_all = statistics.mean(errs_all) if errs_all else float("nan")
    print(f"  mispredict mean {mean:.4f} m p95 {p95:.4f} m over {len(errs)} ticks (excluding ±12 ticks around {len(death_ticks)} deaths; mean incl. deaths {mean_all:.3f} m) | snaps {me.get('correction_snaps',0)}")
    print(f"  shots {me.get('shots_fired',0)} hit_predicted {pred} hit_confirmed(host) {conf} confirm_rate {rate:.2f}")
    # Post-death desync detector: how many ticks after each host-side death does the client's own
    # deaths counter catch up? More than 30 ticks (500 ms) is an outage, not latency.
    lags = []
    for dt in death_ticks:
        target = int(host_traj[(peer, dt)]["deaths"])
        caught = None
        for t in range(dt, dt + 400):
            r = ct.get((peer, t))
            if r is not None and int(r["deaths"]) >= target:
                caught = t; break
        lags.append((dt, (caught - dt) if caught is not None else 400))
    outages = [(dt, lg) for dt, lg in lags if lg > 30]
    print(f"  death->client lag ticks: {[lg for _, lg in lags]} | outages (>30): {outages}")
    print(f"  bytes up {c['net'].get('bytes_sent',0)/1024:.1f} KB down {c['net'].get('bytes_received',0)/1024:.1f} KB | "
          f"conditioner {cond.get('profile','?')}: fwd up {cond.get('forwarded_up',0)} down {cond.get('forwarded_down',0)} "
          f"dropped up {cond.get('dropped_up',0)} down {cond.get('dropped_down',0)}")
