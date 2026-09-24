class_name BoardRules
extends RefCounted
## The rules (BOARDPLAN.md §1, §4): pure functions over BoardState + BoardGraph + tuning. Each
## mutates the state and returns the events presentation animates. Randomness comes from the
## state's seed and counter, so the same match replays identically on every peer.

## A bot only portals when the target is at least this many steps nearer the goal.
const BOT_PORTAL_MIN_GAIN := 3
const BOT_SHUTTLE_MIN_GAIN := 8   # a bot pays the rocket's fare for this many hops saved to the machine


static func rng(state: BoardState) -> RandomNumberGenerator:
	var r := SeededRng.make_tick(state.seed_value, "board", state.rng_counter)
	state.rng_counter += 1
	return r


static func setup(state: BoardState, graph: BoardGraph, players_data: Array, seed_value: int, cfg: Dictionary) -> Array:
	state.board_id = graph.id
	state.seed_value = seed_value
	state.rng_counter = 0
	state.rounds = int(cfg.get("rounds", 5))
	state.round = 1
	state.players.clear()
	for d in players_data:
		var p := BoardState.PlayerState.from_dict(d)
		p.space = graph.start_id
		p.tickets = int(cfg.get("start_tickets", 5))
		p.toys = 0
		p.items = []
		p.hp = int(cfg.get("hp", 30))
		state.players.append(p)
	state.blood.clear()
	state.blood_serial = 0
	state.goal = graph.machine_spot([graph.start_id], rng(state))
	state.phase = BoardState.PHASE_TURNS
	state.active = 0
	state.dice = 0
	state.steps_left = 0
	state.pending_options.clear()
	var events := []
	_begin_turn(state, events)
	return events


static func can_act(state: BoardState, peer_id: int) -> bool:
	var ap := state.active_player()
	return ap != null and ap.peer_id == peer_id and (state.phase == BoardState.PHASE_TURNS or state.phase == BoardState.PHASE_CHOOSING)


static func _begin_turn(state: BoardState, events: Array) -> void:
	state.dice = 0
	state.steps_left = 0
	state.pending_options.clear()
	state.turn_serial += 1
	var ap := state.active_player()
	events.append({"kind": "turn", "peer": ap.peer_id, "round": state.round, "serial": state.turn_serial})


