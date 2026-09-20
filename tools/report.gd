extends SceneTree
## Harness report tools in GDScript, so a machine needs only Godot (the M4 had Python; Sean's
## Windows desktop does not). Replaces traj_diff.py, soak_report.py, shot_diff.py and
## remote_diff.py line for line. One script, four commands, args after `--`:
##   GODOT --headless --path . --script tools/report.gd -- traj_diff A_traj.csv B_traj.csv [show]
##   GODOT --headless --path . --script tools/report.gd -- soak_report DIR LABEL
##   GODOT --headless --path . --script tools/report.gd -- shot_diff HOST.log CLIENT.log [peer]
##   GODOT --headless --path . --script tools/report.gd -- remote_diff HOST_traj.csv CLIENT_remote.csv
## Relative paths are taken from the project folder. Exit 1 when traj_diff finds a differing
## row, 2 on a usage or file error, 0 otherwise.

const TRAJ_COLS := ["x", "y", "z", "health", "kills", "deaths", "yaw"]
const USAGE := "usage: report.gd -- traj_diff A B [show] | soak_report DIR LABEL | shot_diff HOST.log CLIENT.log [peer] | remote_diff HOST_traj.csv CLIENT_remote.csv"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var code := 2
	if args.is_empty():
		printerr(USAGE)
	else:
		match args[0]:
			"traj_diff":
				code = _traj_diff(args.slice(1))
			"soak_report":
				code = _soak_report(args.slice(1))
			"shot_diff":
				code = _shot_diff(args.slice(1))
			"remote_diff":
				code = _remote_diff(args.slice(1))
			_:
				printerr(USAGE)
	quit(code)


# --- traj_diff -----------------------------------------------------------------------------------

## Diff two trajectory CSVs (peer,tick rows). Exit 1 if any overlapping row differs.
func _traj_diff(a: Array) -> int:
	if a.size() < 2:
		printerr(USAGE)
		return 2
	var show := int(a[2]) if a.size() > 2 else 6
	var ra := _load_rows(a[0])
	var rb := _load_rows(a[1])
	if ra.is_empty() or rb.is_empty():
		return 2
	var common: Array = []
	for k in ra:
		if rb.has(k):
			common.append(k)
	common.sort()
	if common.is_empty():
		print("FAIL: no overlapping ticks (%d vs %d rows)" % [ra.size(), rb.size()])
		return 1
	var diffs: Array = []
	for k in common:
		for c in TRAJ_COLS:
			if ra[k][c] != rb[k][c]:
				diffs.append(k)
				break
	print("compared %d (peer,tick) rows over ticks %d..%d; %d differ" % [
		common.size(), common[0].y, common.back().y, diffs.size()])
	var by_peer := {}
	for k in diffs:
		if not by_peer.has(k.x):
			by_peer[k.x] = []
		by_peer[k.x].append(k.y)
	var peers := by_peer.keys()
	peers.sort()
	for p in peers:
		var ticks: Array = by_peer[p]
		print("  peer %d: %d rows differ, ticks %s%s" % [p, ticks.size(), ticks.slice(0, 10), "..." if ticks.size() > 10 else ""])
	for k in diffs.slice(0, show):
		var changed := {}
		for c in TRAJ_COLS:
			if ra[k][c] != rb[k][c]:
				changed[c] = [ra[k][c], rb[k][c]]
		print("  peer %d tick %d: %s" % [k.x, k.y, changed])
	if diffs.is_empty():
		print("PASS: trajectories identical to the byte")
		return 0
	print("FAIL: %d rows differ" % diffs.size())
	return 1


# --- soak_report ---------------------------------------------------------------------------------

