extends SceneTree
## Every lap from the start back to the start on BOMBA BAY, and the turns each takes with the die
## (a lap is what the board size is judged by: Sean wants about 20 turns).
##   GODOT --headless --path . --script tools/board_laps.gd
func _initialize() -> void:
	var g := BoardGraph.load_file("res://board/boards/main.json")
	var sides := int(TuningLoader.load_file("res://tuning/board.json").get("dice_sides", 8))
	var mean_roll := (1.0 + sides) / 2.0
	var laps: Array = []
	_walk(g, g.start_id, g.start_id, 0, {}, laps)
	laps.sort()
	print("spaces %d, forks %d, d%d (mean roll %.1f)" % [g.spaces.size(), _forks(g), sides, mean_roll])
	print("laps (steps from the start back to the start): %s" % str(laps))
	var total := 0
	for l in laps:
		total += int(l)
	var mean_lap := float(total) / laps.size()
	print("shortest %d steps = %.1f turns, longest %d = %.1f turns, mean %.1f = %.1f turns" % [
		laps[0], laps[0] / mean_roll, laps[-1], laps[-1] / mean_roll, mean_lap, mean_lap / mean_roll])
	for target: int in [15, 20, 25]:
		var steps: float = target * mean_roll
		print("%d turns a lap needs a %.0f-step lap: scale the board by %.2f, about %d spaces" % [
			target, steps, steps / mean_lap, roundi(g.spaces.size() * steps / mean_lap)])
	quit(0)

func _forks(g: BoardGraph) -> int:
	var n := 0
	for sid in g.ids():
		if g.is_fork(sid):
			n += 1
	return n

func _walk(g: BoardGraph, at: String, start: String, depth: int, seen: Dictionary, laps: Array) -> void:
	for nx in g.next_of(at):
		var n := str(nx)
		if n == start:
			laps.append(depth + 1)
		elif not seen.has(n):
			seen[n] = true
			_walk(g, n, start, depth + 1, seen, laps)
			seen.erase(n)
