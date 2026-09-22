# BOMBA — MINIGAMES.md

The minigame contract and every minigame's rules, written before the code (DESIGN.md §8). A
minigame is a folder under `minigames/` that the registry finds on its own; the board draws one
per round (never the same twice in a row when there is a choice), `--minigame=ID` pins it.

## 1. The contract

`minigames/<id>/manifest.json` declares `id`, `display_name`, `tagline` (one line under GET
READY), `min_players`, `max_players`, `camera`, `scoring`, `time_limit_seconds`, `weapons`,
`bot_profile`, `scene`. The scene's root script extends `Minigame`: it receives `setup(players,
seed, config)` on every peer and returns a ranked `MinigameResult` through `finished`. It never
reaches into board, session or item state.

First-person minigames extend `FpsMatch` (`fps/match/fps_match.gd`), which builds the map from a
layout table, spawns everyone, drives the bots and runs the clock, and expose their rules through
hooks: `_layout()`, `_palette_map()`, `_respawns()`, `_score_for(player)`, `_score_label(player)`,
`centre_text()` (what the HUD prints instead of DOWN), `hud_status()` (lines the HUD prints at the
top centre), `hud_score(player)` and `hud_score_header()` (the big number top-right and the
scoreboard column), `objective_position()` (where the bots go when nobody is in sight; `INF` for
none). A minigame with no map of its own uses the ARENA layout (`GrayboxLayout`); LAST STAND
carries `pit_layout.gd`.

## 2. The minigames

| Minigame | Rules | Clock | Scoring |
|---|---|---|---|
| ARENA | free-for-all, sniper and AR, instant respawn with protection | 180 s | kills |
| SNIPERS | bolt-action only | 150 s | kills, headshots count double |
| LAST STAND | one life each, the dusk pit, the dead spectate | 60 s | survival: the later you fell the higher; alive at the clock ties for first |
| KING OF THE HILL | a hill that moves; seconds alone inside it score; a minute wins outright | 150 s | hill seconds |

## 3. KING OF THE HILL (plan, 2026-09-22)

Halo's king of the hill on the ARENA map, the objective minigame the SDK had been waiting on
(`scoring` had kills and survival behind it, nothing territorial).

- **The hill** is a cylinder (`hill.radius_m` 2.8 by default, per spot in the layout; `hill.height_m` 3 tall from 0.3 m
  under its floor) at one of the layout's `hills` spots: on BOMBA's arena the tower top, both
  roofs, the catwalk, the south and north lanes, the west and east lanes (eight). It moves every
  `hill.move_every_seconds` (30) to the next spot of a seeded order that visits every spot before
  repeating and never repeats the spot just left. The host announces each move reliably
  (`_rpc_hill`), so clients never compute it.
- **Scoring**, on the host, one sample per tick from the authoritative states: the living players
  inside the hill. Exactly one inside scores a tick; two or more is contested and scores nobody;
  empty scores nobody. `hill.win_seconds` (60) alone ends the round on the spot; otherwise the clock
  ends it and hill seconds rank, ties shared. Kills still show in the feed and the scoreboard but
  do not score.
- **Replication**: the host sends the holder and everyone's hill ticks ten times a second
  (unreliable) and reliably on every move and at the end; clients only display.
- **Seen**: a translucent glass cylinder on a ring, the ring and a pennant in the holder's colour
  (the score colour when empty, the danger red when contested), a beam up so the hill can be found
  over the walls, a burst and a two-note chime when it moves, a soft tick every second you score.
  HUD: top centre "KING: YOU / BOT LEMON / CONTESTED / HILL OPEN" with your time, the lead and
  the seconds to the next move; the big number top-right is your hill time; the scoreboard's
  column is HILL.
- **Bots**: when nobody is in sight a bot heads for the waypoint nearest the hill with probability
  `hill.bot_hill_weight` (0.85 per repath) and then walks to the hill's centre and holds there,
  strafing; an enemy in sight is fought as before.
- **Harness**: `--minigame=hill`, `--hill_index=N` pins the first spot, `--screenshot_event=hill`
  arms on a move (`--screenshot_event_index=N` for the Nth).
- **Verified** (2026-09-22): five `HillRules` tests (inside, holder, the order, the seed, the clock
  format); a headless four-seat 70 s round: three placements (spots 7, 2, 0), moves at ticks 1980
  and 3780, result BOT MAGENTA 790 ticks, BOT LEMON 615, BOT TANGERINE 266, Player 76 0; frames at
  1080p in `docs/screenshots/hill_spectator.png` (the hill on the tower, its beam), `hill_hip.png`
  (the hill held, the status lines) and `hill_scoreboard.png` (the HILL column);
  `tools/check_all.sh` with HILL in the board rotation. Sean's verdict on the mode is pending.
- **Known**: the roofs are bot-free spots (no roof waypoints); "KING OF THE HILL" is a long name for
  the board's NEXT UP card.