## Join host and client soak reports into the numbers NETPLAN.md §11 asks for.
func _soak_report(a: Array) -> int:
	var out: String = a[0] if a.size() > 0 else "reports"
	var label: String = a[1] if a.size() > 1 else "soak_bad"
	var host = _load_json(out.path_join("%s_host_summary.json" % label))
	if host == null:
		return 2
	var host_traj := _load_rows(out.path_join("%s_host_traj.csv" % label))
	var hnet: Dictionary = host.get("net", {})
	print("== %s ==" % label)
	print("host: ticks %d..%d, rollback mean %.2f max %d, loop ms mean %.2f p95 %.2f, up %.1f KB down %.1f KB" % [
		int(host["start_tick"]), int(host["end_tick"]), float(host["rollback_ticks_mean"]),
		int(host["rollback_ticks_max"]), float(host["tick_loop_ms_mean"]), float(host["tick_loop_ms_p95"]),
		float(hnet.get("bytes_sent", 0)) / 1024.0, float(hnet.get("bytes_received", 0)) / 1024.0])
	var hplayers: Dictionary = host["players"]
	for pid in hplayers:
		var p: Dictionary = hplayers[pid]
		print("  host view of %-14s kills %2d deaths %2d shots %3d hits_landed %3d" % [
			p["name"], int(p["kills"]), int(p["deaths"]), int(p["shots_fired"]), int(p["hits_landed"])])
	print("  kills broadcast: %d" % (host["kills"] as Array).size())

	var client_files: Array[String] = []
	var dir := DirAccess.open(_abs(out))
	if dir != null:
		for fn in dir.get_files():
			if fn.begins_with(label + "_client") and fn.ends_with("_summary.json"):
				client_files.append(fn)
	client_files.sort()
	for cf in client_files:
		var c = _load_json(out.path_join(cf))
		if c == null:
			continue
		var peer := int(c["peer_id"])
		var ct := _load_rows(out.path_join(cf.replace("_summary.json", "_traj.csv")))
		# Death ticks (host truth): a respawn teleports the body, so the client cannot predict
		# those ticks by design; they are reported separately as snaps and excluded here.
		var death_ticks: Array[int] = []
		var keys: Array = []
		for k in host_traj:
			if k.x == peer:
				keys.append(k)
		keys.sort()
		var last_deaths := 0
		var have_last := false
		for k in keys:
			var d := int(host_traj[k]["deaths"])
			if have_last and d != last_deaths:
				death_ticks.append(k.y)
			last_deaths = d
			have_last = true
		var errs: Array[float] = []
		var errs_all: Array[float] = []
		for k in ct:
			if k.x != peer or not host_traj.has(k):
				continue
			var e := _dist(ct[k], host_traj[k])
			errs_all.append(e)
			if not _near_death(k.y, death_ticks):
				errs.append(e)
		var cplayers: Dictionary = c["players"]
		var me: Dictionary = cplayers.get(str(peer), {})
		var hv: Dictionary = hplayers.get(str(peer), {})
		var conf := int(hv.get("hits_landed", 0))
		var pred := int(me.get("hits_predicted", 0))
		var rate := (float(conf) / float(pred)) if pred > 0 else NAN
		var cnet: Dictionary = c.get("net", {})
		var cond: Dictionary = cnet.get("conditioner", {})
		print("client #%d (%s): rtt mean %.1f max %.1f ms | rollback mean %.2f max %d | loop p95 %.2f ms" % [
			peer, me.get("name", "?"), float(c["rtt_ms_mean"]), float(c["rtt_ms_max"]),
			float(c["rollback_ticks_mean"]), int(c["rollback_ticks_max"]), float(c["tick_loop_ms_p95"])])
		print("  mispredict mean %.4f m p95 %.4f m over %d ticks (excluding ±12 ticks around %d deaths; mean incl. deaths %.3f m) | snaps %d" % [
			_mean(errs), _p95(errs), errs.size(), death_ticks.size(), _mean(errs_all), int(me.get("correction_snaps", 0))])
		print("  shots %d hit_predicted %d hit_confirmed(host) %d confirm_rate %.2f" % [
			int(me.get("shots_fired", 0)), pred, conf, rate])
		# Post-death desync detector: how many ticks after each host-side death does the client's
		# own deaths counter catch up? More than 30 ticks (500 ms) is an outage, not latency.
		var lags: Array[int] = []
		for dt in death_ticks:
			var target := int(host_traj[Vector2i(peer, dt)]["deaths"])
			var caught := -1
			for t in range(dt, dt + 400):
				var r = ct.get(Vector2i(peer, t))
				if r != null and int(r["deaths"]) >= target:
					caught = t
					break
			lags.append((caught - dt) if caught >= 0 else 400)
		var outages: Array = []
		for i in lags.size():
			if lags[i] > 30:
				outages.append([death_ticks[i], lags[i]])
		print("  death->client lag ticks: %s | outages (>30): %s" % [lags, outages])
		print("  bytes up %.1f KB down %.1f KB | conditioner %s: fwd up %d down %d dropped up %d down %d" % [
			float(cnet.get("bytes_sent", 0)) / 1024.0, float(cnet.get("bytes_received", 0)) / 1024.0,
			cond.get("profile", "?"), int(cond.get("forwarded_up", 0)), int(cond.get("forwarded_down", 0)),
			int(cond.get("dropped_up", 0)), int(cond.get("dropped_down", 0))])
	return 0


func _near_death(t: int, death_ticks: Array[int]) -> bool:
	for dt in death_ticks:
		if absi(t - dt) <= 12:
			return true
	return false


# --- shot_diff -----------------------------------------------------------------------------------