## Items are used before rolling. Returns [] if not allowed. `payload` carries what an item needs
## beyond a target player: the laser's aim angle, the bomb's landing point.
static func use_item(state: BoardState, graph: BoardGraph, cfg: Dictionary, peer_id: int, item: String, target_peer: int, payload: Dictionary = {}) -> Array:
	var events := []
	if state.phase != BoardState.PHASE_TURNS or state.dice != 0:
		return events
	var user := state.active_player()
	if user == null or user.peer_id != peer_id or not user.items.has(item):
		return events
	var items: Dictionary = cfg.get("items", {})
	var def: Dictionary = items.get(item, {})
	if def.is_empty():
		return events
	user.items.erase(item)
	match item:
		"bomb":
			# Thrown (Sean: not targetable; a circle of range, the character throws it, it lands and
			# does AOE damage): it lands at the payload's x/z, held within range_spaces of the
			# thrower; everyone within blast_spaces of the landing, the thrower included, takes HP
			# by distance and is knocked back; a shield eats the hit; a downed player respawns.
			var origin := graph.get_space(user.space)
			if origin == null:
				user.items.append(item)
				return events
			var at := bomb_landing(graph, cfg, origin.position,
				Vector2(float(payload.get("x", origin.position.x)), float(payload.get("z", origin.position.z))))
			var shot := {"kind": "bomb", "peer": user.peer_id, "at": [at.x, at.y, at.z], "radius": bomb_radius(graph, cfg), "hits": []}
			var shields := []
			events.append({"kind": "item_used", "peer": user.peer_id, "item": item, "target": 0})
			for h in bomb_hits(state, graph, cfg, at):
				var victim: BoardState.PlayerState = h["player"]
				var rec := {"peer": victim.peer_id, "damage": int(h["damage"]), "hp": victim.hp, "dead": false, "tickets": 0, "respawn": "", "knock": []}
				if victim.items.has("shield"):
					victim.items.erase("shield")
					rec["damage"] = 0
					rec["shielded"] = true
					shields.append({"kind": "shield", "peer": victim.peer_id, "from": user.peer_id})
				else:
					_hurt(state, graph, cfg, user, victim, int(h["damage"]), float(def.get("death_ticket_share", 0.5)), rec)
					if not bool(rec["dead"]):
						var path := graph.step_back(victim.space, int(def.get("knockback", 3)))
						if not path.is_empty():
							victim.space = path[path.size() - 1]
							rec["knock"] = Array(path)
				(shot["hits"] as Array).append(rec)
			events.append(shot)
			events.append_array(shields)
		"portal":
			# A portal to the picked player: you go through it to them, then push them back through
			# it to where you stood (Sean). The rule is a swap of spaces.
			var target := state.player(target_peer)
			if target == null or target == user:
				user.items.append(item)
				return events
			var mine := user.space
			user.space = target.space
			target.space = mine
			events.append({"kind": "item_used", "peer": user.peer_id, "item": item, "target": target.peer_id})
			events.append({"kind": "portal", "peer": user.peer_id, "target": target.peer_id, "from": mine, "to": user.space})
		"shield":
			# Passive: it is spent when a hit targets its holder. Using it by hand does nothing.
			user.items.append(item)
		"laser":
			# Aimed: every other player in the beam takes damage by distance; a shield eats the hit;
			# at 0 HP the victim hands the shooter a share of their tickets and respawns at the annex
			# that is not the live machine, HP full. Sean: "if they are close enough they lose all
			# their hp"; the respawn spots are his "original two spots".
			var aim := float(payload.get("aim", 0.0))
			var shot := {"kind": "laser", "peer": user.peer_id, "aim": aim, "length": laser_length(graph, cfg), "hits": []}
			var shields := []
			events.append({"kind": "item_used", "peer": user.peer_id, "item": item, "target": 0})
			for h in laser_hits(state, graph, cfg, user, aim):
				var victim: BoardState.PlayerState = h["player"]
				var rec := {"peer": victim.peer_id, "damage": int(h["damage"]), "hp": victim.hp, "dead": false, "tickets": 0, "respawn": ""}
				if victim.items.has("shield"):
					victim.items.erase("shield")
					rec["damage"] = 0
					rec["shielded"] = true
					shields.append({"kind": "shield", "peer": victim.peer_id, "from": user.peer_id})
				else:
					_hurt(state, graph, cfg, user, victim, int(h["damage"]), float(def.get("death_ticket_share", 0.5)), rec)
				(shot["hits"] as Array).append(rec)
			events.append(shot)
			events.append_array(shields)
		"claw":
			# The retractable claw (Sean: it extends along its path and grabs what is in it): aimed
			# like the laser; the first player in the line within range_spaces loses one item at
			# random to the user, or tickets_when_empty tickets when their bar is empty; a shield eats
			# the grab and both are spent; nobody in the path and the claw comes back empty.
			var aim := float(payload.get("aim", 0.0))
			events.append({"kind": "item_used", "peer": user.peer_id, "item": item, "target": 0})
			var grab := {"kind": "claw", "peer": user.peer_id, "aim": aim, "length": claw_length(graph, cfg), "target": 0, "item": "", "tickets": 0}
			var hits := claw_hits(state, graph, cfg, user, aim)
			if hits.is_empty():
				events.append(grab)
				return events
			var target: BoardState.PlayerState = hits[0]["player"]
			grab["target"] = target.peer_id
			grab["along"] = float(hits[0]["along"])
			if target.items.has("shield"):
				target.items.erase("shield")
				grab["shielded"] = true
				events.append(grab)
				events.append({"kind": "shield", "peer": target.peer_id, "from": user.peer_id})
			elif not target.items.is_empty():
				var idx := rng(state).randi_range(0, target.items.size() - 1)
				var stolen := str(target.items[idx])
				target.items.remove_at(idx)
				user.items.append(stolen)
				grab["item"] = stolen
				events.append(grab)
			else:
				var taken := mini(target.tickets, int(def.get("tickets_when_empty", 3)))
				target.tickets -= taken
				user.tickets += taken
				grab["tickets"] = taken
				events.append(grab)
		_:
			user.items.append(item)
	return events


