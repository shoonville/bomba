# BOMBA — MINIGAMES.md

The minigame contract and every minigame's rules, written before the code (DESIGN.md §8). A
minigame is a folder under `minigames/` that the registry finds on its own; the board draws one
per round (never the same twice in a row when there is a choice), `--minigame=ID` pins it. A
manifest with `"enabled": false` parks a minigame: the board never draws it, the pin still works
(ARENA and SNIPERS since 2026-09-24, Sean: "disable SNIPERS and ARENA for now").

## 1. The contract

`minigames/<id>/manifest.json` declares `id`, `display_name`, `tagline` (one line under GET
READY), `min_players`, `max_players`, `camera`, `scoring`, `time_limit_seconds`, `weapons`,
`bot_profile`, `scene`, `enabled`, and for the briefing before the round `description` (how it
plays, a few lines) and `controls` (a list of "KEY  what it does"). The scene's root script
extends `Minigame`: it receives `setup(players, seed, config)` on every peer and returns a ranked
`MinigameResult` through `finished`. It never reaches into board, session or item state.

First-person minigames extend `FpsMatch` (`fps/match/fps_match.gd`), which builds the map from a
layout table, spawns everyone, drives the bots and runs the clock, and expose their rules through
hooks: `_layout()`, `_palette_map()`, `_dress_map()` (the city round the map, off for a map that is
not a city), `_movement_overrides()` (keys of `tuning/movement.json` the minigame changes: FIREBALL's
half gravity), `_make_brain()` (the bots' and the `--autoplay` seat's brain, `BotBrain` unless the
minigame has its own), `_respawns()`, `_score_for(player)`, `_score_label(player)`,
`_kill_weapon_id(victim, kind, slot)` (what the feed and the result name a death by, for a minigame
with killers that are not weapons), `build_visuals()` (the look, built one chunk per frame under the
held wipe after `setup()`), `centre_text()` (what the HUD prints instead of DOWN), `hud_status()`
(lines the HUD prints at the top centre), `hud_score(player)` and `hud_score_header()` (the big number
top-right and the scoreboard column), `objective_position()` (where the bots go when nobody is in
sight; `INF` for none), and for the final-kill cam `killcam_place(pt)`, `killcam_fire(weapon)` and
`killcam_end()` (anything else in the shot, replayed to where it was). A minigame with no map of its
own uses the ARENA layout (`GrayboxLayout`); LAST STAND carries `pit_layout.gd`, FIREBALL
`platform_layout.gd`. A layout box with `"shape": "cylinder"` is round (the platform).

## 2. The minigames

| Minigame | Rules | Clock | Scoring |
|---|---|---|---|
| ARENA (parked) | free-for-all, sniper and AR, instant respawn with protection | 180 s | kills |
| SNIPERS (parked) | bolt-action only | 150 s | kills, headshots count double |
| LAST STAND | one life each, the dusk pit, the dead spectate | 60 s | survival: the later you fell the higher; alive at the clock ties for first |
| FIREBALL | one life each on a platform in the sky; a fireball hunts you, the katana reflects it | 120 s | survival, as LAST STAND; the HUD's number is reflects made |

## 3. FIREBALL

Sean's Genji Ball (2026-09-24). Every number is in `tuning/fireball.json`; the katana's are in
`tuning/weapons.json` under `katana`.

- **The map**: one round platform (radius 34 m, doubled on his 2026-09-25 note, its top at y = 0, dark grey with the paving print,
  a dashed ring inside the rim and a disc at the centre) floating in the board's pink sky, no walls.
  Everyone spawns on a ring (22 m) evenly spaced, facing the centre, as many spawns as seats. Off
  the platform is out (a fall past y = −14 m; the feed says FELL). Gravity is a quarter of the
  shared movement's (3.125 m/s²: half on 2026-09-24, halved again on his 2026-09-25 note) with the
  same jump, so a jump goes 5.95 m instead of 1.49 and hangs 3.9 s.
- **The katana** (weapon model `melee`, the only weapon): RIGHT CLICK opens the reflect window
  (`parry_ticks` 18 = 0.3 s) and starts its cooldown (`parry_cooldown_ticks` 54 = 0.9 s, press to
  press; holding the button re-opens it whenever it is ready). LEFT CLICK swings the blade
  (`swing_ticks` 24); the swing hits nothing, the ball is the only thing that kills. The window
  and the cooldown are rollback state (`Weapons:parry_since_tick`, `Weapons:parry_ready_tick`);
  the swing is not.
- **The ball**: appears 12 m over the centre (6 m until 2026-09-25) when the GET READY countdown ends, hovers 0.75 s, then
  flies at a player drawn from the living (seeded) at `speed_start_m_s` 9, homing on their chest
  (`aim_height_m` 1.1) at `homing_turn_deg_s` 160. It is a light-blue orb in an aura of the same blue with arcs flickering over it (Sean,
  2026-09-25: "an electrifying orb, keep it the same color"; flame tongues until then), drawn on every peer from
  the host's state (sent every tick, unreliable, dead-reckoned between), its events (spawn,
  launch, reflect, hit, vanish) reliable for the look and the sounds.
- **The reflect**: a ball passing through an open window, within `parry_range_m` 3.2 of the eye and
  `parry_cone_deg` 75 of the aim, leaves along that player's crosshair at whoever is nearest that
  line (`FireballSim.pick_reflect_target`), 1.5 m/s faster each time (`speed_gain_per_reflect_m_s`,
  capped at `speed_max_m_s` 34). One press reflects once (the window that sent it is remembered),
  and the reflector cannot be hit by the ball it just sent for `reflect_immunity_ticks` 12.
- **The hit**: a ball whose step touches a body capsule or head sphere (`ball_radius_m` 0.45)
  kills; the kill is the last reflector's (the feed: NAME ▸ NAME  FIREBALL, or world's for an
  unreflected ball). The ball is gone for `respawn_delay_seconds` 1.5 and comes back over the
  centre at the start speed, hunting again, until one player is left (or the clock: survivors tie).
- **Netcode**: the ball is simulated on the host only, once per tick inside the tick loop
  (`NetworkRollback.after_process_tick`, after every player's tick), against the players' state as
  the host holds it; a client's press reaches the host with its input, so its reflect counts when
  the press arrives while the ball is still in range. Kills go through `Player.take_damage` like a
  shot's, so the feed, the scoring, the spectator and the final-kill cam are the shared match's;
  the kill cam replays the ball from a per-tick buffer (`killcam_place`).
- **Bots** (`FireballBrain`, also the `--autoplay` seat): wander inside 0.7 of the radius, watch
  the ball, and when it turns on them decide after `reaction_ms` to reflect (`parry_chance`: turn
  to a player inside the cone and press `press_seconds` before it arrives), dodge (`dodge_chance`:
  a sidestep and a jump, away from the rim) or freeze.