## Compare SHOT debug lines between a host log and a client log for one peer: where does the
## client's predicted hit test disagree with the server's authoritative one? (needs LOG=1)
func _shot_diff(a: Array) -> int:
	if a.size() < 2:
		printerr(USAGE)
		return 2
	var rx := RegEx.new()
	rx.compile("SHOT peer=(-?\\d+) tick=(\\d+) kind=(\\w+) victim=(-?\\d+) dist=([\\d.]+) view=([\\d.]+) o=([-\\d.,]+) d=([-\\d.,]+) hh=([-\\d.]+)")
	var h := _load_shots(a[0], rx)
	var c := _load_shots(a[1], rx)
	var peer := 0
	if a.size() > 2:
		peer = int(a[2])
	else:
		var peers: Array = []
		for k in c:
			if k.x > 1 and not peers.has(k.x):
				peers.append(k.x)
		peers.sort()
		peer = peers[0] if not peers.is_empty() else 0
	var keys: Array = []
	for k in c:
		if k.x == peer:
			keys.append(k)
	keys.sort()
	var hits_c := 0
	for k in keys:
		if c[k]["kind"] in ["body", "head"]:
			hits_c += 1
	var agree := 0
	var missing := 0
	var mism: Array = []
	for k in keys:
		if not h.has(k):
			missing += 1
			continue
		var ca: Dictionary = c[k]
		var hb: Dictionary = h[k]
		if ca["kind"] == hb["kind"] and ca["victim"] == hb["victim"]:
			agree += 1
		else:
			mism.append([k, ca, hb])
	print("peer %d: client shots %d, predicted hits %d, server saw %d, agree %d, disagree %d, missing on server %d" % [
		peer, keys.size(), hits_c, keys.size() - missing, agree, mism.size(), missing])
	for m in mism.slice(0, 12):
		var k: Vector2i = m[0]
		var ca: Dictionary = m[1]
		var hb: Dictionary = m[2]
		print("  tick %d: client %s/%d d=%.1f view=%.1f o=%s dir=%s" % [k.y, ca["kind"], ca["victim"], ca["dist"], ca["view"], ca["o"], ca["d"]])
		print("             server %s/%d d=%.1f view=%.1f o=%s dir=%s" % [hb["kind"], hb["victim"], hb["dist"], hb["view"], hb["o"], hb["d"]])
	return 0


func _load_shots(path: String, rx: RegEx) -> Dictionary:
	var out := {}
	var f := FileAccess.open(_abs(path), FileAccess.READ)
	if f == null:
		printerr("cannot open %s" % path)
		return out
	while not f.eof_reached():
		var m := rx.search(f.get_line())
		if m == null:
			continue
		out[Vector2i(int(m.get_string(1)), int(m.get_string(2)))] = {
			"kind": m.get_string(3), "victim": int(m.get_string(4)), "dist": float(m.get_string(5)),
			"view": float(m.get_string(6)), "o": m.get_string(7), "d": m.get_string(8), "hh": float(m.get_string(9))}
	return out


# --- remote_diff ---------------------------------------------------------------------------------

## How stale/mislabelled is a client's view of remote players? Compares the client's recorded
## remote history (peer,tick,pos) with the host's authoritative trajectory at the same tick.
func _remote_diff(a: Array) -> int:
	if a.size() < 2:
		printerr(USAGE)
		return 2
	var h := _load_rows(a[0])
	var c := _load_rows(a[1])
	if h.is_empty() or c.is_empty():
		return 2
	var by_peer := {}
	for k in c:
		if not h.has(k):
			continue
		if not by_peer.has(k.x):
			by_peer[k.x] = []
		by_peer[k.x].append([k.y, _dist(c[k], h[k])])
	var peers := by_peer.keys()
	peers.sort()
	for peer in peers:
		var lst: Array = by_peer[peer]
		var errs: Array[float] = []
		var small: Array[float] = []
		var big: Array = []
		for x in lst:
			errs.append(x[1])
			if x[1] > 0.3:
				big.append(x)
			else:
				small.append(x[1])
		# Samples over 30 cm are respawn teleports (a death moves the body across the map in one
		# tick); the mean without them is the interpolation error itself.
		print("peer %d: %d ticks compared, mean err %.4f m (%.4f m excluding >0.3m), p95 %.4f m, max %.3f m, >0.3m: %d" % [
			peer, errs.size(), _mean(errs), _mean(small), _p95(errs), errs.max(), big.size()])
		for x in big.slice(0, 8):
			print("   tick %d: %.3f m" % [x[0], x[1]])
	return 0


# --- shared --------------------------------------------------------------------------------------

## A CSV with peer and tick columns, keyed by Vector2i(peer, tick); every value stays a string so
## equality is textual, like the Python originals.
func _load_rows(path: String) -> Dictionary:
	var rows := {}
	var f := FileAccess.open(_abs(path), FileAccess.READ)
	if f == null:
		printerr("cannot open %s" % path)
		return rows
	var header := f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < header.size():
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = line[i]
		rows[Vector2i(int(row["peer"]), int(row["tick"]))] = row
	return rows


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(_abs(path), FileAccess.READ)
	if f == null:
		printerr("cannot open %s" % path)
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		printerr("bad JSON in %s" % path)
	return parsed


func _abs(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)


func _dist(a: Dictionary, b: Dictionary) -> float:
	var dx := float(a["x"]) - float(b["x"])
	var dy := float(a["y"]) - float(b["y"])
	var dz := float(a["z"]) - float(b["z"])
	return sqrt(dx * dx + dy * dy + dz * dz)


func _mean(v: Array[float]) -> float:
	if v.is_empty():
		return NAN
	var s := 0.0
	for x in v:
		s += x
	return s / v.size()


func _p95(v: Array[float]) -> float:
	if v.is_empty():
		return NAN
	var s := v.duplicate()
	s.sort()
	return s[int(0.95 * (s.size() - 1))]