## HP damage from `attacker` to `victim`, written into the hit record: blood on the victim's
## tile, and at 0 HP the victim hands the attacker `share` of their tickets and respawns at the
## machine spot that is not the live machine, HP full. The laser's rule, shared by the bomb.
static func _hurt(state: BoardState, graph: BoardGraph, cfg: Dictionary, attacker: BoardState.PlayerState,
		victim: BoardState.PlayerState, damage: int, share: float, rec: Dictionary) -> void:
	victim.hp = maxi(0, victim.hp - damage)
	rec["hp"] = victim.hp
	rec["blood"] = _add_blood(state, victim.space)
	if victim.hp <= 0:
		rec["dead"] = true
		var taken := int(floor(victim.tickets * share))
		victim.tickets -= taken
		attacker.tickets += taken
		rec["tickets"] = taken
		victim.hp = int(cfg.get("hp", 30))
		victim.space = _respawn_spot(state, graph)
		rec["respawn"] = victim.space


## How far a bomb can be thrown, in metres: `range_spaces` of the board's mean tile spacing.
static func bomb_range(graph: BoardGraph, cfg: Dictionary) -> float:
	var def: Dictionary = (cfg.get("items", {}) as Dictionary).get("bomb", {})
	return float(def.get("range_spaces", 3.0)) * graph.mean_step()


## The blast's radius in metres: `blast_spaces` of the mean tile spacing.
static func bomb_radius(graph: BoardGraph, cfg: Dictionary) -> float:
	var def: Dictionary = (cfg.get("items", {}) as Dictionary).get("bomb", {})
	return float(def.get("blast_spaces", 1.0)) * graph.mean_step()


## Where a throw from `origin` toward `want` (XZ) lands: no farther than the range, at the
## height of the nearest space so the blast sits on the walkway.
static func bomb_landing(graph: BoardGraph, cfg: Dictionary, origin: Vector3, want: Vector2) -> Vector3:
	var v := want - Vector2(origin.x, origin.z)
	var reach := bomb_range(graph, cfg)
	if v.length() > reach:
		v = v.normalized() * reach
	var x := origin.x + v.x
	var z := origin.z + v.y
	var y := origin.y
	var best := 1e18
	for sid in graph.ids():
		var s := graph.get_space(str(sid))
		if s == null:
			continue
		var d := Vector2(s.position.x - x, s.position.z - z).length_squared()
		if d < best:
			best = d
			y = s.position.y
	return Vector3(x, y, z)


## Who a bomb landing at `at` hurts, nearest first: [{player, dist, damage}]. Everyone whose
## space lies within the blast, the thrower not excepted; `damage_close` at the centre falling
## linearly to `damage_far` at the edge.
static func bomb_hits(state: BoardState, graph: BoardGraph, cfg: Dictionary, at: Vector3) -> Array:
	var out := []
	var def: Dictionary = (cfg.get("items", {}) as Dictionary).get("bomb", {})
	if def.is_empty():
		return out
	var radius := bomb_radius(graph, cfg)
	var d_close := float(def.get("damage_close", 20))
	var d_far := float(def.get("damage_far", 8))
	for p in state.players:
		var sp := graph.get_space(p.space)
		if sp == null:
			continue
		var d := Vector2(sp.position.x - at.x, sp.position.z - at.z).length()
		if d > radius:
			continue
		var t := clampf(d / maxf(radius, 0.001), 0.0, 1.0)
		out.append({"player": p, "dist": d, "damage": int(round(lerpf(d_close, d_far, t)))})
	out.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	return out


## The beam's reach in metres: `length_spaces` of the board's mean tile spacing.
static func laser_length(graph: BoardGraph, cfg: Dictionary) -> float:
	var def: Dictionary = (cfg.get("items", {}) as Dictionary).get("laser", {})
	return float(def.get("length_spaces", 3.0)) * graph.mean_step()


## Who a laser from `shooter` at `aim` (radians in the XZ plane, atan2(dz, dx)) hits, nearest
## first: [{player, along, damage}]. Damage is `damage_close` out to `close_spaces`, then falls
## linearly to `damage_far` at the end of the beam.
static func laser_hits(state: BoardState, graph: BoardGraph, cfg: Dictionary, shooter: BoardState.PlayerState, aim: float) -> Array:
	var out := []
	var def: Dictionary = (cfg.get("items", {}) as Dictionary).get("laser", {})
	if def.is_empty():
		return out
	var length := laser_length(graph, cfg)
	var close := float(def.get("close_spaces", 1.0)) * graph.mean_step()
	var d_close := float(def.get("damage_close", 30))
	var d_far := float(def.get("damage_far", 10))
	for h in _players_in_line(state, graph, shooter, aim, length, float(def.get("width", 1.4)) * 0.5):
		var along := float(h["along"])
		var t := 0.0 if along <= close else clampf((along - close) / maxf(length - close, 0.001), 0.0, 1.0)
		out.append({"player": h["player"], "along": along, "damage": int(round(lerpf(d_close, d_far, t)))})
	return out


