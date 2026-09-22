extends Node
## The event bus. Autoload `Events`. Modules talk through these signals, never by reaching into
## each other's folders.

# Session / flow
signal session_changed()
signal minigame_started(id: String)
signal minigame_finished(result: MinigameResult)
signal error_banner(text: String)

# Gameplay facts (authoritative, broadcast by the server)
signal kill(killer_id: int, victim_id: int, weapon: String, headshot: bool, tick: int)
signal round_started(end_tick: int)
signal round_ended()

# Local feedback (this machine only, predicted)
signal local_fired(weapon: String)
signal local_shot_fx(origin: Vector3, point: Vector3, hit_kind: int)
signal local_hit_predicted(kind: int, victim_id: int)
signal local_damaged(amount: int, from_id: int)
signal local_died()
signal local_respawned()
signal local_weapon_changed(weapon: String)
signal local_weapon_event(name: String)   # reload_started, reload_finished, dry_fire, swapped
signal local_footstep()
signal local_jump()
signal local_land()
signal remote_shot(weapon: String, origin: Vector3)
signal ui_sound(name: String)
signal board_dice_landed(value: int)   # the 3D die has settled; HUD shows the number now
signal board_item_picked(peer_id: int, item: String, at_turn: bool)   # the view plays an item pickup; the HUD pops the icon now, or at that player's next turn
signal board_turn_shown(peer_id: int)   # the view has moved the camera to the player whose turn began

# Diagnostics
signal net_stats(stats: Dictionary)
