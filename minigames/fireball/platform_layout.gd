class_name PlatformLayout
extends RefCounted
## FIREBALL's map (Sean, 2026-09-24: "a large dark grey circular platform that we all spawn on,
## evenly away from each other"): one round platform in the sky and nothing else. The spawns
## stand on a ring inside the rim, as many as there are seats and evenly spaced, each facing the
## centre. The waypoints are the centre and a ring, for anything that walks the graph (the
## fireball bots pick their own spots). The showcase vantage is the briefing's orbit.


static func build(cfg: Dictionary, seats: int) -> Dictionary:
	var r := float(cfg.get("platform_radius_m", 17.0))
	var thick := float(cfg.get("platform_thickness_m", 1.6))
	var spawn_r := float(cfg.get("spawn_radius_m", 11.0))
	var boxes: Array = []
	# The platform: its top at y = 0, the paving print on it (tone "floor"); a narrower drum
	# under it so it reads as a thing floating in the sky, not a slab cut off by the frame.
	boxes.append({"pos": Vector3(0.0, -thick * 0.5, 0.0), "size": Vector3(r * 2.0, thick, r * 2.0), "tone": "floor", "shape": "cylinder", "segments": 64})
	boxes.append({"pos": Vector3(0.0, -thick - 1.2, 0.0), "size": Vector3(r * 1.5, 2.4, r * 1.2), "tone": "counter_dark", "shape": "cylinder", "segments": 48})
	boxes.append({"pos": Vector3(0.0, -thick - 3.4, 0.0), "size": Vector3(r * 0.9, 2.0, r * 0.5), "tone": "counter_dark", "shape": "cylinder", "segments": 32})

	var spawns: Array = []
	var n := maxi(seats, 2)
	for i in n:
		var a := TAU * float(i) / float(n) - PI * 0.5
		var p := Vector3(cos(a) * spawn_r, 0.0, sin(a) * spawn_r)
		spawns.append({"pos": p, "yaw": atan2(p.x, p.z)})   # forward = -p: facing the centre

	var wp: Array = [Vector3.ZERO]
	var edges: Array = []
	var ring := 8
	for i in ring:
		var a := TAU * float(i) / float(ring)
		wp.append(Vector3(cos(a) * r * 0.55, 0.0, sin(a) * r * 0.55))
		edges.append([0, i + 1])
		edges.append([i + 1, (i + 1) % ring + 1])

	# Decor: a dashed ring near the rim and a disc at the centre, both flush with the top, in the
	# lighter greys, so the platform's size and its middle (where the ball appears) read.
	var decor: Array = []
	var dashes := int(TAU * (r - 1.4) / 3.0)   # one every 3 m of rim, whatever the radius
	for i in dashes:
		var a := TAU * float(i) / float(dashes)
		var d := r - 1.4
		decor.append({"pos": Vector3(cos(a) * d, 0.012, sin(a) * d), "size": Vector3(1.4, 0.024, 0.28), "tone": "counter", "yaw": -a, "shape": "box", "shadow": false})
	decor.append({"pos": Vector3(0.0, 0.01, 0.0), "size": Vector3(5.0, 0.02, 5.0), "tone": "counter_dark", "shape": "cylinder", "shadow": false})
	decor.append({"pos": Vector3(0.0, 0.02, 0.0), "size": Vector3(1.2, 0.02, 1.2), "tone": "counter", "shape": "cylinder", "shadow": false})
	for i in 4:
		var a := TAU * float(i) / 4.0
		decor.append({"pos": Vector3(cos(a) * 1.9, 0.02, sin(a) * 1.9), "size": Vector3(1.0, 0.02, 0.16), "tone": "counter", "yaw": -a, "shape": "box", "shadow": false})
	var showcase := {"pos": Vector3(-1.3 * r, 0.53 * r, 1.53 * r), "look": Vector3(0.0, 1.5, 0.0)}   # the briefing's orbit, scaled with the platform
	return {"boxes": boxes, "spawns": spawns, "waypoints": wp, "edges": edges, "size": Vector2(r * 2.0, r * 2.0), "decor": decor, "showcase": showcase}