## The claw's reach in metres: `range_spaces` of the board's mean tile spacing.
static func claw_length(graph: BoardGraph, cfg: Dictionary) -> float:
	var def: Dictionary = (cfg.get("items", {}) as Dictionary).get("claw", {})
	return float(def.get("range_spaces", 3.0)) * graph.mean_step()


## Who a claw from `user` at `aim` reaches, nearest first: [{player, along}]; the first is the
## one it grabs from. The same line test as the laser's.
static func claw_hits(state: BoardState, graph: BoardGraph, cfg: Dictionary, user: BoardState.PlayerState, aim: float) -> Array:
	var def: Dictionary = (cfg.get("items", {}) as Dictionary).get("claw", {})
	if def.is_empty():
		return []
	return _players_in_line(state, graph, user, aim, claw_length(graph, cfg), float(def.get("width", 1.4)) * 0.5)


## The players whose space lies within `half_w` of a straight line from `shooter`'s space at
## `aim` (radians in the XZ plane, atan2(dz, dx)), out to `length`, nearest first:
## [{player, along}]. Players on the shooter's own space are beside the hand, not in front of it.
static func _players_in_line(state: BoardState, graph: BoardGraph, shooter: BoardState.PlayerState, aim: float, length: float, half_w: float) -> Array:
	var out := []
	var origin := graph.get_space(shooter.space)
	if origin == null:
		return out
	var dir := Vector2(cos(aim), sin(aim))
	for p in state.players:
		if p == shooter:
			continue
		var sp := graph.get_space(p.space)
		if sp == null:
			continue
		var v := Vector2(sp.position.x - origin.position.x, sp.position.z - origin.position.z)
		var along := v.dot(dir)
		var across := absf(v.x * dir.y - v.y * dir.x)
		if along < 0.3 or along > length or across > half_w:
			continue
		out.append({"player": p, "along": along})
	out.sort_custom(func(a, b): return float(a["along"]) < float(b["along"]))
	return out


## Where a downed player comes back: a machine spot that is not the live machine (so dying never
## hands you the machine), the start when the board has no other.
static func _respawn_spot(state: BoardState, graph: BoardGraph) -> String:
	var spots := []
	for c in graph.goal_candidates():
		if str(c) != state.goal:
			spots.append(str(c))
	if spots.is_empty():
		return graph.start_id
	spots.sort()
	return spots[rng(state).randi_range(0, spots.size() - 1)]


## A blood splat record on the victim's space, kept in the state so every peer draws the same
## one and it survives the board being rebuilt. Capped so the state stays small.
static func _add_blood(state: BoardState, space_id: String) -> Dictionary:
	var r := rng(state)
	state.blood_serial += 1
	var entry := {"n": state.blood_serial, "space": space_id, "a": r.randf_range(0.0, TAU),
		"r": r.randf_range(0.45, 0.8), "seed": r.randi_range(0, 9999)}
	state.blood.append(entry)
	while state.blood.size() > 24:
		state.blood.pop_front()
	return entry


static func roll(state: BoardState, graph: BoardGraph, cfg: Dictionary) -> Array:
	var events := []
	if state.phase != BoardState.PHASE_TURNS or state.dice != 0:
		return events
	var ap := state.active_player()
	var r := rng(state)
	var raw := r.randi_range(1, int(cfg.get("dice_sides", 8)))
	state.dice = raw
	state.steps_left = state.dice
	events.append({"kind": "roll", "peer": ap.peer_id, "value": state.dice, "roll": raw})
	_move_continue(state, graph, cfg, events)
	return events


static func choose(state: BoardState, graph: BoardGraph, cfg: Dictionary, option_index: int) -> Array:
	var events := []
	if state.phase != BoardState.PHASE_CHOOSING or state.pending_options.is_empty():
		return events
	var idx := clampi(option_index, 0, state.pending_options.size() - 1)
	var ap := state.active_player()
	if state.pending_kind == "shuttle":
		# The rocket's offer: stay (the move goes on from the pad) or pay the fare and fly to the
		# landing spot, no steps spent on the flight (Sean, 2026-09-24).
		var to := state.pending_options[1]
		state.pending_options.clear()
		state.pending_kind = ""
		state.phase = BoardState.PHASE_TURNS
		if idx == 1 and ap.tickets >= graph.shuttle_price:
			ap.tickets -= graph.shuttle_price
			ap.space = to
			events.append({"kind": "shuttle", "peer": ap.peer_id, "from": graph.shuttle_from, "to": to,
				"price": graph.shuttle_price, "total": ap.tickets})
		_move_continue(state, graph, cfg, events)
		return events
	var dest := state.pending_options[idx]
	state.pending_options.clear()
	state.phase = BoardState.PHASE_TURNS
	_enter(state, graph, cfg, ap, dest, events)
	if state.phase == BoardState.PHASE_FINISHED:
		return events
	state.steps_left -= 1
	if _offer_shuttle(state, graph, events):
		return events
	_move_continue(state, graph, cfg, events)
	return events


## The vending machine (state.goal is the space it stands beside): passing it or landing on it
## with at least `toy_price` tickets pays, hands out a toy, and moves the machine to the spot
## farthest from where everyone is. The first player to `toys_to_win` toys ends the match there
## and then (0 means never: only the round cap ends it).
static func _enter(state: BoardState, graph: BoardGraph, cfg: Dictionary, p: BoardState.PlayerState, space_id: String, events: Array) -> void:
	p.space = space_id
	_append_move(events, p.peer_id, space_id)
	if space_id == state.goal and p.tickets >= int(cfg.get("toy_price", 10)):
		p.tickets -= int(cfg.get("toy_price", 10))
		p.toys += 1
		var occupied := []
		for q in state.players:
			occupied.append(q.space)
		state.goal = graph.machine_spot(occupied, rng(state), space_id)
		events.append({"kind": "toy", "peer": p.peer_id, "toys": p.toys, "tickets": p.tickets, "spot": space_id, "new_spot": state.goal})
		var to_win := int(cfg.get("toys_to_win", 4))
		if to_win > 0 and p.toys >= to_win:
			_finish(state, events)


static func _finish(state: BoardState, events: Array) -> void:
	state.phase = BoardState.PHASE_FINISHED
	state.steps_left = 0
	state.pending_options.clear()
	state.pending_kind = ""
	var order := []
	for q in state.standings():
		order.append(q.peer_id)
	events.append({"kind": "finished", "order": order})


static func _append_move(events: Array, peer_id: int, space_id: String) -> void:
	if not events.is_empty():
		var last: Dictionary = events[events.size() - 1]
		if last.get("kind") == "move" and int(last.get("peer")) == peer_id and not bool(last.get("backwards", false)):
			(last["path"] as Array).append(space_id)
			return
	events.append({"kind": "move", "peer": peer_id, "path": [space_id]})


static func _move_continue(state: BoardState, graph: BoardGraph, cfg: Dictionary, events: Array) -> void:
	var ap := state.active_player()
	while state.steps_left > 0:
		var options := graph.next_of(ap.space)
		if options.is_empty():
			state.steps_left = 0
			break
		if options.size() > 1:
			state.phase = BoardState.PHASE_CHOOSING
			state.pending_options = options
			events.append({"kind": "choose", "peer": ap.peer_id, "options": Array(options)})
			return
		_enter(state, graph, cfg, ap, options[0], events)
		if state.phase == BoardState.PHASE_FINISHED:
			return   # the winning toy ends the match where it was bought
		state.steps_left -= 1
		if _offer_shuttle(state, graph, events):
			return
	_land(state, graph, cfg, events)
	_end_turn(state, events)


## The rocket (BOARDPLAN.md §1, Sean's drawing): reaching its pad space, landing there or passing
## through, with the fare in hand pauses the move to ask: stay, or fly to the landing spot on
## the far side. The offer is a choice like a fork's, `pending_kind` "shuttle", its options the
## pad (stay) and the landing spot (fly).
static func _offer_shuttle(state: BoardState, graph: BoardGraph, events: Array) -> bool:
	var ap := state.active_player()
	if graph.shuttle_from == "" or ap.space != graph.shuttle_from or ap.tickets < graph.shuttle_price:
		return false
	state.phase = BoardState.PHASE_CHOOSING
	state.pending_kind = "shuttle"
	state.pending_options = PackedStringArray([ap.space, graph.shuttle_to])
	events.append({"kind": "choose", "peer": ap.peer_id, "options": [ap.space, graph.shuttle_to], "shuttle": true, "price": graph.shuttle_price})
	return true


static func _land(state: BoardState, graph: BoardGraph, cfg: Dictionary, events: Array) -> void:
	var ap := state.active_player()
	var space := graph.get_space(ap.space)
	if space == null:
		return
	var effects: Dictionary = cfg.get("space_effects", {})
	match space.type:
		"ticket":
			var delta := int(effects.get("ticket", 3))
			var before := ap.tickets
			ap.tickets = maxi(0, ap.tickets + delta)
			events.append({"kind": "tickets", "peer": ap.peer_id, "delta": ap.tickets - before, "total": ap.tickets})
		"lose":
			# Damage. A shield (the shield space, or the item) takes it instead of the tickets.
			if ap.items.has("shield"):
				ap.items.erase("shield")
				events.append({"kind": "shield", "peer": ap.peer_id, "from": 0})
			else:
				var delta := int(effects.get("lose", -3))
				var before := ap.tickets
				ap.tickets = maxi(0, ap.tickets + delta)
				events.append({"kind": "tickets", "peer": ap.peer_id, "delta": ap.tickets - before, "total": ap.tickets})
		"shield":
			# The one safe spot: you leave it invulnerable to the next hit (bomb or damage space).
			if not ap.items.has("shield"):
				ap.items.append("shield")
				events.append({"kind": "item", "peer": ap.peer_id, "item": "shield"})
		"item":
			var names := (cfg.get("items", {}) as Dictionary).keys()
			if not names.is_empty():
				names.sort()
				var item: String = names[rng(state).randi_range(0, names.size() - 1)]
				ap.items.append(item)
				events.append({"kind": "item", "peer": ap.peer_id, "item": item})


static func _end_turn(state: BoardState, events: Array) -> void:
	state.active += 1
	state.dice = 0
	state.steps_left = 0
	if state.active >= state.players.size():
		state.active = 0
		state.phase = BoardState.PHASE_MINIGAME
		events.append({"kind": "minigame", "round": state.round})
		return
	state.phase = BoardState.PHASE_TURNS
	_begin_turn(state, events)


## ranked_peer_ids: winner first. Pays tickets, gives the winner an item, advances the round.
static func apply_minigame(state: BoardState, cfg: Dictionary, ranked_peer_ids: Array) -> Array:
	var events := []
	if state.phase != BoardState.PHASE_MINIGAME:
		return events
	var rewards: Dictionary = cfg.get("rewards", {})
	var by_rank: Array = rewards.get("tickets_by_rank", [10, 6, 4, 2, 2, 2])
	state.last_ranking = ranked_peer_ids.duplicate()
	for i in ranked_peer_ids.size():
		var p := state.player(int(ranked_peer_ids[i]))
		if p == null:
			continue
		var delta := int(by_rank[mini(i, by_rank.size() - 1)]) if not by_rank.is_empty() else 0
		p.tickets += delta
		events.append({"kind": "tickets", "peer": p.peer_id, "delta": delta, "total": p.tickets, "rank": i + 1})
		if i == 0 and bool(rewards.get("winner_item", true)):
			var names := (cfg.get("items", {}) as Dictionary).keys()
			if not names.is_empty():
				names.sort()
				var item: String = names[rng(state).randi_range(0, names.size() - 1)]
				p.items.append(item)
				# "reward": the HUD shows this one over the winner's head when their turn comes.
				events.append({"kind": "item", "peer": p.peer_id, "item": item, "reward": true})
	# The turn order follows the ranking (Sean): the winner rolls first next round, second
	# second, and so on; anyone the ranking left out keeps their place at the back.
	var ordered: Array[BoardState.PlayerState] = []
	for pid in ranked_peer_ids:
		var p := state.player(int(pid))
		if p != null and not ordered.has(p):
			ordered.append(p)
	for p in state.players:
		if not ordered.has(p):
			ordered.append(p)
	state.players = ordered
	state.round += 1
	if state.rounds > 0 and state.round > state.rounds:
		_finish(state, events)
		return events
	state.phase = BoardState.PHASE_TURNS
	state.active = 0
	_begin_turn(state, events)
	return events


static func bot_choose(state: BoardState, graph: BoardGraph) -> int:
	if state.pending_kind == "shuttle":
		# The rocket: worth the fare when it brings the machine BOT_SHUTTLE_MIN_GAIN hops nearer.
		var d_stay := graph.distance(state.pending_options[0], state.goal)
		var d_fly := graph.distance(state.pending_options[1], state.goal)
		return 1 if d_fly >= 0 and d_stay - d_fly >= BOT_SHUTTLE_MIN_GAIN else 0
	var best := 0
	var best_d := 1 << 30
	for i in state.pending_options.size():
		var d := graph.distance(state.pending_options[i], state.goal)
		if d < 0:
			d = 1 << 20
		if d < best_d:
			best_d = d
			best = i
	return best


## [item, target_peer, payload] or [] when the bot passes. `cfg` is needed for the laser, the
## bomb and the claw (their reach is a tuning number); without it the bot only portals.
static func bot_item(state: BoardState, graph: BoardGraph = null, cfg: Dictionary = {}) -> Array:
	var me := state.active_player()
	if me == null:
		return []
	if me.items.has("laser") and graph != null and not cfg.is_empty():
		# Aim straight at each other player in turn and take the shot that does the most damage.
		var origin := graph.get_space(me.space)
		var best_total := 0
		var best_peer := 0
		var best_aim := 0.0
		if origin != null:
			for p in state.players:
				if p == me:
					continue
				var sp := graph.get_space(p.space)
				if sp == null:
					continue
				var aim := atan2(sp.position.z - origin.position.z, sp.position.x - origin.position.x)
				var total := 0
				for h in laser_hits(state, graph, cfg, me, aim):
					total += int(h["damage"])
				if total > best_total:
					best_total = total
					best_peer = p.peer_id
					best_aim = aim
		if best_total > 0:
			return ["laser", best_peer, {"aim": snappedf(best_aim, 0.001)}]
	if me.items.has("bomb") and graph != null and not cfg.is_empty():
		# Throw at whichever other player's space hurts the most, never where the blast reaches itself.
		var origin := graph.get_space(me.space)
		var best_total := 0
		var best_at := Vector3.ZERO
		if origin != null:
			for p in state.players:
				if p == me:
					continue
				var sp := graph.get_space(p.space)
				if sp == null:
					continue
				var at := bomb_landing(graph, cfg, origin.position, Vector2(sp.position.x, sp.position.z))
				var total := 0
				for h in bomb_hits(state, graph, cfg, at):
					if h["player"] == me:
						total = 0
						break
					total += int(h["damage"])
				if total > best_total:
					best_total = total
					best_at = at
		if best_total > 0:
			return ["bomb", 0, {"x": snappedf(best_at.x, 0.01), "z": snappedf(best_at.z, 0.01)}]
	if me.items.has("claw") and graph != null and not cfg.is_empty():
		# Aim at each other player in turn and grab from whoever comes first in that line with the
		# most to lose: a laser first, then the fullest bar, then tickets; never a shield, which
		# would only eat the claw.
		var origin := graph.get_space(me.space)
		var best_score := 0
		var best_aim := 0.0
		if origin != null:
			for p in state.players:
				if p == me:
					continue
				var sp := graph.get_space(p.space)
				if sp == null:
					continue
				var aim := atan2(sp.position.z - origin.position.z, sp.position.x - origin.position.x)
				var hits := claw_hits(state, graph, cfg, me, aim)
				if hits.is_empty():
					continue
				var first: BoardState.PlayerState = hits[0]["player"]
				var score := 0
				if first.items.has("shield"):
					score = 0
				elif not first.items.is_empty():
					score = first.items.size() * 10 + (100 if first.items.has("laser") else 0)
				else:
					score = mini(first.tickets, 3)
				if score > best_score:
					best_score = score
					best_aim = aim
		if best_score > 0:
			return ["claw", 0, {"aim": snappedf(best_aim, 0.001)}]
	if me.items.has("portal") and graph != null and state.goal != "":
		# Portal to whoever stands clearly nearer the goal than we do.
		var my_d := graph.distance(me.space, state.goal)
		if my_d < 0:
			my_d = 1 << 20
		var best: BoardState.PlayerState = null
		var best_d := my_d - int(BOT_PORTAL_MIN_GAIN)
		for p in state.players:
			if p == me:
				continue
			var d := graph.distance(p.space, state.goal)
			if d >= 0 and d <= best_d:
				best_d = d
				best = p
		if best != null:
			return ["portal", best.peer_id, {}]
	return []
